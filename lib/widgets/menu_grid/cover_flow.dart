import 'package:flutter/material.dart';

/// One card in a [CoverFlow]: a visual [face], a [label] shown under the
/// centered card, and an optional [onTap] fired when the centered card is
/// tapped. Leave [onTap] null for faces that handle their own interaction.
class CoverFlowItem {
  final Widget face;
  final String label;
  final VoidCallback? onTap;
  const CoverFlowItem({required this.face, required this.label, this.onTap});
}

/// PS Vita / RetroFlow-style cover flow: near-upright cards fanned out from the
/// center like a deck, the centered one enlarged and on top, far ones
/// compressing to slivers, each with a mirrored reflection. Drag to browse;
/// snaps to a card.
class CoverFlow extends StatefulWidget {
  final List<CoverFlowItem> items;

  /// Card width / height. 1.0 = square (consoles); < 1 = portrait (game boxart).
  final double aspectRatio;

  const CoverFlow({super.key, required this.items, this.aspectRatio = 1.0});

  @override
  State<CoverFlow> createState() => _CoverFlowState();
}

class _CoverFlowState extends State<CoverFlow> with SingleTickerProviderStateMixin {
  double _position = 0; // continuous centered index
  late final AnimationController _snap;
  Animation<double>? _snapAnim;

  static const double _tilt = 0.22; // subtle Y rotation (radians) — near upright
  static const int _window = 6;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _snap.addListener(() {
      if (_snapAnim != null) setState(() => _position = _snapAnim!.value);
    });
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  int get _last => widget.items.length - 1;

  void _animateTo(int target) {
    _snapAnim = Tween<double>(begin: _position, end: target.clamp(0, _last).toDouble())
        .animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    _snap
      ..reset()
      ..forward();
  }

  void _onEnd(double velocity) {
    int target = _position.round();
    if (velocity.abs() > 400) target = velocity < 0 ? _position.ceil() : _position.floor();
    _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fit card + its 0.42 reflection within the height left after the label,
        // and cap the width so the centered card isn't absurdly wide.
        final budget = (constraints.maxHeight - 56).clamp(160.0, double.infinity);
        double cardH = budget / 1.44;
        final maxCardW = constraints.maxWidth * 0.5;
        if (cardH * widget.aspectRatio > maxCardW) cardH = maxCardW / widget.aspectRatio;
        final cardW = cardH * widget.aspectRatio;
        final nearGap = cardW * 0.52; // spacing of the immediate neighbours
        final farStep = cardW * 0.13; // far cards compress into slivers
        final step = nearGap; // drag sensitivity

        final visible = <int>[];
        for (int i = 0; i < widget.items.length; i++) {
          if ((i - _position).abs() <= _window) visible.add(i);
        }
        // Paint far-to-near so the centered card ends up on top.
        visible.sort((a, b) => (b - _position).abs().compareTo((a - _position).abs()));

        return GestureDetector(
          onHorizontalDragUpdate: (d) {
            _snap.stop();
            setState(() => _position = (_position - d.delta.dx / step).clamp(0.0, _last.toDouble()));
          },
          onHorizontalDragEnd: (d) => _onEnd(d.primaryVelocity ?? 0),
          child: Column(
            children: [
              Expanded(
                child: ClipRect(
                  child: SizedBox.expand(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        for (final i in visible) _card(i, cardW, cardH, nearGap, farStep),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _label(),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _card(int i, double cardW, double cardH, double nearGap, double farStep) {
    final d = i - _position;
    final a = d.abs();
    final sign = d.isNegative ? -1.0 : 1.0;
    final t = d.clamp(-1.0, 1.0);

    final x = a <= 1 ? d * nearGap : sign * (nearGap + (a - 1) * farStep);
    final rot = t * _tilt;
    final scale = (1 - a * 0.10).clamp(0.6, 1.0);
    final opacity = (1 - a * 0.10).clamp(0.45, 1.0);

    final card = GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () {
        if (_position.round() == i) {
          widget.items[i].onTap?.call();
        } else {
          _animateTo(i);
        }
      },
      child: _cardWithReflection(cardW, cardH, widget.items[i].face),
    );

    // Horizontal placement kept separate from the perspective tilt/scale so the
    // math stays predictable.
    return Transform.translate(
      offset: Offset(x, 0),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012) // perspective
          ..rotateY(rot)
          ..scaleByDouble(scale, scale, scale, 1.0),
        child: Opacity(opacity: opacity, child: card),
      ),
    );
  }

  Widget _cardWithReflection(double w, double h, Widget face) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: w, height: h, child: face),
        const SizedBox(height: 2),
        IgnorePointer(
          child: SizedBox(
            width: w,
            height: h * 0.42,
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x9EFFFFFF), Color(0x00FFFFFF)],
              ).createShader(rect),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  maxHeight: h,
                  // Vertically mirrored face; its top row is the card's bottom row.
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..scaleByDouble(1.0, -1.0, 1.0, 1.0),
                    child: SizedBox(width: w, height: h, child: face),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label() {
    final i = _position.round().clamp(0, _last);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        widget.items[i].label,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
