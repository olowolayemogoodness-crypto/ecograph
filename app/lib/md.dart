// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_super_parameters
import 'package:flutter/material.dart';

import 'theme.dart';

/// A small Markdown renderer for the agent's answers: headings, bullets, numbered lists, **bold**, *italic* and `code`.
class MdText extends StatelessWidget {
  final String text;
  final double size;
  const MdText(this.text, {Key? key, this.size = 15}) : super(key: key);

  static final _bullet = RegExp(r'^(\s*)([-*•])\s+(.*)$');
  static final _number = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final _heading = RegExp(r'^#{1,6}\s+(.*)$');

  @override
  Widget build(BuildContext context) {
    final out = <Widget>[];
    for (final raw in text.replaceAll('\r', '').split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        out.add(SizedBox(height: 8));
        continue;
      }
      final h = _heading.firstMatch(line);
      final b = _bullet.firstMatch(line);
      final n = _number.firstMatch(line);
      if (h != null) {
        out.add(Padding(padding: EdgeInsets.only(top: 6, bottom: 2), child: _rich(h.group(1)!, sans(size + 2, weight: FontWeight.w800, height: 1.3))));
      } else if (b != null) {
        final indent = (b.group(1)!.length ~/ 2) * 14.0;
        out.add(_item(Container(margin: EdgeInsets.only(top: size * 0.55), width: 5, height: 5, decoration: BoxDecoration(color: Tone.ink2, shape: BoxShape.circle)), b.group(3)!, indent));
      } else if (n != null) {
        final indent = (n.group(1)!.length ~/ 2) * 14.0;
        out.add(_item(SizedBox(width: 20, child: Text('${n.group(2)}.', style: sans(size, weight: FontWeight.w700, color: Tone.ink2, height: 1.45))), n.group(3)!, indent));
      } else {
        out.add(_rich(line, sans(size, height: 1.5)));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }

  Widget _item(Widget lead, String body, double indent) => Padding(
        padding: EdgeInsets.only(left: indent, top: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 22, child: Align(alignment: Alignment.topLeft, child: lead)),
          Expanded(child: _rich(body, sans(size, height: 1.5))),
        ]),
      );

  /// Inline styles: **bold**, *italic*, `code`.
  Widget _rich(String s, TextStyle base) {
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\*(.+?)\*|_(.+?)_');
    var at = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > at) spans.add(TextSpan(text: s.substring(at, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: TextStyle(fontWeight: FontWeight.w800)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: ' ${m.group(2)} ',
          style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: base.fontSize! * 0.86, backgroundColor: Tone.line2, color: Tone.ink),
        ));
      } else {
        spans.add(TextSpan(text: m.group(3) ?? m.group(4), style: TextStyle(fontStyle: FontStyle.italic)));
      }
      at = m.end;
    }
    if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}
