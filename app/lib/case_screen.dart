// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_super_parameters
import 'package:flutter/material.dart';

import 'eco_api.dart';
import 'panels.dart';
import 'theme.dart';

class CaseScreen extends StatefulWidget {
  final EcoApi api;
  final String id;
  const CaseScreen({Key? key, required this.api, required this.id}) : super(key: key);
  @override
  State<CaseScreen> createState() => _CaseScreenState();
}

class _CaseScreenState extends State<CaseScreen> with SingleTickerProviderStateMixin {
  late final TabController tabs;
  CaseDetail? d;
  String? error;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    load();
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.caseDetail(widget.id);
      if (mounted) {
        setState(() {
          d = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> decide(String action) async {
    final c = d;
    if (c == null) return;
    final r = await runDecision(context, widget.api, c, action);
    if (r == null || !mounted) return;
    Navigator.pushReplacement(context, EcoRoute(DecisionRecordedScreen(api: widget.api, result: r)));
  }

  @override
  Widget build(BuildContext context) {
    final c = d;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 560), child: c == null ? _loading() : _loaded(c)),
        ),
      ),
    );
  }

  Widget _loading() => Column(children: [
        _top(widget.id, null),
        Expanded(child: error != null ? ErrorBox(message: error!, onRetry: load) : Center(child: CircularProgressIndicator(color: Tone.ink))),
      ]);

  Widget _top(String id, CaseDetail? c) => Padding(
        padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
        child: Row(children: [
          IconButton(tooltip: 'Back to cases', iconSize: 22, onPressed: () => Navigator.pop(context), icon: Icon(Icons.arrow_back, color: Tone.ink)),
          Text(id, style: mono(15, weight: FontWeight.w600, spacing: 0.3)),
          Spacer(),
          if (c != null)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.status == 'open' ? null : Tone.verdigrisTint,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.status == 'open' ? Tone.ink3 : Tone.verdigris),
              ),
              child: Text(c.status == 'open' ? 'OPEN' : 'DECIDED',
                  style: mono(12, weight: FontWeight.w700, color: c.status == 'open' ? Tone.ink2 : Tone.verdigris, spacing: 1)),
            ),
        ]),
      );

  Widget _loaded(CaseDetail c) {
    final col = bandColor(c.band);
    Widget scroll(Widget child) => ListView(padding: EdgeInsets.fromLTRB(16, 12, 16, 20), children: [child]);
    return Column(children: [
      _top(c.id, c),
      Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            c.status == 'open' ? bandStamp(c.band) : decidedStamp(c.status),
            Spacer(),
            Text(c.score.toStringAsFixed(3), style: mono(22, weight: FontWeight.w700, color: col)),
          ]),
          SizedBox(height: 8),
          Text(c.title, style: sans(22, weight: FontWeight.w700, height: 1.25, spacing: -0.2)),
          SizedBox(height: 8),
          TickMeter(value: c.score, color: c.status == 'open' ? bandFill(c.band) : Tone.ink3),
        ]),
      ),
      if (tabs.index != 3) ProposalBanner(c: c),
      SizedBox(height: 10),
      EcoTabBar(controller: tabs, labels: ['Evidence', 'Why', 'Query', 'Ask'], margin: EdgeInsets.fromLTRB(16, 0, 16, 4)),
      Expanded(
        child: TabBarView(controller: tabs, children: [
          scroll(EvidencePanel(c: c)),
          scroll(WhyPanel(c: c)),
          scroll(QueryPanel(c: c)),
          AskPanel(api: widget.api, caseId: c.id, onWrote: load),
        ]),
      ),
      if (tabs.index != 3) DecisionBar(c: c, onDecide: decide),
    ]);
  }
}

class DecisionRecordedScreen extends StatefulWidget {
  final EcoApi api;
  final DecisionResult result;
  const DecisionRecordedScreen({Key? key, required this.api, required this.result}) : super(key: key);
  @override
  State<DecisionRecordedScreen> createState() => _DecisionRecordedScreenState();
}

class _DecisionRecordedScreenState extends State<DecisionRecordedScreen> {
  int? open;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final o = await widget.api.overview();
      final n = o['open'];
      if (mounted && n is num) setState(() => open = n.toInt());
    } catch (_) {

    }
  }

  Widget _row(String label, String value, {bool isMono = false, bool last = false}) => Container(
        padding: EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Tone.line2))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: sans(14, color: Tone.ink2)),
          SizedBox(width: 16),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: isMono ? mono(14, weight: FontWeight.w700) : sans(14, weight: FontWeight.w600))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final c = r.detail;
    final frozen = c.status == 'frozen';
    final headline = frozen
        ? '${r.creditsFrozen} credits are frozen'
        : c.status == 'referred'
            ? 'Referred to the registries'
            : 'Case dismissed';
    final sub = frozen
        ? 'They are marked in the graph, and the next scan keeps your decision.'
        : c.status == 'referred'
            ? 'Your referral is logged, and the next scan keeps your decision.'
            : 'The case is closed as a false alarm, and the next scan keeps your decision.';
    final action = frozen ? 'Freeze' : c.status == 'referred' ? 'Refer' : 'Dismiss';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560),
            child: Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(children: [
                  IconButton(
                      tooltip: 'Back to cases',
                      iconSize: 22,
                      onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                      icon: Icon(Icons.arrow_back, color: Tone.ink)),
                  Text(c.id, style: mono(15, weight: FontWeight.w600, spacing: 0.3)),
                  Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: Tone.verdigrisTint, borderRadius: BorderRadius.circular(999), border: Border.all(color: Tone.verdigris)),
                    child: Text('DECIDED', style: mono(12, weight: FontWeight.w700, color: Tone.verdigris, spacing: 1)),
                  ),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
                  child: Column(children: [
                    Transform.rotate(
                      angle: -0.07,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Tone.ink, width: 3)),
                        child: Text(c.status.toUpperCase(), style: mono(40, weight: FontWeight.w700, spacing: 4.8)),
                      ),
                    ),
                    SizedBox(height: 14),
                    Text(fmtWhen(r.at), style: mono(13, color: Tone.ink2, spacing: 0.8)),
                    SizedBox(height: 18),
                    Text(headline, textAlign: TextAlign.center, style: sans(22, weight: FontWeight.w700, spacing: -0.2)),
                    SizedBox(height: 6),
                    Text(sub, textAlign: TextAlign.center, style: sans(15, color: Tone.ink2, height: 1.45)),
                    SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
                      child: Column(children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Row(children: [
                            Expanded(child: Text('AUDIT LOG', style: mono(12, weight: FontWeight.w700, color: Tone.ink2, spacing: 1))),
                            Text(r.log, style: mono(14, weight: FontWeight.w700)),
                          ]),
                        ),
                        Container(height: 1, color: Tone.line),
                        Padding(
                          padding: EdgeInsets.fromLTRB(16, 6, 16, 10),
                          child: Column(children: [
                            _row('Action', action),
                            if (r.proposed.isNotEmpty) _row('Agent proposed', {'freeze': 'Freeze', 'refer': 'Refer', 'dismiss': 'Dismiss'}[r.proposed] ?? r.proposed),
                            _row('Decided by', 'Human reviewer'),
                            _row('Risk score then', c.score.toStringAsFixed(3), isMono: true),
                            _row('Credits frozen', '${r.creditsFrozen}', isMono: true),
                            _row('Note', (c.note ?? '').isEmpty ? 'None' : c.note!, last: true),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(children: [
                  ActionButton(
                      label: open == null ? 'Back to cases' : 'Back to cases · $open open',
                      onPressed: () => Navigator.popUntil(context, (route) => route.isFirst)),
                  SizedBox(height: 8),
                  ActionButton(
                      label: 'View the full audit log',
                      filled: false,
                      onPressed: () => Navigator.push(context, EcoRoute(AuditLogScreen(api: widget.api)))),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class AuditLogScreen extends StatefulWidget {
  final EcoApi api;
  const AuditLogScreen({Key? key, required this.api}) : super(key: key);
  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  List<AuditEntry>? items;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await widget.api.auditLog();
      if (mounted) {
        setState(() {
          items = r;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> resetDemo() async {
    if (!await confirmReset(context, widget.api)) return;
    await load();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Demo data reset')));
  }

  @override
  Widget build(BuildContext context) {
    final list = items;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560),
            child: Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(4, 8, 16, 8),
                child: Row(children: [
                  IconButton(tooltip: 'Back', iconSize: 22, onPressed: () => Navigator.pop(context), icon: Icon(Icons.arrow_back, color: Tone.ink)),
                  Expanded(child: Text('Audit log', style: sans(22, weight: FontWeight.w700, spacing: -0.2))),
                  SquareButton(icon: Icons.restart_alt, tooltip: 'Reset demo data', onPressed: resetDemo),
                ]),
              ),
              Expanded(
                child: list == null
                    ? (error != null ? ErrorBox(message: error!, onRetry: load) : Center(child: CircularProgressIndicator(color: Tone.ink)))
                    : list.isEmpty
                        ? Center(child: Text('No decisions yet.', style: sans(16, color: Tone.ink2)))
                        : ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 20), children: [for (final e in list) _entry(e)]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _entry(AuditEntry e) => Container(
        margin: EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            decidedStamp(actionWord(e.action)),
            Spacer(),
            Text(e.log, style: mono(13, weight: FontWeight.w700)),
          ]),
          SizedBox(height: 10),
          Text(e.caseId, style: mono(14, weight: FontWeight.w600)),
          SizedBox(height: 2),
          Text('${fmtWhen(e.at)}  ·  ${e.by}', style: sans(13, color: Tone.ink2)),
          if (e.creditsFrozen > 0) ...[SizedBox(height: 4), Text('${e.creditsFrozen} credits frozen', style: sans(14, weight: FontWeight.w600))],
          if ((e.note ?? '').isNotEmpty) ...[SizedBox(height: 4), Text('Note: ${e.note}', style: sans(14, color: Tone.ink2, height: 1.35))],
          if (e.proposed.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(e.proposed == e.action ? 'The agent had proposed ${e.proposed}. The reviewer agreed.' : 'The agent had proposed ${e.proposed}. The reviewer chose ${e.action}.',
                style: sans(14, color: Tone.ink2, height: 1.35)),
          ],
        ]),
      );
}
