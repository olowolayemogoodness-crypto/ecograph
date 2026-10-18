// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables, use_super_parameters
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'eco_api.dart';
import 'shell.dart';
import 'theme.dart';

/// Soft blobs that drift and melt into each other (blur, then a hard alpha threshold = the "goo" effect).
class GooField extends StatefulWidget {
  final List<Color> colors;
  final Color background;
  final double blobScale;
  const GooField({Key? key, required this.colors, required this.background, this.blobScale = 1}) : super(key: key);
  @override
  State<GooField> createState() => _GooFieldState();
}

class _GooFieldState extends State<GooField> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: Duration(seconds: 14))..repeat();
  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ColoredBox(
          color: widget.background,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(<double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 22, -9]),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: AnimatedBuilder(
                animation: c,
                builder: (context, _) => CustomPaint(painter: _GooPainter(c.value, widget.colors, widget.blobScale), size: Size.infinite),
              ),
            ),
          ),
        ),
      );
}

class _GooPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  final double k;
  _GooPainter(this.t, this.colors, this.k);
  @override
  void paint(Canvas canvas, Size size) {
    final base = math.min(size.width, size.height);
    for (var i = 0; i < colors.length; i++) {
      final a = t * 2 * math.pi + i * 2.1;
      final cx = size.width * (0.5 + 0.30 * math.sin(a + i)) ;
      final cy = size.height * (0.5 + 0.26 * math.cos(a * 0.8 + i * 1.7));
      final r = base * (0.15 + 0.035 * math.sin(a * 1.6 + i)) * k * (i == 0 ? 1.5 : 1.0);
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(_GooPainter old) => old.t != t;
}

/// 1. Splash: blobs melt together, the mark pops in, then on to the welcome page.
class SplashScreen extends StatefulWidget {
  final EcoApi api;
  const SplashScreen({Key? key, required this.api}) : super(key: key);
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 2600), () {
      if (mounted) Navigator.pushReplacement(context, EcoRoute(WelcomeScreen(api: widget.api)));
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Tone.ink,
        body: Stack(fit: StackFit.expand, children: [
          GooField(colors: [Color(0xFF1B2540), Tone.agent, Color(0xFF26324F), Tone.coral, Color(0xFF3A4A78)], background: Tone.ink),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Duration(milliseconds: 1300),
              curve: Curves.elasticOut,
              builder: (context, t, _) => Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * t,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(color: Tone.ground, borderRadius: BorderRadius.circular(30)),
                      child: Center(child: Glyph(size: 54, color: Tone.ink, accent: Tone.vermilion)),
                    ),
                    SizedBox(height: 22),
                    Text('EcoGraph', style: sans(36, weight: FontWeight.w800, color: Colors.white, spacing: -1)),
                    SizedBox(height: 6),
                    Text('FINDS CREDITS COUNTED TWICE', style: mono(11, color: Tone.navyText, spacing: 1.6)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// 2. Welcome: what it does, one button in. Sign-in will sit here later.
class WelcomeScreen extends StatelessWidget {
  final EcoApi api;
  const WelcomeScreen({Key? key, required this.api}) : super(key: key);

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520),
            child: Column(children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: Stack(fit: StackFit.expand, children: [
                      GooField(colors: [Tone.sand, Tone.coral, Color(0xFFB8C2F5), Color(0xFFF2D9A6), Color(0xFFFFC9BF)], background: Color(0xFFFBF7EE), blobScale: 1.1),
                      Positioned(left: 22, top: 22, child: Wordmark(size: 20)),
                    ]),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(28, 26, 28, 24),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Reveal(child: Text('Find carbon credits that were counted twice.', style: sans(32, weight: FontWeight.w800, height: 1.08, spacing: -1))),
                    SizedBox(height: 12),
                    Reveal(
                      index: 2,
                      child: Text('An agent reasons over a graph of projects, land, credits and buyers. You make the call.',
                          style: sans(16, color: Tone.ink2, height: 1.45)),
                    ),
                    Spacer(),
                    Reveal(
                      index: 4,
                      child: ActionButton(
                        label: 'Get started',
                        onPressed: () => Navigator.pushReplacement(context, EcoRoute(AppShell(api: api))),
                      ),
                    ),
                    SizedBox(height: 12),
                    Center(child: Text('Synthetic data only · powered by FalkorDB', style: mono(11, color: Tone.ink3, spacing: 0.4))),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}
