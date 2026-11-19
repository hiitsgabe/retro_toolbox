import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mesh_gradient/mesh_gradient.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/utils/handheld.dart';

import 'backdrop_clock.dart';
import 'paint_swirl.dart';

/// What sits behind every page (app.dart puts it there). Ported from
/// Kitchentable's backdrop.
///
/// The pages draw on top of this, so it is the look of the screen rather than
/// a ground colour. [still] is a screen that cannot afford motion (the
/// framebuffer handheld): the animated kinds then draw one frame.
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.style, required this.child, bool? still}) : _still = still;

  final BackdropStyle style;
  final Widget child;
  final bool? _still;

  @override
  Widget build(BuildContext context) {
    final still = _still ?? Handheld.framebuffer;
    // Each in a layer of its own. Sharing one meant every tick of the paint
    // repainted the whole menu over it.
    return Stack(
      children: [
        Positioned.fill(child: RepaintBoundary(child: _paint(still))),
        Positioned.fill(child: RepaintBoundary(child: child)),
      ],
    );
  }

  Widget _paint(bool still) => switch (style.kind) {
    // The drift is the fallback on purpose: it is the one that needs no
    // shader, so a platform without them still has a moving backdrop.
    BackdropKind.paint => still
        ? _Flat(style: style)
        : PaintSwirl(key: const ValueKey('backdrop-paint'), style: style, fallback: _Drift(style: style)),
    BackdropKind.aurora => still ? _Flat(style: style) : _Aurora(style: style),
    BackdropKind.drift => _Drift(style: style, still: still),
    BackdropKind.flat => _Flat(style: style),
    BackdropKind.dots => _Dots(style: style),
    BackdropKind.image => _Picture(style: style),
  };
}

class _Flat extends StatelessWidget {
  const _Flat({required this.style}) : super(key: const ValueKey('backdrop-flat'));

  final BackdropStyle style;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color.lerp(style.bottom, style.top, 0.14)!, style.bottom],
      ),
    ),
  );
}

/// Flat with a grid of dots in the top colour (Classic's own).
class _Dots extends StatelessWidget {
  const _Dots({required this.style}) : super(key: const ValueKey('backdrop-dots'));

  final BackdropStyle style;

  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _DotsPainter(style), child: _Flat(style: style));
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.style);

  final BackdropStyle style;

  static const step = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    // Faint: the grid is texture under the menus, not a pattern to look at.
    final dot = Paint()..color = style.top.withValues(alpha: 0.22);
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.style != style;
}

/// The fluid one, and with Paint the only part of the app that leans on a
/// fragment shader. If the shader ever stops working the other kinds still do,
/// which is why the player can pick.
class _Aurora extends StatelessWidget {
  const _Aurora({required this.style}) : super(key: const ValueKey('backdrop-aurora'));

  final BackdropStyle style;

  @override
  Widget build(BuildContext context) {
    final bottom = style.bottom;
    final top = style.top;

    return AnimatedMeshGradient(
      colors: [
        bottom,
        Color.lerp(bottom, top, 0.55)!,
        Color.lerp(bottom, top, 0.12)!,
        Color.lerp(bottom, top, 0.32)!,
      ],
      options: AnimatedMeshGradientOptions(speed: 1.4, frequency: 2.6),
    );
  }
}

/// Painted rather than shaded: three blobs drifting on long, prime-ish periods
/// so the loop never lines up and never reads as a loop. [still] draws the
/// first frame once, with no controller at all.
class _Drift extends StatefulWidget {
  const _Drift({required this.style, this.still = false}) : super(key: const ValueKey('backdrop-drift'));

  final BackdropStyle style;
  final bool still;

  @override
  State<_Drift> createState() => _DriftState();
}

class _DriftState extends State<_Drift> with SingleTickerProviderStateMixin {
  AnimationController? _clock;

  @override
  void initState() {
    super.initState();
    if (!widget.still) {
      const period = Duration(seconds: 60);
      _clock = AnimationController(vsync: this, duration: period, value: backdropPhase(period))..repeat();
    }
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clock = _clock;
    if (clock == null) {
      return CustomPaint(painter: _DriftPainter(style: widget.style, t: 0), size: Size.infinite);
    }
    return AnimatedBuilder(
      animation: clock,
      builder: (_, __) => CustomPaint(painter: _DriftPainter(style: widget.style, t: clock.value)),
    );
  }
}

class _DriftPainter extends CustomPainter {
  _DriftPainter({required this.style, required this.t});

  final BackdropStyle style;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = style.bottom);

    const periods = [1.0, 0.61, 0.37];
    const origins = [Offset(0.25, 0.3), Offset(0.78, 0.22), Offset(0.5, 0.85)];
    const strengths = [0.30, 0.22, 0.16];

    for (var i = 0; i < periods.length; i++) {
      final a = 2 * math.pi * (t * periods[i] + i / 3);
      final centre = Offset(
        (origins[i].dx + 0.12 * math.cos(a)) * size.width,
        (origins[i].dy + 0.10 * math.sin(a * 1.3)) * size.height,
      );
      final radius = size.shortestSide * (0.55 + 0.08 * math.sin(a));

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              style.top.withValues(alpha: strengths[i]),
              style.top.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_DriftPainter old) => old.t != t || old.style != style;
}

class _Picture extends StatelessWidget {
  const _Picture({required this.style});

  final BackdropStyle style;

  @override
  Widget build(BuildContext context) {
    // Dimmed, because the menus have to stay readable on top of whatever
    // somebody picked, and people pick bright pictures.
    final path = style.imagePath;
    if (path == null) return _Flat(style: style);

    return Image.file(
      File(path),
      key: const ValueKey('backdrop-image'),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _Flat(style: style),
      color: Colors.black.withValues(alpha: 0.45),
      colorBlendMode: BlendMode.darken,
    );
  }
}
