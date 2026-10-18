// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_super_parameters
import 'package:flutter/material.dart';

import 'case_screen.dart';
import 'console.dart';
import 'eco_api.dart';
import 'panels.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  final EcoApi api;
  const AppShell({Key? key, required this.api}) : super(key: key);
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  List<CaseSummary>? cases;
  Map<String, dynamic>? stats;
  String? error;
  int _seq = 0;
  int tab = 0;
  int histKey = 0;
  int askSeed = 0;
  String? askAuto;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final mine = ++_seq;
    try {
      final cs = await widget.api.cases();
      final ov = await widget.api.overview();
      if (!mounted || mine != _seq) return;
      setState(() {
        cases = cs;
        stats = ov;
        error = null;
      });
    } catch (e) {
      if (!mounted || mine != _seq) return;
      setState(() => error = e.toString());
    }
  }

  Future<void> openCase(CaseSummary c) async {
    await Navigator.push(context, EcoRoute(CaseScreen(api: widget.api, id: c.id)));
    if (!mounted) return;
    setState(() => histKey++);
    load();
  }

  void go(int i) {
    setState(() {
      tab = i;
      if (i == 4) histKey++;
    });
  }

  void triage() {
    setState(() {
      askSeed++;
      askAuto = 'Triage every open case';
      tab = 2;
    });
  }

  Future<void> openSettings() async {
    await Navigator.push(context, EcoRoute(SettingsScreen(api: widget.api)));
    if (!mounted) return;
    setState(() => histKey++);
    load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = cases, st = stats;
    return LayoutBuilder(builder: (context, bc) {
      if (cs == null || st == null) {
        return Scaffold(
          body: SafeArea(
            child: error != null
                ? ErrorBox(message: error!, onRetry: () {
                    setState(() => error = null);
                    load();
                  })
                : _Connecting(),
          ),
        );
      }
      if (bc.maxWidth >= consoleBreakpoint) {
        return ReviewConsole(api: widget.api, stats: st, cases: cs, onChanged: load);
      }
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 560),
              child: Column(children: [
                Expanded(
                  child: IndexedStack(index: tab, children: [
                    HomeTab(cases: cs, stats: st, onOpen: openCase, onTriage: triage, onSettings: openSettings, onCases: () => go(1)),
                    CasesTab(cases: cs, onOpen: openCase, onRefresh: load),
                    _AskTab(key: ValueKey('ask$askSeed'), api: widget.api, auto: askAuto, onWrote: load),
                    TraceTab(api: widget.api),
                    HistoryTab(api: widget.api, cases: cs, refreshKey: histKey, onOpen: openCase),
                  ]),
                ),
                SafeArea(top: false, child: EcoNav(index: tab, onTap: go)),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

class EcoNav extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const EcoNav({Key? key, required this.index, required this.onTap}) : super(key: key);

  static const _items = <(IconData, String)>[
    (Icons.home_rounded, 'Home'),
    (Icons.view_agenda_rounded, 'Cases'),
    (Icons.auto_awesome_rounded, 'Ask'),
    (Icons.search_rounded, 'Trace'),
    (Icons.history_rounded, 'History'),
  ];

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.fromLTRB(14, 4, 14, 10),
        padding: EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Tone.paper,
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Tone.line),
          boxShadow: [BoxShadow(color: Color(0x140C111B), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Row(children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              flex: i == index ? 24 : 15,
              child: Bounce(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 380),
                  curve: Curves.easeOutBack,
                  height: 48,
                  decoration: BoxDecoration(color: i == index ? Tone.ink : Colors.transparent, borderRadius: BorderRadius.circular(26)),
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(_items[i].$1, size: 22, color: i == index ? Tone.ground : Tone.ink3),
                      if (i == index) ...[
                        SizedBox(width: 6),
                        Flexible(child: Text(_items[i].$2, maxLines: 1, overflow: TextOverflow.clip, style: sans(13, weight: FontWeight.w700, color: Tone.ground))),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}

Widget _pageTitle(String t, {Widget? trailing}) => Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Row(children: [
        Expanded(child: Text(t, style: sans(32, weight: FontWeight.w800, spacing: -1))),
        if (trailing != null) trailing,
      ]),
    );

class HomeTab extends StatelessWidget {
  final List<CaseSummary> cases;
  final Map<String, dynamic> stats;
  final ValueChanged<CaseSummary> onOpen;
  final VoidCallback onTriage, onSettings, onCases;
  const HomeTab({Key? key, required this.cases, required this.stats, required this.onOpen, required this.onTriage, required this.onSettings, required this.onCases})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final open = [for (final c in cases) if (c.status == 'open') c];
    final nOpen = numOf(stats, 'open');
    Widget tile(String big, String label, {Color color = Tone.ink}) => Expanded(
          child: Container(
            padding: EdgeInsets.fromLTRB(14, 14, 10, 14),
            decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(big, maxLines: 1, style: mono(24, weight: FontWeight.w700, color: color))),
              SizedBox(height: 2),
              Text(label, style: sans(12.5, color: Tone.ink3)),
            ]),
          ),
        );
    return ListView(padding: EdgeInsets.fromLTRB(20, 14, 20, 20), children: [
      Row(children: [
        Wordmark(size: 20),
        Spacer(),
        SquareButton(icon: Icons.settings_rounded, tooltip: 'Settings', onPressed: onSettings),
      ]),
      SizedBox(height: 26),
      Reveal(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: nOpen.toDouble()),
          duration: Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, v, _) => Text(nOpen == 0 ? 'Every case\nhas a decision.' : '${v.round()} ${nOpen == 1 ? 'case needs' : 'cases need'}\na decision.',
              style: sans(38, weight: FontWeight.w800, height: 1.04, spacing: -1.4)),
        ),
      ),
      SizedBox(height: 10),
      Reveal(index: 1, child: Text('${fmtInt(numOf(stats, 'tonnes_at_risk'))} t at risk · ${numOf(stats, 'freeze_suggested')} suggested to freeze', style: mono(13, color: Tone.ink2))),
      SizedBox(height: 22),
      Reveal(index: 2, child: Row(children: [
        tile('$nOpen', 'open cases'),
        SizedBox(width: 10),
        tile('${numOf(stats, 'freeze_suggested')}', 'to freeze', color: Tone.vermilion),
        SizedBox(width: 10),
        tile('${fmtInt(numOf(stats, 'tonnes_at_risk'))}', 'tonnes', color: Tone.ink),
      ])),
      if (open.isNotEmpty) ...[
        SizedBox(height: 26),
        Row(children: [
          Text('Start here', style: sans(18, weight: FontWeight.w700)),
          Spacer(),
          Bounce(onTap: onCases, child: Padding(padding: EdgeInsets.all(4), child: Text('All cases', style: sans(14, weight: FontWeight.w700, color: Tone.agent)))),
        ]),
        SizedBox(height: 10),
        Reveal(index: 3, child: CaseCard(c: open.first, onTap: () => onOpen(open.first))),
      ],
      SizedBox(height: 16),
      Reveal(
        index: 4,
        child: Bounce(
          onTap: onTriage,
          child: Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(color: Tone.agentTint, borderRadius: BorderRadius.circular(28)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [AgentChip('The agent'), SizedBox(width: 8), PulseDot(), ]),
              SizedBox(height: 12),
              Text('Let it triage every open case.', style: sans(22, weight: FontWeight.w800, height: 1.15, spacing: -0.5)),
              SizedBox(height: 6),
              Text('It queries the graph, ranks the cases and writes a note on each. You still decide.', style: sans(14.5, color: Tone.ink2, height: 1.4)),
              SizedBox(height: 16),
              Container(
                height: 46,
                padding: EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(color: Tone.agent, borderRadius: BorderRadius.circular(23)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('Triage now', style: sans(15, weight: FontWeight.w700, color: Colors.white)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                ]),
              ),
            ]),
          ),
        ),
      ),
      SizedBox(height: 18),
      Center(child: Text('FalkorDB · ${fmtInt(numOf(stats, 'nodes'))} nodes · ${fmtInt(numOf(stats, 'edges'))} edges · synthetic data', style: mono(11, color: Tone.ink3))),
    ]);
  }
}

class CasesTab extends StatelessWidget {
  final List<CaseSummary> cases;
  final ValueChanged<CaseSummary> onOpen;
  final Future<void> Function() onRefresh;
  const CasesTab({Key? key, required this.cases, required this.onOpen, required this.onRefresh}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final open = [for (final c in cases) if (c.status == 'open') c];
    final done = [for (final c in cases) if (c.status != 'open') c];
    var i = 0;
    return RefreshIndicator(
      color: Tone.ink,
      onRefresh: onRefresh,
      child: ListView(physics: AlwaysScrollableScrollPhysics(), padding: EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
        _pageTitleInline('Cases', '${open.length} open · highest risk first'),
        if (open.isEmpty)
          Container(
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(color: Tone.verdigrisTint, borderRadius: BorderRadius.circular(22)),
            child: Text('Every case has a decision. Pull down to check for new ones.', style: sans(15, color: Tone.verdigris, height: 1.4)),
          ),
        for (final c in open) Padding(padding: EdgeInsets.only(bottom: 12), child: Reveal(index: i++, child: CaseCard(c: c, onTap: () => onOpen(c)))),
        if (done.isNotEmpty) ...[
          Padding(padding: EdgeInsets.fromLTRB(2, 14, 2, 10), child: Text('Decided', style: sans(18, weight: FontWeight.w700))),
          for (final c in done) Padding(padding: EdgeInsets.only(bottom: 12), child: CaseCard(c: c, onTap: () => onOpen(c))),
        ],
      ]),
    );
  }
}

Widget _pageTitleInline(String t, String sub) => Padding(
      padding: EdgeInsets.fromLTRB(2, 14, 2, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: sans(32, weight: FontWeight.w800, spacing: -1)),
        SizedBox(height: 4),
        Text(sub, style: mono(12, color: Tone.ink3, spacing: 0.4)),
      ]),
    );

class _AskTab extends StatelessWidget {
  final EcoApi api;
  final String? auto;
  final Future<void> Function() onWrote;
  const _AskTab({Key? key, required this.api, required this.auto, required this.onWrote}) : super(key: key);
  @override
  Widget build(BuildContext context) => Column(children: [
        _pageTitle('Ask', trailing: AgentChip('Grounded in the graph')),
        Expanded(child: AskPanel(api: api, caseId: null, autoAsk: auto, onWrote: onWrote)),
      ]);
}

class TraceTab extends StatefulWidget {
  final EcoApi api;
  const TraceTab({Key? key, required this.api}) : super(key: key);
  @override
  State<TraceTab> createState() => _TraceTabState();
}

class _TraceTabState extends State<TraceTab> with AutomaticKeepAliveClientMixin {
  final q = TextEditingController(text: 'CR-00694');
  Map<String, dynamic>? r;
  String? error;
  bool busy = false;
  int seed = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  Future<void> run([String? id]) async {
    final text = (id ?? q.text).trim().toUpperCase();
    if (text.isEmpty || busy) return;
    q.text = text;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final res = await widget.api.creditTrace(text);
      if (mounted) {
        setState(() {
          r = res;
          seed++;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          r = null;
          error = e.toString();
        });
      }
    }
    if (mounted) setState(() => busy = false);
  }

  List<Map<String, dynamic>> _list(dynamic v) => v is List ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)] : <Map<String, dynamic>>[];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final res = r;
    return ListView(padding: EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
      _pageTitleInline('Trace a credit', 'From retirement back to the land'),
      Container(
        height: 56,
        padding: EdgeInsets.only(left: 18, right: 6),
        decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(28), border: Border.all(color: Tone.line)),
        child: Row(children: [
          Icon(Icons.search_rounded, color: Tone.ink3),
          SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: q,
              textCapitalization: TextCapitalization.characters,
              onSubmitted: (_) => run(),
              style: mono(16, weight: FontWeight.w600),
              decoration: InputDecoration(border: InputBorder.none, hintText: 'Credit id, e.g. CR-00694', hintStyle: mono(15, color: Tone.ink3)),
            ),
          ),
          Bounce(
            onTap: busy ? null : () => run(),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: Tone.ink, borderRadius: BorderRadius.circular(22)),
              child: busy ? Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))) : Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
      SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final id in ['CR-00694', 'CR-00089', 'CR-00691'])
          Bounce(
            onTap: () => run(id),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(999), border: Border.all(color: Tone.line)),
              child: Text(id, style: mono(13, weight: FontWeight.w600)),
            ),
          ),
      ]),
      SizedBox(height: 18),
      if (error != null)
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(color: Tone.amberTint, borderRadius: BorderRadius.circular(22)),
          child: Text(error!, style: sans(14.5, color: Tone.amber, height: 1.4)),
        ),
      if (res != null) KeyedSubtree(key: ValueKey(seed), child: _result(res)),
    ]);
  }

  Widget _result(Map<String, dynamic> res) {
    final flags = [for (final f in (res['flags'] is List ? res['flags'] as List : const [])) f.toString()];
    final retired = _list(res['retired']);
    final sales = _list(res['sales']);
    final rivals = _list(res['rival_claims']);
    final project = res['project'] is Map ? Map<String, dynamic>.from(res['project'] as Map) : <String, dynamic>{};
    final parcels = project['parcels'] is List ? (project['parcels'] as List).join(', ') : '';
    final steps = <(String, String, Color)>[];
    for (final e in [...retired]..sort((a, b) => (b['day'] as num).compareTo(a['day'] as num))) {
      steps.add(('Retired · day ${e['day']}', '${e['name'] ?? e['buyer']} · claim ${e['claim']}', Tone.vermilion));
    }
    for (final e in [...sales]..sort((a, b) => (b['day'] as num).compareTo(a['day'] as num))) {
      steps.add(('Sold · day ${e['day']}', '${e['from']} to ${e['to']}', Tone.ink));
    }
    steps.add(('Issued for ${project['id'] ?? ''}', '${project['name'] ?? ''}${project['country'] != null ? ' · ${project['country']}' : ''} · ${project['registry'] ?? ''}${project['audit'] == null ? ' · no audit on file' : ''}', project['audit'] == null ? Tone.amber : Tone.ink));
    steps.add(('Land', parcels.isEmpty ? 'none recorded' : parcels, Tone.sand));
    var k = 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Reveal(
        child: Container(
          padding: EdgeInsets.all(18),
          decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tone.line)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${res['credit']}', style: mono(20, weight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('${fmtInt((res['tonnes'] as num?) ?? 0)} t · ${res['hops'] ?? '?'} hops to the land', style: sans(13.5, color: Tone.ink2)),
              ]),
            ),
            Stamp(text: '${res['status']}', color: res['status'] == 'RETIRED' ? Tone.vermilion : Tone.verdigris, tint: res['status'] == 'RETIRED' ? Tone.vermilionTint : Tone.verdigrisTint),
          ]),
        ),
      ),
      if (flags.isNotEmpty || rivals.isNotEmpty) ...[
        SizedBox(height: 12),
        Reveal(
          index: 1,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(color: Tone.vermilionTint, borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('WHY IT IS FLAGGED', style: mono(11, weight: FontWeight.w700, color: Tone.vermilion, spacing: 1)),
              SizedBox(height: 8),
              for (final f in flags)
                Padding(padding: EdgeInsets.only(bottom: 4), child: Text(f, style: sans(15, color: Tone.vermilion, weight: FontWeight.w600, height: 1.35))),
            ]),
          ),
        ),
      ],
      SizedBox(height: 20),
      Text('Back to the land', style: sans(18, weight: FontWeight.w700)),
      SizedBox(height: 12),
      for (var i = 0; i < steps.length; i++)
        Reveal(
          index: 2 + k++,
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 28,
                child: Column(children: [
                  SizedBox(height: 4),
                  Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: steps[i].$3, border: Border.all(color: Tone.ground, width: 2))),
                  if (i < steps.length - 1) Expanded(child: Container(width: 2, margin: EdgeInsets.symmetric(vertical: 4), decoration: BoxDecoration(color: Tone.line, borderRadius: BorderRadius.circular(1)))),
                ]),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i].$1, style: sans(15, weight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text(steps[i].$2, style: sans(13.5, color: Tone.ink2, height: 1.35)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      if (rivals.isNotEmpty)
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(color: Tone.amberTint, borderRadius: BorderRadius.circular(22)),
          child: Text('Also claimed by ${[for (final e in rivals) '${e['project']} (${e['parcel']})'].join(', ')}.', style: sans(14.5, color: Tone.amber, weight: FontWeight.w600, height: 1.35)),
        ),
    ]);
  }
}

class HistoryTab extends StatefulWidget {
  final EcoApi api;
  final List<CaseSummary> cases;
  final int refreshKey;
  final ValueChanged<CaseSummary> onOpen;
  const HistoryTab({Key? key, required this.api, required this.cases, required this.refreshKey, required this.onOpen}) : super(key: key);
  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  List<AuditEntry>? items;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(HistoryTab old) {
    super.didUpdateWidget(old);
    if (old.refreshKey != widget.refreshKey) load();
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

  @override
  Widget build(BuildContext context) {
    final waiting = [for (final c in widget.cases) if (c.status == 'open' && c.proposal != null) c];
    final list = items;
    var i = 0;
    return RefreshIndicator(
      color: Tone.ink,
      onRefresh: load,
      child: ListView(physics: AlwaysScrollableScrollPhysics(), padding: EdgeInsets.fromLTRB(20, 0, 20, 20), children: [
        _pageTitleInline('History', '${list?.length ?? 0} decided · ${waiting.length} waiting for you'),
        if (waiting.isNotEmpty) ...[
          Padding(padding: EdgeInsets.fromLTRB(2, 0, 2, 10), child: Row(children: [Text('Waiting for you', style: sans(18, weight: FontWeight.w700)), Spacer(), AgentChip('Agent proposals')])),
          for (final c in waiting)
            Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Bounce(
                onTap: () => widget.onOpen(c),
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.id, style: mono(13, weight: FontWeight.w600)),
                        SizedBox(height: 3),
                        Text(c.title, style: sans(14.5, color: Tone.ink2)),
                      ]),
                    ),
                    Stamp(text: c.proposal!.action.toUpperCase(), color: actionColor(c.proposal!.action), tint: c.proposal!.action == 'freeze' ? Tone.vermilionTint : Tone.amberTint),
                  ]),
                ),
              ),
            ),
          SizedBox(height: 10),
        ],
        Padding(padding: EdgeInsets.fromLTRB(2, 0, 2, 10), child: Text('Decided', style: sans(18, weight: FontWeight.w700))),
        if (list == null)
          (error != null ? ErrorBox(message: error!, onRetry: load) : Center(child: Padding(padding: EdgeInsets.all(30), child: PulseDot(color: Tone.ink))))
        else if (list.isEmpty)
          Container(
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
            child: Text('No decisions yet. Open a case and freeze, refer or dismiss it.', style: sans(14.5, color: Tone.ink2, height: 1.4)),
          )
        else
          for (final e in list) Reveal(index: i++, child: _entry(e)),
      ]),
    );
  }

  Widget _entry(AuditEntry e) {
    final agreed = e.proposed.isNotEmpty && e.proposed == e.action;
    final differ = e.proposed.isNotEmpty && e.proposed != e.action;
    final c = e.action == 'freeze' ? Tone.vermilion : e.action == 'refer' ? Tone.amber : Tone.ink2;
    final t = e.action == 'freeze' ? Tone.vermilionTint : e.action == 'refer' ? Tone.amberTint : Tone.line2;
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tone.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Stamp(text: actionWord(e.action), color: c, tint: t),
          SizedBox(width: 10),
          Expanded(child: Text(e.caseId, style: mono(13, weight: FontWeight.w600))),
          Text(fmtWhen(e.at).split(' · ').last, style: mono(11, color: Tone.ink3)),
        ]),
        if (e.creditsFrozen > 0) ...[SizedBox(height: 8), Text('${e.creditsFrozen} credits frozen', style: sans(15, weight: FontWeight.w700))],
        if ((e.note ?? '').isNotEmpty) ...[SizedBox(height: 4), Text(e.note!, style: sans(14, color: Tone.ink2, height: 1.35))],
        if (agreed || differ) ...[
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.only(top: 10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Tone.line2))),
            child: Row(children: [
              AgentChip('Proposed ${e.proposed}'),
              SizedBox(width: 10),
              Icon(agreed ? Icons.check_rounded : Icons.swap_horiz_rounded, size: 18, color: agreed ? Tone.verdigris : Tone.amber),
              SizedBox(width: 4),
              Text(agreed ? 'You agreed' : 'You decided differently', style: sans(13, weight: FontWeight.w700, color: agreed ? Tone.verdigris : Tone.amber)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final EcoApi api;
  const SettingsScreen({Key? key, required this.api}) : super(key: key);
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? health;
  Map<String, dynamic>? ov;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final h = await widget.api.health();
      final o = await widget.api.overview();
      if (mounted) {
        setState(() {
          health = h;
          ov = o;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Widget _row(String l, Widget v, {bool last = false}) => Container(
        height: 52,
        padding: EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Tone.line2))),
        child: Row(children: [Text(l, style: sans(15, weight: FontWeight.w600)), Spacer(), v]),
      );

  Widget _group(String label, List<Widget> rows, {String? note}) => Padding(
        padding: EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text(label, style: mono(11, color: Tone.ink3, spacing: 1.2))),
          Container(
            decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(24), border: Border.all(color: Tone.line)),
            child: Column(children: rows),
          ),
          if (note != null) Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 0), child: Text(note, style: sans(12.5, color: Tone.ink3, height: 1.4))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final h = health, o = ov;
    final agentOn = h?['agent'] == true;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560),
            child: ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
              Row(children: [
                Bounce(onTap: () => Navigator.pop(context), child: Padding(padding: EdgeInsets.all(10), child: Icon(Icons.arrow_back_rounded, color: Tone.ink))),
                Text('Home', style: sans(15, weight: FontWeight.w600, color: Tone.ink2)),
              ]),
              Padding(padding: EdgeInsets.fromLTRB(8, 6, 0, 18), child: Text('Settings', style: sans(32, weight: FontWeight.w800, spacing: -1))),
              if (error != null) Padding(padding: EdgeInsets.only(bottom: 14), child: Text(error!, style: sans(14, color: Tone.vermilion))),
              _group('SERVER', [
                _row('API', Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(apiBase.replaceFirst('http://', '').replaceFirst('https://', ''), overflow: TextOverflow.ellipsis, style: mono(12, color: Tone.ink3))),
                  SizedBox(width: 8),
                  if (h != null) Stamp(text: 'ONLINE', color: Tone.verdigris, tint: Tone.verdigrisTint, fontSize: 10),
                ])),
                _row('Database', Text(h == null ? '...' : '${h['database']}', style: mono(12, color: Tone.ink3))),
                _row('Graph', Text(o == null ? '...' : '${fmtInt(numOf(o, 'nodes'))} nodes · ${fmtInt(numOf(o, 'edges'))} edges', style: mono(12, color: Tone.ink3)), last: true),
              ]),
              _group('AGENT', [
                _row('Model', agentOn ? AgentChip('${h?['model'] ?? 'on'}') : Text(h == null ? '...' : 'Not switched on', style: mono(12, color: Tone.ink3))),
                _row('Can do', Text('read, trace, propose', style: mono(12, color: Tone.ink3)), last: true),
              ], note: 'The agent recommends. Only you can freeze, refer or dismiss a case.'),
              _group('DATA', [
                _row('Dataset', Text('Synthetic', style: mono(12, color: Tone.ink3))),
                Bounce(
                  onTap: () async {
                    if (!await confirmReset(context, widget.api)) return;
                    await load();
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Demo data reset')));
                  },
                  child: _row('Reset demo data', Icon(Icons.chevron_right_rounded, color: Tone.vermilion), last: true),
                ),
              ], note: 'No real registries, projects or companies. Reset brings back all five open cases.'),
              _group('ABOUT', [
                _row('Built for', Text('Graph Hacks · Track 1', style: mono(12, color: Tone.ink3)), last: true),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}


class _Connecting extends StatefulWidget {
  @override
  State<_Connecting> createState() => _ConnectingState();
}

class _ConnectingState extends State<_Connecting> {
  bool slow = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(seconds: 5), () {
      if (mounted) setState(() => slow = true);
    });
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            PulseDot(color: Tone.forest, size: 16),
            SizedBox(height: 18),
            Text('Connecting to the server', style: sans(16, weight: FontWeight.w700)),
            if (slow) ...[
              SizedBox(height: 8),
              Text(
                'The free server sleeps when idle. Waking it up can take up to a minute. Please wait.',
                textAlign: TextAlign.center,
                style: sans(14, color: Tone.ink2, height: 1.4),
              ),
            ],
          ]),
        ),
      );
}
