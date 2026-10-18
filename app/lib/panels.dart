// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_super_parameters
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;

import 'eco_api.dart';
import 'graph.dart';
import 'md.dart';
import 'theme.dart';

const _kindOrder = ['project', 'parcel', 'registry', 'credit', 'buyer'];

// ---- Evidence --------------------------------------------------------------------------------------
/// The graph, its key, and what the graph shows. Returns a Column, so the caller supplies the scrolling.
class EvidencePanel extends StatelessWidget {
  final CaseDetail c;
  final double aspect;
  final bool findingsInColumns;
  final bool zoomable;
  const EvidencePanel({Key? key, required this.c, this.aspect = 0.85, this.findingsInColumns = false, this.zoomable = true})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final present = c.nodes.map((n) => n.kind).toSet();
    final kinds = [for (final k in _kindOrder) if (present.contains(k)) k];
    Widget finding(Map<String, dynamic> f, {bool ruled = false}) => Container(
          padding: EdgeInsets.only(top: ruled ? 10 : 0),
          decoration: ruled ? BoxDecoration(border: Border(top: BorderSide(color: Tone.vermilion, width: 2))) : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(findingLabel('${f['type']}'), style: mono(12, weight: FontWeight.w700, color: Tone.vermilion, spacing: 0.7)),
            SizedBox(height: 3),
            Text('${f['summary']}', style: sans(15, height: 1.45)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        margin: EdgeInsets.only(bottom: 12),
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(color: Tone.agentTint, borderRadius: BorderRadius.circular(20)),
        child: Text(
          'This is a graph, not a map. Each circle is a thing (a project, a credit, a buyer). Each line is a link between two things, read from top to bottom. Red rings and dashed lines are the parts that look wrong.',
          style: sans(13.5, color: Tone.agent, height: 1.4, weight: FontWeight.w600),
        ),
      ),
      AspectRatio(aspectRatio: aspect, child: EvidenceGraph(nodes: c.nodes, edges: c.edges, zoomable: zoomable)),
      SizedBox(height: 10),
      GraphLegend(kinds: kinds),
      SizedBox(height: 20),
      if (findingsInColumns)
        LayoutBuilder(builder: (context, bc) {
          final cols = bc.maxWidth >= 600 ? 3 : 1;
          final w = ((bc.maxWidth - 16.0 * (cols - 1)) / cols).floorToDouble();
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final f in c.findings) SizedBox(width: w, child: finding(f, ruled: true)),
          ]);
        })
      else ...[
        Text('What the graph shows', style: sans(17, weight: FontWeight.w700)),
        for (final f in c.findings) Padding(padding: EdgeInsets.only(top: 10), child: finding(f)),
      ],
      SizedBox(height: 14),
      Text('${c.creditsAtRisk} credits, ${fmtInt(c.tonnesAtRisk)} t at risk.', style: sans(15, weight: FontWeight.w700)),
    ]);
  }
}

// ---- Why -------------------------------------------------------------------------------------------
class WhyPanel extends StatelessWidget {
  final CaseDetail c;
  const WhyPanel({Key? key, required this.c}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ws = [for (final s in c.signals) s.weight];
    var p = 1.0;
    for (final w in ws) {
      p *= 1 - w;
    }
    final formula = '1 − ${ws.map((w) => '(1−${w.toStringAsFixed(2)})').join()}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: Color(0xFFF3F5F7), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('HOW THE SCORE IS BUILT', style: mono(12, weight: FontWeight.w700, color: Tone.ink2, spacing: 1)),
          SizedBox(height: 8),
          Text(formula, style: mono(13, height: 1.7)),
          Text('= 1 − ${p.toStringAsFixed(4)}', style: mono(13, height: 1.7)),
          SizedBox(height: 6),
          Container(height: 1, color: Color(0xFFAEBBC8)),
          SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: Text('A rule of thumb, not a probability.', style: sans(13, color: Tone.ink2))),
            Text('= ${c.score.toStringAsFixed(3)}', style: mono(20, weight: FontWeight.w700, color: bandColor(c.band))),
          ]),
        ]),
      ),
      SizedBox(height: 18),
      Text('Signals behind the score', style: sans(17, weight: FontWeight.w700)),
      SizedBox(height: 4),
      for (var i = 0; i < c.signals.length; i++) _SignalRow(s: c.signals[i], last: i == c.signals.length - 1),
    ]);
  }
}

class _SignalRow extends StatelessWidget {
  final Signal s;
  final bool last;
  const _SignalRow({required this.s, required this.last});
  @override
  Widget build(BuildContext context) {
    final bar = s.signal == 'no_audit' ? Tone.ink3 : Tone.vermilion;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: Tone.line2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(signalLabel(s.signal), style: sans(15, weight: FontWeight.w700))),
          Text(s.weight.toStringAsFixed(2), style: mono(15, weight: FontWeight.w700)),
        ]),
        SizedBox(height: 6),
        Container(
          height: 8,
          width: double.infinity,
          decoration: BoxDecoration(color: Tone.line2, borderRadius: BorderRadius.circular(999)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: s.weight < 0 ? 0.0 : (s.weight > 1 ? 1.0 : s.weight),
            child: Container(decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(999))),
          ),
        ),
        SizedBox(height: 6),
        Text(s.why, style: sans(14, color: Tone.ink2, height: 1.4)),
      ]),
    );
  }
}

// ---- Query -----------------------------------------------------------------------------------------
const _cypherKeywords = {
  'MATCH', 'OPTIONAL', 'WITH', 'WHERE', 'RETURN', 'ORDER', 'BY', 'LIMIT', 'UNWIND', 'CALL', 'YIELD', 'AS', 'AND', 'OR', 'NOT', 'IN',
  'DISTINCT', 'CREATE', 'SET', 'MERGE', 'DESC', 'ASC', 'IS', 'NULL', 'EXISTS',
};

/// Colours the Cypher: keywords green, :Labels blue, numbers orange.
List<InlineSpan> highlightCypher(String src) {
  final re = RegExp(r':[A-Za-z_][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*|\d+(?:\.\d+)?');
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in re.allMatches(src)) {
    if (m.start > last) spans.add(TextSpan(text: src.substring(last, m.start)));
    final t = m.group(0)!;
    TextStyle? st;
    if (t.startsWith(':')) {
      st = TextStyle(color: Color(0xFF9DB8FF));
    } else if (RegExp(r'^\d').hasMatch(t)) {
      st = TextStyle(color: Color(0xFFFFB86B));
    } else if (_cypherKeywords.contains(t)) {
      st = TextStyle(color: Color(0xFF7FD6C2), fontWeight: FontWeight.w700);
    }
    spans.add(TextSpan(text: t, style: st));
    last = m.end;
  }
  if (last < src.length) spans.add(TextSpan(text: src.substring(last)));
  return spans;
}

class QueryPanel extends StatefulWidget {
  final CaseDetail c;
  const QueryPanel({Key? key, required this.c}) : super(key: key);
  @override
  State<QueryPanel> createState() => _QueryPanelState();
}

class _QueryPanelState extends State<QueryPanel> {
  int open = 0;

  @override
  Widget build(BuildContext context) {
    final trace = widget.c.trace;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('The exact Cypher that ran in FalkorDB to build this case. Nothing here is written by the AI.', style: sans(14, color: Tone.ink2, height: 1.4)),
      SizedBox(height: 10),
      for (var i = 0; i < trace.length; i++)
        Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: _QueryCard(t: trace[i], expanded: open == i, onTap: () => setState(() => open = open == i ? -1 : i)),
        ),
    ]);
  }
}

class _QueryCard extends StatelessWidget {
  final TraceStep t;
  final bool expanded;
  final VoidCallback onTap;
  const _QueryCard({required this.t, required this.expanded, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: Tone.paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: expanded ? Tone.ink : Tone.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.tool, style: mono(14, weight: FontWeight.w700)),
                    if (t.detail.isNotEmpty) Text(t.detail, style: sans(13, color: Tone.ink2)),
                  ]),
                ),
                Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: expanded ? Tone.ink : Tone.ink2),
              ]),
            ),
          ),
          if (expanded && t.cypher.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(color: Tone.ink, borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText.rich(
                    TextSpan(children: highlightCypher(t.cypher), style: mono(12, color: Color(0xFFE6EDF3), height: 1.5)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: Tone.ink3)),
                  child: Text('READ-ONLY', style: mono(12, weight: FontWeight.w600, color: Tone.ink2)),
                ),
                SizedBox(width: 8),
                Expanded(child: Text(t.detail, style: mono(12, color: Tone.ink2), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ],
        ]),
      );
}

// ---- Ask -------------------------------------------------------------------------------------------
class _Turn {
  final String q;
  AskResult? result;
  String? error;
  bool busy = true;
  _Turn(this.q);
}

/// Ask Claude about this case. It answers only from graph queries and lists the ones it used.
class AskPanel extends StatefulWidget {
  final EcoApi api;
  final String? caseId;
  /// Sent as the first question as soon as the panel opens (used by the Home screen shortcut).
  final String? autoAsk;
  /// Called after the agent saved a proposal, so the screen can reload and show it.
  final Future<void> Function()? onWrote;
  const AskPanel({Key? key, required this.api, required this.caseId, this.onWrote, this.autoAsk}) : super(key: key);
  @override
  State<AskPanel> createState() => _AskPanelState();
}

class _AskPanelState extends State<AskPanel> with AutomaticKeepAliveClientMixin {
  final q = TextEditingController();
  final scroll = ScrollController();
  final turns = <_Turn>[];
  bool busy = false;
  bool? agentOn;
  String? model;

  static const _caseIdeas = ["Why is this risky?", "What should I freeze?", "Is any broker in a loop?", "Triage every open case"];
  static const _wideIdeas = ["Triage every open case", "Which broker sits in the most loops?", "Which case has the most tonnes at risk?"];
  List<String> get _ideas => widget.caseId == null ? _wideIdeas : _caseIdeas;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _checkAgent();
    final a = widget.autoAsk;
    if (a != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) send(a);
      });
    }
  }

  @override
  void dispose() {
    q.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _checkAgent() async {
    try {
      final h = await widget.api.health();
      if (mounted) {
        setState(() {
          agentOn = h['agent'] == true;
          model = h['model'] is String ? h['model'] as String : null;
        });
      }
    } catch (_) {
      // the case view shows its own error if the server is down
    }
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) scroll.animateTo(scroll.position.maxScrollExtent, duration: Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> send([String? preset]) async {
    final text = (preset ?? q.text).trim();
    if (text.isEmpty || busy) return;
    q.clear();
    final t = _Turn(text);
    setState(() {
      turns.add(t);
      busy = true;
    });
    _toEnd();
    try {
      t.result = await widget.api.ask(text, caseId: widget.caseId);
    } on ApiException catch (e) {
      t.error = e.unavailable ? 'The AI assistant is not switched on for this server. Everything else still works.' : e.message;
    } catch (e) {
      t.error = e.toString();
    }
    t.busy = false;
    if (mounted) setState(() => busy = false);
    final r = t.result;
    if (r != null && r.calls.any((s) => s.tool == 'propose_action')) {
      try {
        await widget.onWrote?.call();
      } catch (_) {
        // the proposal is saved either way; the next reload will show it
      }
    }
    _toEnd();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      Expanded(
        child: ListView(controller: scroll, padding: EdgeInsets.fromLTRB(16, 10, 16, 12), children: [
          if (agentOn == false)
            Container(
              margin: EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(color: Tone.amberTint, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tone.amber)),
              child: Text('The AI assistant is switched off on this server. Everything else still works.', style: sans(14, color: Tone.amber, height: 1.4)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final s in _ideas)
                Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Material(
                    color: Tone.paper,
                    shape: StadiumBorder(side: BorderSide(color: Tone.ink3, width: 1.5)),
                    child: InkWell(
                      customBorder: StadiumBorder(),
                      onTap: busy ? null : () => send(s),
                      child: SizedBox(height: 44, child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Center(child: Text(s, style: sans(14, weight: FontWeight.w600))))),
                    ),
                  ),
                ),
            ]),
          ),
          for (final t in turns) ..._turn(t),
        ]),
      ),
      _composer(),
    ]);
  }

  List<Widget> _turn(_Turn t) => [
        SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: 300),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: Tone.ink, borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(4))),
            child: Text(t.q, style: sans(15, color: Colors.white, height: 1.4)),
          ),
        ),
        SizedBox(height: 12),
        if (t.busy)
          _card(Row(children: [
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Tone.ink)),
            SizedBox(width: 12),
            Expanded(child: Text('Reading the graph. This takes a few seconds.', style: sans(15, color: Tone.ink2))),
          ]))
        else if (t.error != null)
          _card(Text(t.error!, style: sans(15, color: Tone.vermilion, height: 1.4)))
        else ...[
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ANSWER', style: mono(12, weight: FontWeight.w700, color: Tone.ink2, spacing: 1)),
            SizedBox(height: 6),
            MdText(t.result!.answer),
          ])),
          if (t.result!.calls.isNotEmpty) ...[SizedBox(height: 12), _calls(t.result!.calls)],
        ],
      ];

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
        child: child,
      );

  Widget _calls(List<TraceStep> calls) => Container(
        width: double.infinity,
        decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(children: [
              Expanded(child: Text('What it looked at', style: sans(14, weight: FontWeight.w700))),
              Text('${calls.length} ${calls.length == 1 ? 'tool' : 'tools'}', style: mono(12, color: Tone.ink2)),
            ]),
          ),
          for (final c in calls)
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Tone.line2))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(c.tool, style: mono(13, weight: FontWeight.w700))),
                  if (c.tool == 'propose_action')
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: Tone.vermilion)),
                      child: Text('SAVED A NOTE', style: mono(12, weight: FontWeight.w700, color: Tone.vermilion)),
                    ),
                ]),
                if (c.detail.isNotEmpty) Text(c.detail, style: sans(13, color: Tone.ink2, height: 1.3)),
              ]),
            ),
        ]),
      );

  Widget _composer() => Container(
        decoration: BoxDecoration(color: Tone.paper, border: Border(top: BorderSide(color: Tone.line))),
        padding: EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Answers come only from graph queries. The agent can propose an action but cannot freeze anything.${model == null ? '' : ' Model: $model.'}',
              style: sans(12, color: Tone.ink2, height: 1.3)),
          SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 56,
                child: TextField(
                  controller: q,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => send(),
                  style: sans(16),
                  decoration: InputDecoration(
                    hintText: 'Ask about this case',
                    hintStyle: sans(16, color: Tone.ink3),
                    filled: true,
                    fillColor: Tone.paper,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Tone.ink3, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Tone.ink, width: 2)),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8),
            Material(
              color: busy ? Tone.ink3 : Tone.ink,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: busy ? null : () => send(),
                child: SizedBox(width: 56, height: 56, child: Icon(Icons.arrow_forward, color: Colors.white)),
              ),
            ),
          ]),
        ]),
      );
}

// ---- Decisions -------------------------------------------------------------------------------------
Color actionColor(String action) => action == 'freeze' ? Tone.vermilion : action == 'refer' ? Tone.amber : Tone.ink;

/// One line for the queue: the agent has proposed something on this case.
class ProposalTag extends StatelessWidget {
  final Proposal p;
  const ProposalTag({Key? key, required this.p}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final col = actionColor(p.action);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.auto_awesome, size: 14, color: col),
      SizedBox(width: 6),
      Text('AGENT PROPOSES · ${p.action.toUpperCase()}', style: mono(12, weight: FontWeight.w700, color: col, spacing: 0.8)),
    ]);
  }
}

/// What the agent recommended on an open case, with its reason. Hidden when it has proposed nothing.
/// It is only a note: the buttons in the decision bar are the only way anything happens.
class ProposalBanner extends StatelessWidget {
  final CaseSummary c;
  final EdgeInsets margin;
  const ProposalBanner({Key? key, required this.c, this.margin = const EdgeInsets.fromLTRB(16, 10, 16, 0)}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = c.proposal;
    if (p == null || c.status != 'open') return SizedBox.shrink();
    final col = actionColor(p.action);
    final tint = p.action == 'freeze' ? Tone.vermilionTint : p.action == 'refer' ? Tone.amberTint : Tone.line2;
    return Container(
      width: double.infinity,
      margin: margin,
      padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(18), border: Border.all(color: col)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ProposalTag(p: p),
        SizedBox(height: 6),
        Text(p.rationale, style: sans(14, height: 1.4)),
        SizedBox(height: 4),
        Text('A note only. Nothing happens until you decide.', style: sans(12, color: Tone.ink2)),
      ]),
    );
  }
}

/// Freeze / Refer / Dismiss. The suggested action is the filled one. Once decided, shows what was recorded.
class DecisionBar extends StatelessWidget {
  final CaseDetail c;
  final void Function(String action) onDecide;
  const DecisionBar({Key? key, required this.c, required this.onDecide}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (c.status != 'open') {
      body = Row(children: [
        decidedStamp(c.status),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Decision recorded${c.creditsFrozen > 0 ? ': ${c.creditsFrozen} credits frozen' : ''}${(c.note ?? '').isNotEmpty ? '. Note: ${c.note}' : ''}',
            style: sans(14, color: Tone.ink2, height: 1.35),
          ),
        ),
      ]);
    } else {
      Widget btn(String a, String label, {int flex = 1, Widget? icon}) {
        final filled = c.suggested == a;
        return Expanded(
          flex: flex,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: ActionButton(label: label, color: actionColor(a), filled: filled, icon: icon, onPressed: () => onDecide(a)),
          ),
        );
      }

      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 8), child: Text('The agent only recommends. You decide.', style: sans(12, color: Tone.ink2))),
        Row(children: [
          btn('freeze', 'Freeze', flex: 13, icon: SnowIcon(size: 18, color: c.suggested == 'freeze' ? Colors.white : Tone.ink)),
          btn('refer', 'Refer', flex: 10),
          btn('dismiss', 'Dismiss', flex: 10),
        ]),
      ]);
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Tone.paper, border: Border(top: BorderSide(color: Tone.line))),
      padding: EdgeInsets.fromLTRB(12, 10, 12, 14),
      child: body,
    );
  }
}

/// Bottom sheet that asks the person to confirm. Returns the note (maybe empty) on confirm, null on cancel.
Future<String?> showDecisionSheet(BuildContext context, CaseDetail c, String action) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tone.paper,
      constraints: BoxConstraints(maxWidth: 560),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
      builder: (ctx) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom), child: _DecisionSheet(c: c, action: action)),
    );

class _DecisionSheet extends StatefulWidget {
  final CaseDetail c;
  final String action;
  const _DecisionSheet({required this.c, required this.action});
  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final a = widget.action;
    final col = actionColor(a);
    final title = {'freeze': 'Freeze these credits', 'refer': 'Refer to the registries', 'dismiss': 'Dismiss as a false alarm'}[a]!;
    final text = {
      'freeze': 'This marks ${c.creditsAtRisk} credits as frozen in the graph and logs your decision. You can find it later in the audit log.',
      'refer': 'This asks the registries to resolve the case and logs your decision. No credit is frozen.',
      'dismiss': 'This closes the case as a false alarm and logs your decision. No credit is frozen.',
    }[a]!;
    final confirm = {'freeze': 'Confirm freeze', 'refer': 'Confirm referral', 'dismiss': 'Confirm dismissal'}[a]!;
    final Widget icon = a == 'freeze' ? SnowIcon(size: 22, color: col) : Icon(a == 'refer' ? Icons.north_east : Icons.close, size: 22, color: col);
    final ids = c.atRiskIds;
    final shown = ids.length > 8 ? ids.sublist(0, 8) : ids;
    final more = c.creditsAtRisk - shown.length;
    final found = c.findings.map((f) => findingLabel('${f['type']}').toLowerCase()).toSet().join(', ');
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Tone.dots, borderRadius: BorderRadius.circular(2)))),
          SizedBox(height: 16),
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(shape: BoxShape.circle, color: a == 'freeze' ? Tone.vermilionTint : a == 'refer' ? Tone.amberTint : Tone.line2),
              child: Center(child: icon),
            ),
            SizedBox(width: 12),
            Expanded(child: Text(title, style: sans(22, weight: FontWeight.w700, spacing: -0.2))),
          ]),
          SizedBox(height: 12),
          Text(text, style: sans(15, color: Tone.ink2, height: 1.45)),
          if (a == 'freeze' && ids.isNotEmpty) ...[
            SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(color: Color(0xFFF3F5F7), borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('CREDITS TO FREEZE', style: mono(12, weight: FontWeight.w700, color: Tone.ink2, spacing: 1))),
                  Text('${c.creditsAtRisk} · ${fmtInt(c.tonnesAtRisk)} t', style: mono(13, weight: FontWeight.w700)),
                ]),
                SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final id in shown)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tone.vermilion)),
                      child: Text(id, style: mono(12, weight: FontWeight.w600)),
                    ),
                  if (more > 0) Padding(padding: EdgeInsets.only(top: 4), child: Text('+ $more more', style: mono(12, color: Tone.ink2))),
                ]),
                if (found.isNotEmpty) ...[SizedBox(height: 8), Text('Found by: $found.', style: sans(13, color: Tone.ink2, height: 1.35))],
              ]),
            ),
          ],
          SizedBox(height: 14),
          Text('Note (optional)', style: sans(13, weight: FontWeight.w600, color: Tone.ink2)),
          SizedBox(height: 6),
          SizedBox(
            height: 52,
            child: TextField(
              controller: note,
              inputFormatters: [LengthLimitingTextInputFormatter(300)],
              style: sans(16),
              decoration: InputDecoration(
                hintText: 'For example: checked with the registry',
                hintStyle: sans(16, color: Tone.ink3),
                filled: true,
                fillColor: Tone.paper,
                contentPadding: EdgeInsets.symmetric(horizontal: 14),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Tone.ink3, width: 1.5)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: Tone.ink, width: 2)),
              ),
            ),
          ),
          SizedBox(height: 16),
          ActionButton(label: confirm, color: col, icon: a == 'freeze' ? SnowIcon(size: 18, color: Colors.white) : null, onPressed: () => Navigator.pop(context, note.text.trim())),
          SizedBox(height: 6),
          SizedBox(
            height: 48,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.pop(context),
              child: Center(child: Text('Cancel', style: sans(16, weight: FontWeight.w600, color: Tone.ink2))),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Opens the confirm sheet and, if confirmed, records the decision. Returns null if cancelled or it failed (an error is shown).
Future<DecisionResult?> runDecision(BuildContext context, EcoApi api, CaseDetail c, String action) async {
  final note = await showDecisionSheet(context, c, action);
  if (note == null) return null;
  try {
    return await api.decide(c.id, action, note: note);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return null;
  }
}

/// Asks first, then rebuilds the demo ledger for everyone using this server. Returns true when it was reset.
Future<bool> confirmReset(BuildContext context, EcoApi api) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Tone.paper,
      title: Text('Reset the demo?', style: sans(20, weight: FontWeight.w700)),
      content: Text('This clears every decision and rebuilds the synthetic ledger, for everyone using this server.',
          style: sans(15, color: Tone.ink2, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: sans(15, weight: FontWeight.w600, color: Tone.ink2))),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Reset', style: sans(15, weight: FontWeight.w700, color: Tone.vermilion))),
      ],
    ),
  );
  if (ok != true) return false;
  try {
    await api.reset();
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return false;
  }
}
