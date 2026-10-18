// ignore_for_file: prefer_const_constructors, use_super_parameters
import 'package:flutter/material.dart';

import 'eco_api.dart';
import 'theme.dart';

/// The evidence sub-graph of one case: pinch to zoom, red ring = part of the problem, dashed red = suspicious link.
/// The parent decides the size (put it in an AspectRatio).
class EvidenceGraph extends StatelessWidget {
  final List<EvNode> nodes;
  final List<EvEdge> edges;
  final double nodeRadius;

  /// Pinch to zoom. Turn off on desktop, where the mouse wheel should scroll the page instead.
  final bool zoomable;
  const EvidenceGraph({Key? key, required this.nodes, required this.edges, this.nodeRadius = 16, this.zoomable = true}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final drawing = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => SizedBox.expand(child: CustomPaint(painter: EvidencePainter(nodes, edges, nodeRadius, t))),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Tone.plot, border: Border.all(color: Tone.line), borderRadius: BorderRadius.circular(22)),
        child: zoomable ? InteractiveViewer(maxScale: 4, child: drawing) : drawing,
      ),
    );
  }
}

TextStyle _ts(double size, FontWeight w, Color c, {Paint? fg}) =>
    TextStyle(fontFamily: 'JetBrainsMono', fontSize: size, fontWeight: w, color: fg == null ? c : null, foreground: fg);

class EvidencePainter extends CustomPainter {
  final List<EvNode> nodes;
  final List<EvEdge> edges;
  final double r;
  final double t;
  EvidencePainter(this.nodes, this.edges, this.r, [this.t = 1]);

  @override
  void paint(Canvas canvas, Size size) {
    // dot grid
    final dot = Paint()..color = Tone.dots;
    for (double x = 8; x < size.width; x += 16) {
      for (double y = 8; y < size.height; y += 16) {
        canvas.drawCircle(Offset(x, y), 1, dot);
      }
    }
    const padX = 40.0, padTop = 32.0, padBottom = 54.0;
    Offset pos(EvNode n) => Offset(padX + n.x * (size.width - 2 * padX), padTop + n.y * (size.height - padTop - padBottom));
    final byId = {for (final n in nodes) n.id: n};

    // links first, so nodes sit on top
    final labels = <MapEntry<String, Offset>>[];
    for (final e in edges) {
      final a = byId[e.a], b = byId[e.b];
      if (a == null || b == null) continue;
      final pa = pos(a), pb = pos(b);
      final v = pb - pa;
      final len = v.distance;
      if (len < 2 * r + 14) continue;
      final u = v / len;
      final from = pa + u * (r + 5);
      final to = pb - u * (r + 8);
      final col = (e.flag ? Tone.vermilion : Tone.edge).withValues(alpha: t.clamp(0.0, 1.0));
      final stroke = Paint()
        ..color = col
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.flag ? 2.2 : 1.6
        ..strokeCap = StrokeCap.round;
      if (e.flag) {
        _dashed(canvas, from, to, stroke, 6, 5);
      } else {
        canvas.drawLine(from, to, stroke);
      }
      final side = Offset(-u.dy, u.dx);
      final tip = to + u * 2, base = to - u * 7;
      canvas.drawPath(
          Path()
            ..moveTo(tip.dx, tip.dy)
            ..lineTo(base.dx + side.dx * 4, base.dy + side.dy * 4)
            ..lineTo(base.dx - side.dx * 4, base.dy - side.dy * 4)
            ..close(),
          Paint()..color = col);
      if ((e.label ?? '').isNotEmpty) labels.add(MapEntry(e.label!, (pa + pb) / 2));
    }
    for (final l in labels) {
      _text(canvas, l.key, l.value, _ts(10.5, FontWeight.w400, Tone.ink2), background: Tone.plot);
    }

    // nodes
    final pop = Curves.easeOutBack.transform(t.clamp(0.0, 1.0));
    for (final n in nodes) {
      final p = pos(n);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.scale(pop);
      canvas.translate(-p.dx, -p.dy);
      final square = kindSquare(n.kind);
      final rect = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
      RRect shape(double grow) => RRect.fromRectAndRadius(rect.inflate(grow), Radius.circular(square ? r * 0.56 + grow : r + grow));
      if (n.flag) {
        canvas.drawRRect(shape(4.5), Paint()..color = Tone.vermilion);
        canvas.drawRRect(shape(2), Paint()..color = Tone.plot);
      }
      canvas.drawRRect(shape(0), Paint()..color = kindColor(n.kind));
      _text(canvas, kindLetter(n.kind), p, _ts(r * 0.78, FontWeight.w700, kindInk(n.kind)));
      final halo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = Tone.plot;
      _text(canvas, n.label, p + Offset(0, r + 14), _ts(11, FontWeight.w600, Tone.ink), halo: halo, haloStyle: _ts(11, FontWeight.w600, Tone.ink, fg: halo));
      if (n.sub.isNotEmpty) {
        _text(canvas, n.sub, p + Offset(0, r + 27), _ts(10, FontWeight.w400, Tone.ink2), halo: halo, haloStyle: _ts(10, FontWeight.w400, Tone.ink2, fg: halo));
      }
      canvas.restore();
    }
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double dash, double gap) {
    final v = b - a;
    final len = v.distance;
    if (len < 1) return;
    final u = v / len;
    var d = 0.0;
    while (d < len) {
      final end = d + dash < len ? d + dash : len;
      canvas.drawLine(a + u * d, a + u * end, paint);
      d += dash + gap;
    }
  }

  void _text(Canvas canvas, String s, Offset center, TextStyle style, {Color? background, Paint? halo, TextStyle? haloStyle}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')
      ..layout(maxWidth: 120);
    final off = center - Offset(tp.width / 2, tp.height / 2);
    if (background != null) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(off.dx - 4, off.dy - 1, tp.width + 8, tp.height + 2), Radius.circular(6)), Paint()..color = background);
    }
    if (halo != null && haloStyle != null) {
      final hp = TextPainter(text: TextSpan(text: s, style: haloStyle), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')
        ..layout(maxWidth: 120);
      hp.paint(canvas, off);
    }
    tp.paint(canvas, off);
  }

  @override
  bool shouldRepaint(EvidencePainter old) => old.nodes != nodes || old.edges != edges || old.r != r || old.t != t;
}

/// Key to the shapes, rings and dashed links.
class GraphLegend extends StatelessWidget {
  final List<String> kinds;
  const GraphLegend({Key? key, required this.kinds}) : super(key: key);

  @override
  Widget build(BuildContext context) => Wrap(spacing: 14, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final k in kinds)
          Row(mainAxisSize: MainAxisSize.min, children: [
            KindDot(k),
            SizedBox(width: 6),
            Text(kindName(k), style: sans(13, color: Tone.ink2)),
          ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Tone.vermilion, width: 2.5))),
          SizedBox(width: 6),
          Text('Part of the problem', style: sans(13, weight: FontWeight.w600, color: Tone.vermilion)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 26, height: 8, child: CustomPaint(painter: _DashSwatch())),
          SizedBox(width: 6),
          Text('Suspicious link', style: sans(13, weight: FontWeight.w600, color: Tone.vermilion)),
        ]),
      ]);
}

class _DashSwatch extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Tone.vermilion
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    var x = 1.0;
    while (x < size.width - 1) {
      final end = x + 5 < size.width - 1 ? x + 5 : size.width - 1;
      canvas.drawLine(Offset(x, size.height / 2), Offset(end, size.height / 2), p);
      x += 9;
    }
  }

  @override
  bool shouldRepaint(_DashSwatch old) => false;
}
