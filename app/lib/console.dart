// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_super_parameters
import 'package:flutter/material.dart';

import 'case_screen.dart';
import 'eco_api.dart';
import 'panels.dart';
import 'theme.dart';

const double consoleBreakpoint = 1320;

BoxDecoration cardDeco() => BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tone.line));

int numOf(Map<String, dynamic> m, String k) => m[k] is num ? (m[k] as num).toInt() : 0;

String caseMeta(CaseSummary c) {
  final credits = c.creditsAtRisk == 1 ? '1 credit' : '${c.creditsAtRisk} credits';
  return '$credits · ${fmtInt(c.tonnesAtRisk)} t · ${c.projects.join(', ')}';
}

class CaseCard extends StatelessWidget {
  final CaseSummary c;
  final VoidCallback onTap;
  const CaseCard({required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final open = c.status == 'open';
    return Material(
      color: Tone.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: Tone.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              open ? bandStamp(c.band) : decidedStamp(c.status),
              Spacer(),
              Text(c.score.toStringAsFixed(3), style: mono(22, weight: FontWeight.w700, color: open ? bandColor(c.band) : Tone.ink3)),
            ]),
            SizedBox(height: 10),
            Text(c.title, style: sans(17, weight: FontWeight.w700, height: 22 / 17)),
            if (c.summary.isNotEmpty) ...[
              SizedBox(height: 4),
              Text(c.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: sans(14, color: Tone.ink2, height: 20 / 14)),
            ],
            SizedBox(height: 10),
            TickMeter(value: c.score, color: open ? bandFill(c.band) : Tone.ink3),
            SizedBox(height: 10),
            Text(caseMeta(c), style: mono(12, color: Tone.ink3)),
            if (open && c.proposal != null) ...[SizedBox(height: 8), ProposalTag(p: c.proposal!)],
          ]),
        ),
      ),
    );
  }
}

class ReviewConsole extends StatefulWidget {
  final EcoApi api;
  final Map<String, dynamic> stats;
  final List<CaseSummary> cases;
  final Future<void> Function() onChanged;
  const ReviewConsole({Key? key, required this.api, required this.stats, required this.cases, required this.onChanged}) : super(key: key);
  @override
  State<ReviewConsole> createState() => _ReviewConsoleState();
}

class _ReviewConsoleState extends State<ReviewConsole> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  String? selectedId;
  CaseDetail? detail;
  String? detailError;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 3, vsync: this);
    selectedId = _firstId();
    final id = selectedId;
    if (id != null) _loadDetail(id);
  }

  @override
  void didUpdateWidget(ReviewConsole old) {
    super.didUpdateWidget(old);
    final id = selectedId;
    if (id != null && !widget.cases.any((c) => c.id == id)) {

      selectedId = _firstId();
      detail = null;
      detailError = null;
      final next = selectedId;
      if (next != null) _loadDetail(next);
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  String? _firstId() {
    for (final c in widget.cases) {
      if (c.status == 'open') return c.id;
    }
    return widget.cases.isEmpty ? null : widget.cases.first.id;
  }

  void select(String id) {
    if (id == selectedId) return;
    setState(() {
      selectedId = id;
      detail = null;
      detailError = null;
    });
    _loadDetail(id);
  }

  Future<void> _loadDetail(String id) async {
    try {
      final d = await widget.api.caseDetail(id);
      if (mounted && selectedId == id) {
        setState(() {
          detail = d;
          detailError = null;
        });
      }
    } catch (e) {
      if (mounted && selectedId == id) setState(() => detailError = e.toString());
    }
  }

  Future<void> decide(String action) async {
    final c = detail;
    if (c == null) return;
    final r = await runDecision(context, widget.api, c, action);
    if (r == null || !mounted) return;
    setState(() => detail = r.detail);
    final what = r.status == 'frozen'
        ? '${r.creditsFrozen} credits frozen'
        : r.status == 'referred'
            ? 'Referred to the registries'
            : 'Case dismissed';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what · ${r.log}')));
    await widget.onChanged();
  }

  Future<void> _afterAgentWrote() async {
    await widget.onChanged();
    final id = selectedId;
    if (id != null && mounted) await _loadDetail(id);
  }

  Future<void> openAudit() async {
    await Navigator.push(context, EcoRoute(AuditLogScreen(api: widget.api)));
    if (!mounted) return;
    await widget.onChanged();
    final id = selectedId;
    if (id != null && mounted) _loadDetail(id);
  }

  Future<void> resetDemo() async {
    if (!await confirmReset(context, widget.api)) return;
    await widget.onChanged();
    if (!mounted) return;
    final id = _firstId();
    setState(() {
      selectedId = id;
      detail = null;
      detailError = null;
    });
    if (id != null) _loadDetail(id);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Demo data reset')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            _header(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SizedBox(width: 300, child: _rail()),
                  SizedBox(width: 16),
                  Expanded(child: _center()),
                  SizedBox(width: 16),
                  SizedBox(width: 380, child: _right()),
                ]),
              ),
            ),
          ]),
        ),
      );

  Widget _header() {
    final o = widget.stats;
    Widget stat(String big, String label, {Color color = Colors.white}) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(big, style: mono(22, weight: FontWeight.w700, color: color)),
            SizedBox(width: 8),
            Text(label, style: sans(13, color: Tone.navyText)),
          ],
        );
    return Container(
      color: Tone.ink,
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: LayoutBuilder(builder: (context, bc) {
        final roomy = bc.maxWidth >= 1380;
        return Row(children: [
          Wordmark(color: Colors.white, glyph: Colors.white),
          Container(
            margin: EdgeInsets.only(left: 20),
            padding: EdgeInsets.only(left: 14),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: Tone.navyLine))),
            child: Text('REVIEW CONSOLE', style: mono(12, color: Tone.navyMuted, spacing: 1)),
          ),
          Spacer(),
          stat('${numOf(o, 'open')}', 'open cases'),
          SizedBox(width: 32),
          stat('${numOf(o, 'freeze_suggested')}', 'freeze suggested', color: Tone.coral),
          SizedBox(width: 32),
          stat('${fmtInt(numOf(o, 'tonnes_at_risk'))} t', 'at risk'),
          SizedBox(width: 32),
          SyntheticTag(color: Tone.navyText),
          SizedBox(width: 16),
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0xFF2DD4BF))),
          SizedBox(width: 6),
          Text(roomy ? 'FalkorDB · ${fmtInt(numOf(o, 'nodes'))} nodes · ${fmtInt(numOf(o, 'edges'))} edges' : 'FalkorDB', style: mono(12, color: Tone.navyText)),
          SizedBox(width: 12),
          IconButton(tooltip: 'Audit log', onPressed: openAudit, icon: Icon(Icons.history, color: Colors.white)),
          IconButton(tooltip: 'Reset demo data', onPressed: resetDemo, icon: Icon(Icons.restart_alt, color: Colors.white)),
          IconButton(tooltip: 'Refresh cases', onPressed: widget.onChanged, icon: Icon(Icons.refresh, color: Colors.white)),
        ]);
      }),
    );
  }

  Widget _rail() {
    final open = [for (final c in widget.cases) if (c.status == 'open') c];
    final done = [for (final c in widget.cases) if (c.status != 'open') c];
    Widget heading(String left, String right, {double top = 4}) => Padding(
          padding: EdgeInsets.fromLTRB(2, top, 2, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(left, style: sans(17, weight: FontWeight.w700)),
            Spacer(),
            Text(right, style: sans(13, color: Tone.ink2)),
          ]),
        );
    return ListView(padding: EdgeInsets.zero, children: [
      heading('Cases to review', 'Highest risk first'),
      if (open.isEmpty)
        Padding(padding: EdgeInsets.fromLTRB(2, 4, 2, 8), child: Text('Every case has a decision.', style: sans(14, color: Tone.verdigris))),
      for (final c in open) Padding(padding: EdgeInsets.only(bottom: 8), child: _railTile(c)),
      if (done.isNotEmpty) ...[
        heading('Decided', '${done.length} closed', top: 12),
        for (final c in done) Padding(padding: EdgeInsets.only(bottom: 8), child: _railTile(c)),
      ],
    ]);
  }

  Widget _railTile(CaseSummary c) {
    final sel = c.id == selectedId;
    final open = c.status == 'open';
    return Material(
      color: Tone.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: sel ? BorderSide(color: Tone.ink, width: 2) : BorderSide(color: Tone.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => select(c.id),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              open ? bandStamp(c.band, fontSize: 11) : decidedStamp(c.status, fontSize: 11),
              Spacer(),
              Text(c.score.toStringAsFixed(3), style: mono(18, weight: FontWeight.w700, color: open ? bandColor(c.band) : Tone.ink3)),
            ]),
            SizedBox(height: 8),
            Text(c.title, style: sans(15, weight: FontWeight.w700, height: 20 / 15)),
            SizedBox(height: 4),
            Text(caseMeta(c), style: mono(12, color: Tone.ink3)),
            if (open && c.proposal != null) ...[SizedBox(height: 6), ProposalTag(p: c.proposal!)],
          ]),
        ),
      ),
    );
  }

  Widget _center() {
    final id = selectedId;
    if (id == null) {
      return Container(
        decoration: cardDeco(),
        alignment: Alignment.center,
        child: Text('No cases yet.', style: sans(16, color: Tone.ink2)),
      );
    }
    final c = detail;
    if (c == null) {
      return Container(
        decoration: cardDeco(),
        alignment: Alignment.center,
        child: detailError != null ? ErrorBox(message: detailError!, onRetry: () => _loadDetail(id)) : CircularProgressIndicator(color: Tone.ink),
      );
    }
    final open = c.status == 'open';
    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.id, style: mono(13, color: Tone.ink3, spacing: 0.5)),
                SizedBox(height: 4),
                Text(c.title, style: sans(28, weight: FontWeight.w700, height: 34 / 28, spacing: -0.3)),
              ]),
            ),
            SizedBox(width: 24),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              open ? bandStamp(c.band) : decidedStamp(c.status),
              SizedBox(height: 6),
              Text(c.score.toStringAsFixed(3), style: mono(40, weight: FontWeight.w700, color: bandColor(c.band), height: 1.1)),
            ]),
          ]),
          SizedBox(height: 12),
          TickMeter(value: c.score, color: open ? bandFill(c.band) : Tone.ink3, height: 10),
          if (open && c.proposal != null) ...[SizedBox(height: 16), ProposalBanner(c: c, margin: EdgeInsets.zero)],
          SizedBox(height: 20),
          EvidencePanel(c: c, aspect: 700 / 460, findingsInColumns: true, zoomable: false),
        ]),
      ),
    );
  }

  Widget _right() {
    final c = detail;
    Widget scroll(Widget child) => ListView(padding: EdgeInsets.fromLTRB(18, 16, 18, 16), children: [child]);
    return Material(
      color: Tone.paper,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Tone.line)),
      child: c == null
          ? SizedBox.expand()
          : Column(children: [
              EcoTabBar(controller: tabs, labels: ['Why', 'Query', 'Ask'], margin: EdgeInsets.fromLTRB(14, 12, 14, 8)),
              Expanded(
                child: TabBarView(controller: tabs, children: [
                  scroll(WhyPanel(c: c)),
                  scroll(QueryPanel(c: c)),
                  AskPanel(key: ValueKey('ask-${c.id}'), api: widget.api, caseId: c.id, onWrote: _afterAgentWrote),
                ]),
              ),
              DecisionBar(c: c, onDecide: decide),
            ]),
    );
  }
}
