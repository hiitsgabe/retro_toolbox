import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:retro_toolbox/models/app_style.dart';

/// The swirling paint, drawn by `shaders/paint_swirl.frag`, which is a port
/// of the MIT licensed Balatro background from React Bits.
///
/// The program is loaded once for the life of the process and held here: it
/// is compiled by the engine on first use and asking for it per frame, or per
/// screen, is how a backdrop becomes a stutter.
///
/// [fallback] is drawn until it has loaded and for good if it will not load
/// at all, which is any platform whose renderer has no fragment shaders. The
/// backdrop is the one thing in the app that must never be the reason nothing
/// is on screen.
class PaintSwirl extends StatefulWidget {
  const PaintSwirl({super.key, required this.style, required this.fallback});

  final BackdropStyle style;
  final Widget fallback;

  static Future<ui.FragmentProgram?>? _loading;

  static Future<ui.FragmentProgram?> _program() =>
      _loading ??= ui.FragmentProgram.fromAsset('shaders/paint_swirl.frag')
          .then<ui.FragmentProgram?>((p) => p)
          .catchError((Object _) => null);

  @override
  State<PaintSwirl> createState() => _PaintSwirlState();
}

class _PaintSwirlState extends State<PaintSwirl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    // Long and looping, read as seconds rather than as a fraction: the shader
    // wants a clock, not a progress bar.
    duration: const Duration(minutes: 10),
  )..repeat();

  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    PaintSwirl._program().then((program) {
      if (!mounted || program == null) return;
      setState(() => _shader = program.fragmentShader());
    });
  }

  @override
  void dispose() {
    _clock.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null) return widget.fallback;

    return AnimatedBuilder(
      animation: _clock,
      builder: (_, __) => CustomPaint(
        painter: _SwirlPainter(
          shader: shader,
          seconds:
              _clock.value *
              _clock.duration!.inSeconds *
              _SwirlPainter.slow,
          style: widget.style,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SwirlPainter extends CustomPainter {
  _SwirlPainter({
    required this.shader,
    required this.seconds,
    required this.style,
  });

  final ui.FragmentShader shader;
  final double seconds;
  final BackdropStyle style;

  /// How much slower than the original it turns. The original is a game's
  /// title screen, where the paint is the show; here it sits behind a hand
  /// of cards for an evening, and at full speed it pulled the eye.
  ///
  /// Slower is the one economy taken. Painting it to a small offscreen
  /// image and stretching that, which would run the shader on a ninth of
  /// the pixels, was tried and on the web it was worse: each offscreen
  /// image is a new surface, and the frames came out uneven and slow.
  static const slow = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    // Three colours out of the player's two. The original is red against
    // blue over a near black; here the picked colour is the first, the second
    // is it taken most of the way to the ground so the two bands are the same
    // family rather than a clash, and the ground is the third.
    final three = style.bottom;
    final one = Color.lerp(three, style.top, 0.85)!;
    final two = Color.lerp(three, style.top, 0.32)!;

    // By index, in the order the shader declares them: uSize, uTime, then the
    // three colours. A uniform set out of order is a colour in the wrong
    // channel and nothing says so.
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, seconds)
      ..setFloat(3, one.r)
      ..setFloat(4, one.g)
      ..setFloat(5, one.b)
      ..setFloat(6, 1)
      ..setFloat(7, two.r)
      ..setFloat(8, two.g)
      ..setFloat(9, two.b)
      ..setFloat(10, 1)
      ..setFloat(11, three.r)
      ..setFloat(12, three.g)
      ..setFloat(13, three.b)
      ..setFloat(14, 1);

    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SwirlPainter old) =>
      old.seconds != seconds || old.style != style;
}
