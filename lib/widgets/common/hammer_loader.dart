import 'package:flutter/material.dart';

/// Loading indicator that swings the app's hammer logo like it's striking,
/// replacing the plain spinning circle on full-page loading states.
class HammerLoader extends StatefulWidget {
  const HammerLoader({super.key, this.size = 56});

  final double size;

  @override
  State<HammerLoader> createState() => _HammerLoaderState();
}

class _HammerLoaderState extends State<HammerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _angle;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    // Raise the head, snap it down past the anvil line, bounce, hold.
    _angle = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -0.6).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.6, end: 0.18).chain(CurveTween(curve: Curves.easeIn)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.18, end: 0.0).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 18,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 20),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _angle,
      builder: (context, child) => Transform.rotate(
        angle: _angle.value,
        alignment: Alignment.bottomRight, // pivot on the handle end
        child: child,
      ),
      child: Image.asset(
        'assets/icon.png',
        width: widget.size,
        height: widget.size,
        filterQuality: FilterQuality.none, // keep pixel art crisp
      ),
    );
  }
}
