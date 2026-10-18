// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_super_parameters
import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';

class Tone {
  static const ground = Color(0xFFE6F2D3);
  static const paper = Color(0xFFFFFFFF);
  static const ink = Color(0xFF0B2E1C);
  static const ink2 = Color(0xFF3A5643);
  static const ink3 = Color(0xFF4B6654);
  static const line = Color(0xFFCFE2B8);
  static const line2 = Color(0xFFDDEBC9);
  static const dots = Color(0xFFB5CF9A);
  static const plot = Color(0xFFF1F8E6);
  static const edge = Color(0xFF6E8F78);
  static const vermilion = Color(0xFFC8321F);
  static const vermilionTint = Color(0xFFFBE9E5);
  static const coral = Color(0xFFFF9A8A);
  static const amber = Color(0xFF8A4A05);
  static const amberTint = Color(0xFFFBEFD9);
  static const verdigris = Color(0xFF0F766E);
  static const verdigrisTint = Color(0xFFE1F2EE);
  static const agent = Color(0xFF2F3FC2);
  static const agentTint = Color(0xFFE8EBFD);
  static const sand = Color(0xFFE2B866);
  static const leaf = Color(0xFF8CC63F);
  static const forest = Color(0xFF136437);
  static const leafTint = Color(0xFFEFF7E1);
  static const navyLine = Color(0xFF2A6B45);
  static const navyText = Color(0xFFD3EBC2);
  static const navyMuted = Color(0xFF9CC4A0);
  static const navyCard = Color(0xFF0F4A2A);

  static const rCard = 24.0;
  static const rInner = 18.0;
}

const _sansFamily = 'SchibstedGrotesk';
const _monoFamily = 'JetBrainsMono';

TextStyle sans(double size, {FontWeight weight = FontWeight.w400, Color color = Tone.ink, double? height, double? spacing}) =>
    TextStyle(fontFamily: _sansFamily, fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

TextStyle mono(double size, {FontWeight weight = FontWeight.w400, Color color = Tone.ink, double? height, double? spacing}) =>
    TextStyle(fontFamily: _monoFamily, fontSize: size, fontWeight: weight, color: color, height: height, letterSpacing: spacing);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: Tone.forest, brightness: Brightness.light).copyWith(
    primary: Tone.ink,
    onPrimary: Colors.white,
    secondary: Tone.vermilion,
    surface: Tone.paper,
    error: Tone.vermilion,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tone.ground,
    fontFamily: _sansFamily,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Tone.ink,
      contentTextStyle: sans(14, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: Tone.paper, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Tone.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
  );
}

String fmtInt(num n) {
  final s = n.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

Color bandColor(String band) => band == 'freeze' ? Tone.vermilion : band == 'review' ? Tone.amber : Tone.ink3;

Color bandFill(String band) => band == 'freeze' ? Tone.vermilion : band == 'review' ? const Color(0xFFC97A10) : Tone.ink3;
Color bandTint(String band) => band == 'freeze' ? Tone.vermilionTint : band == 'review' ? Tone.amberTint : Tone.line2;
String bandLabel(String band) => band == 'freeze' ? 'FREEZE SUGGESTED' : band == 'review' ? 'NEEDS REVIEW' : 'WATCH';

String signalLabel(String s) => switch (s) {
      'double_retirement' => 'Double retirement',
      'registry_duplicate' => 'Same land on two registries',
      'overlap' => 'Overlap',
      'loop' => 'Trading loop',
      'no_audit' => 'No audit on file',
      _ => s.replaceAll('_', ' '),
    };

String findingLabel(String t) => switch (t) {
      'double_retirement' => 'DOUBLE RETIREMENT',
      'registry_duplicate' => 'REGISTRY DUPLICATE',
      'overlap' => 'OVERLAP',
      'loop' => 'TRADING LOOP',
      _ => t.toUpperCase().replaceAll('_', ' '),
    };

Color kindColor(String k) => switch (k) {
      'project' => const Color(0xFF0B2E1C),
      'parcel' => const Color(0xFFE2B866),
      'registry' => const Color(0xFF5E6B80),
      'credit' => const Color(0xFF4F8FE0),
      _ => const Color(0xFF8B7BD8),
    };
Color kindInk(String k) => k == 'parcel' || k == 'credit' || k == 'buyer' ? Tone.ink : Colors.white;
String kindLetter(String k) => switch (k) { 'project' => 'P', 'parcel' => 'L', 'registry' => 'R', 'credit' => 'C', _ => 'B' };
String kindName(String k) => switch (k) { 'project' => 'Project', 'parcel' => 'Land', 'registry' => 'Registry', 'credit' => 'Credit', _ => 'Buyer' };
bool kindSquare(String k) => k == 'project' || k == 'registry';

class SnowIcon extends StatelessWidget {
  final double size;
  final Color color;
  const SnowIcon({Key? key, this.size = 14, required this.color}) : super(key: key);
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SnowPainter(color)));
}

class _SnowPainter extends CustomPainter {
  final Color color;
  _SnowPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.42;
    for (final deg in <double>[90, 30, -30]) {
      final a = deg * pi / 180;
      final d = Offset(r * cos(a), r * sin(a));
      canvas.drawLine(c - d, c + d, p);
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) => old.color != color;
}

class Glyph extends StatelessWidget {
  final double size;
  final Color color;
  final Color accent;
  const Glyph({Key? key, this.size = 30, this.color = Tone.ink, this.accent = Tone.vermilion}) : super(key: key);
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _GlyphPainter(color, accent)));
}

class _GlyphPainter extends CustomPainter {
  final Color color, accent;
  _GlyphPainter(this.color, this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 28;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(14 * s, 9.5 * s), Offset(7 * s, 17 * s), line);
    canvas.drawLine(Offset(14 * s, 9.5 * s), Offset(21 * s, 17 * s), line);
    canvas.drawLine(Offset(9.5 * s, 20 * s), Offset(18.5 * s, 20 * s), line);
    canvas.drawCircle(Offset(6 * s, 20 * s), 3.6 * s, Paint()..color = color);
    canvas.drawCircle(Offset(22 * s, 20 * s), 3.6 * s, Paint()..color = color);
    canvas.drawCircle(Offset(14 * s, 6 * s), 3.6 * s, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.color != color || old.accent != accent;
}

class Wordmark extends StatelessWidget {
  final Color color;
  final Color glyph;
  final double size;
  const Wordmark({Key? key, this.color = Tone.ink, this.glyph = Tone.ink, this.size = 22}) : super(key: key);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/logo.png', height: size + 12, fit: BoxFit.contain)),
        SizedBox(width: 10),
        Text('EcoGraph', style: sans(size, weight: FontWeight.w700, color: color, spacing: -0.2)),
      ]);
}

class Stamp extends StatelessWidget {
  final String text;
  final Color color;
  final Color tint;
  final Widget? icon;
  final double fontSize;
  const Stamp({Key? key, required this.text, required this.color, required this.tint, this.icon, this.fontSize = 12}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[icon!, SizedBox(width: 6)],
          Text(text, style: mono(fontSize, weight: FontWeight.w700, color: color, spacing: fontSize * 0.06)),
        ]),
      );
}

Widget bandStamp(String band, {double fontSize = 12}) {
  final c = bandColor(band);
  final Widget icon = band == 'freeze'
      ? SnowIcon(size: fontSize + 2, color: c)
      : Icon(band == 'review' ? Icons.search : Icons.visibility_outlined, size: fontSize + 2, color: c);
  return Stamp(text: bandLabel(band), color: c, tint: bandTint(band), fontSize: fontSize, icon: icon);
}

Widget decidedStamp(String status, {double fontSize = 12}) =>
    Stamp(text: status.toUpperCase(), color: Tone.verdigris, tint: Tone.verdigrisTint, fontSize: fontSize);

class SyntheticTag extends StatelessWidget {
  final Color color;
  const SyntheticTag({Key? key, this.color = Tone.ink2}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: color)),
        child: Text('SYNTHETIC DATA', style: mono(12, weight: FontWeight.w600, color: color, spacing: 0.5)),
      );
}

class TickMeter extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  final bool marks;
  const TickMeter({Key? key, required this.value, required this.color, this.height = 8, this.marks = true}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final v = value < 0 ? 0.0 : (value > 1 ? 1.0 : value);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: v),
      duration: Duration(milliseconds: 900),
      curve: Curves.easeOutBack,
      builder: (context, t, _) => SizedBox(
        height: height + 8,
        width: double.infinity,
        child: CustomPaint(painter: _BarPainter(t < 0 ? 0.0 : t, color, height, marks)),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double v;
  final Color color;
  final double h;
  final bool marks;
  _BarPainter(this.v, this.color, this.h, this.marks);
  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - h) / 2;
    final track = RRect.fromRectAndRadius(Rect.fromLTWH(0, top, size.width, h), Radius.circular(h / 2));
    canvas.drawRRect(track, Paint()..color = Tone.line);
    final w = size.width * (v > 1 ? 1.0 : v);
    if (w > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, top, w < h ? h : w, h), Radius.circular(h / 2)), Paint()..color = color);
    }
    if (marks) {
      final m = Paint()
        ..color = Tone.ink.withValues(alpha: 0.55)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (final f in <double>[0.5, 0.85]) {
        canvas.drawLine(Offset(size.width * f, top - 3), Offset(size.width * f, top + h + 3), m);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.v != v || old.color != color || old.h != h;
}

class KindDot extends StatelessWidget {
  final String kind;
  final double size;
  const KindDot(this.kind, {Key? key, this.size = 18}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: kindColor(kind), borderRadius: BorderRadius.circular(kindSquare(kind) ? size * 0.34 : size / 2)),
        child: Text(kindLetter(kind), style: mono(size * 0.6, weight: FontWeight.w700, color: kindInk(kind))),
      );
}

class Bounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  const Bounce({Key? key, required this.child, required this.onTap, this.scale = 0.95}) : super(key: key);
  @override
  State<Bounce> createState() => _BounceState();
}

class _BounceState extends State<Bounce> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => down = true),
        onTapCancel: () => setState(() => down = false),
        onTapUp: (_) => setState(() => down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: down ? widget.scale : 1,
          duration: Duration(milliseconds: down ? 90 : 420),
          curve: down ? Curves.easeOut : Curves.elasticOut,
          child: widget.child,
        ),
      );
}

class Reveal extends StatelessWidget {
  final Widget child;
  final int index;
  const Reveal({Key? key, required this.child, this.index = 0}) : super(key: key);
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 520 + index * 70),
        curve: Curves.easeOutCubic,
        builder: (context, t, c) => Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, (1 - t) * 22), child: c)),
        child: child,
      );
}

class EcoRoute<T> extends PageRouteBuilder<T> {
  EcoRoute(Widget page)
      : super(
          transitionDuration: Duration(milliseconds: 420),
          reverseTransitionDuration: Duration(milliseconds: 320),
          pageBuilder: (_, _, _) => page,
          transitionsBuilder: (_, a, _, child) {
            final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(position: Tween(begin: Offset(0.0, 0.06), end: Offset.zero).animate(curved), child: child),
            );
          },
        );
}

class SquareButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const SquareButton({Key? key, required this.icon, required this.tooltip, required this.onPressed}) : super(key: key);
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Bounce(
          onTap: onPressed,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: Tone.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: Tone.line)),
            child: Icon(icon, size: 20, color: Tone.ink),
          ),
        ),
      );
}

class ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;
  final Widget? icon;
  const ActionButton({Key? key, required this.label, required this.onPressed, this.color = Tone.ink, this.filled = true, this.icon})
      : super(key: key);
  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : Tone.ink;
    return Bounce(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 250),
        height: 56,
        decoration: BoxDecoration(
          color: filled ? (onPressed == null ? Tone.line : color) : Colors.transparent,
          borderRadius: BorderRadius.circular(28),
          border: filled ? null : Border.all(color: Tone.ink, width: 1.5),
        ),
        child: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[icon!, SizedBox(width: 8)],
            Text(label, style: sans(17, weight: FontWeight.w700, color: onPressed == null ? Tone.ink3 : fg)),
          ]),
        ),
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({Key? key, this.color = Tone.agent, this.size = 9}) : super(key: key);
  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(milliseconds: 1400))..repeat(reverse: true);
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => SizedBox(
          width: widget.size * 2.2,
          height: widget.size * 2.2,
          child: Center(
            child: Container(
              width: widget.size * (0.8 + 0.5 * c.value),
              height: widget.size * (0.8 + 0.5 * c.value),
              decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color.withValues(alpha: 0.55 + 0.45 * (1 - c.value))),
            ),
          ),
        ),
      );
}

class AgentChip extends StatelessWidget {
  final String text;
  const AgentChip(this.text, {Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(9, 5, 12, 5),
        decoration: BoxDecoration(color: Tone.agentTint, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 15, height: 15, child: CustomPaint(painter: _AgentGlyph(Tone.agent))),
          SizedBox(width: 6),
          Text(text, style: sans(12.5, weight: FontWeight.w700, color: Tone.agent)),
        ]),
      );
}

class _AgentGlyph extends CustomPainter {
  final Color color;
  _AgentGlyph(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset(12 * s, 12 * s), 3 * s, line);
    for (final p in <Offset>[Offset(5, 6), Offset(19, 7), Offset(12, 20)]) {
      canvas.drawCircle(Offset(p.dx * s, p.dy * s), 1.7 * s, Paint()..color = color);
    }
    canvas.drawLine(Offset(10 * s, 10 * s), Offset(6.2 * s, 7.2 * s), line);
    canvas.drawLine(Offset(14 * s, 10.4 * s), Offset(17.8 * s, 8.2 * s), line);
    canvas.drawLine(Offset(12 * s, 15 * s), Offset(12 * s, 18.3 * s), line);
  }

  @override
  bool shouldRepaint(_AgentGlyph old) => old.color != color;
}

class ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorBox({Key? key, required this.message, required this.onRetry}) : super(key: key);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: Tone.ink3),
            SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: sans(15, color: Tone.ink2, height: 1.4)),
            SizedBox(height: 16),
            SizedBox(width: 180, child: ActionButton(label: 'Try again', onPressed: onRetry)),
          ]),
        ),
      );
}

String fmtWhen(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2}) UTC$').firstMatch(s);
  if (m == null) return s.toUpperCase();
  const mon = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  final i = int.parse(m.group(2)!) - 1;
  if (i < 0 || i > 11) return s.toUpperCase();
  return '${int.parse(m.group(3)!)} ${mon[i]} ${m.group(1)} · ${m.group(4)} UTC';
}

String actionWord(String action) => switch (action) { 'freeze' => 'FROZEN', 'refer' => 'REFERRED', 'dismiss' => 'DISMISSED', _ => action.toUpperCase() };

class EcoTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  final EdgeInsets margin;
  const EcoTabBar({Key? key, required this.controller, required this.labels, this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 4)}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: EdgeInsets.all(4),
        decoration: BoxDecoration(color: Color(0xFFD5E6BE), borderRadius: BorderRadius.circular(999)),
        child: TabBar(
          controller: controller,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(color: Tone.ink, borderRadius: BorderRadius.circular(999)),
          labelColor: Colors.white,
          unselectedLabelColor: Tone.ink2,
          labelStyle: sans(14, weight: FontWeight.w700),
          unselectedLabelStyle: sans(14, weight: FontWeight.w600),
          tabs: [for (final l in labels) Tab(height: 38, text: l)],
        ),
      );
}
