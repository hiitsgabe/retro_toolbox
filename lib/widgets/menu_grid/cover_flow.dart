import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// One card in a [CoverFlow]: a visual [face], a [label] shown under the
/// centered card, and an optional [onTap] fired when the centered card is
/// tapped. Leave [onTap] null for faces that handle their own interaction.
/// [wrapFocus] wraps the flow's one focus stop while this item is centred, so
/// its gamepad bindings (e.g. X/Y) apply; use the same widget type for every
/// item or focus is lost while browsing.
class CoverFlowItem {
  final Widget face;
  final String label;
  final VoidCallback? onTap;
  final Widget Function(Widget focus)? wrapFocus;
  const CoverFlowItem({required this.face, required this.label, this.onTap, this.wrapFocus});
}

/// PS Vita / RetroFlow-style cover flow: near-upright cards fanned out from the
/// center like a deck, the centered one enlarged and on top, far ones
/// compressing to slivers, each with a mirrored reflection. Drag to browse;
/// snaps to a card.
class CoverFlow extends StatefulWidget {
  final List<CoverFlowItem> items;

  /// Card width / height. 1.0 = square (consoles); < 1 = portrait (game boxart).
  final double aspectRatio;

  /// When this changes to an index, the flow animates there (an L1/R1 jump).
  final int? jumpTo;

  /// The focus ring's shape round the centre card; null: the style's.
  final ShapeBorder? focusShape;

  /// Sees each key before the flow does, with the centre card's index (a
  /// menu's move mode); anything but ignored stops the key there.
  final KeyEventResult Function(int centre, KeyEvent e)? onKey;

  const CoverFlow({super.key, required this.items, this.aspectRatio = 1.0, this.jumpTo, this.focusShape, this.onKey});

  @override
  State<CoverFlow> createState() => _CoverFlowState();
}

class _CoverFlowState extends State<CoverFlow> with SingleTickerProviderStateMixin {
  double _position = 0; // continuous centered index
  late final AnimationController _snap;

  /// Where the centre card rests: the focus ring's place.
  final _slot = GlobalKey();
  Animation<double>? _snapAnim;

  static const double _tilt = 0.22; // subtle Y rotation (radians) — near upright
  /// Room kept between the farthest card and the screen's edge.
  static const double _gutter = 12;

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

  @override
  void didUpdateWidget(CoverFlow old) {
    super.didUpdateWidget(old);
    final target = widget.jumpTo;
    if (target != null && target != old.jumpTo) _animateTo(target);
  }

  void _animateTo(int target) {
    _snapAnim = Tween<double>(begin: _position, end: target.clamp(0, _last).toDouble())
        .animate(CurvedAnimation(parent: _snap, curve: Curves.easeOutCubic));
    _snap
      ..reset()
      ..forward();
  }

  // One focus stop for the whole flow: faces (and their reflections) are
  // ExcludeFocus'd, so Left/Right browse, Enter/Space/A opens, Up/Down leave.
  // Left/Right at the ends are swallowed so a held arrow can't spill over.
  // Start is left to the screen (DpadScope falls back to ActivateIntent, which
  // opens the centre card).
  static final _open = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.gameButtonA,
    LogicalKeyboardKey.select,
  };

  void _openCentre() {
    if (widget.items.isEmpty) return;
    widget.items[_position.round().clamp(0, _last)].onTap?.call();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (widget.items.isEmpty) return KeyEventResult.ignored;
    final centre = _position.round().clamp(0, _last);
    final first = widget.onKey?.call(centre, e) ?? KeyEventResult.ignored;
    if (first != KeyEventResult.ignored) return first;
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowLeft) {
      _animateTo(centre - 1);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _animateTo(centre + 1);
    } else if (e is KeyDownEvent && _open.contains(k)) {
      _openCentre();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
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
        // The centre card sits in the middle of its band, its reflection
        // hanging below it, the label right under the band, and the whole in
        // the middle of the height. Landscape keeps the sides for the fans; a
        // phone sizes the card from its height as much as from its width.
        final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
        final budget = (constraints.maxHeight - 56).clamp(160.0, double.infinity);
        double cardH = budget * (portrait ? 0.5 : 0.8);
        final maxCardW = constraints.maxWidth * (portrait ? 0.68 : 0.36);
        if (cardH * widget.aspectRatio > maxCardW) cardH = maxCardW / widget.aspectRatio;
        final cardW = cardH * widget.aspectRatio;
        // A phone shows more of the reflection, the title over its fading end.
        final gap = portrait ? cardH * 0.3 : math.max(16.0, cardH * 0.12);
        final band = math.min(portrait ? constraints.maxHeight : budget, cardH + 2 * gap);
        final nearGap = cardW * (portrait ? 0.46 : 0.62); // spacing of the immediate neighbours
        // The far cards fan out to the screen's edges: as many as the width
        // takes at a readable step, the last one ending at the gutter. A
        // phone has no room for that: two more peek past the first, as slivers.
        final edge = constraints.maxWidth / 2 - _gutter - cardW * 0.24;
        final room = edge - nearGap;
        final window = room < cardW * 0.16 ? 3 : ((room / (cardW * 0.16)).floor() + 1).clamp(3, 8);
        final farStep = room < cardW * 0.16 ? cardW * 0.08 : room / (window - 1); // far cards compress into slivers
        final step = nearGap; // drag sensitivity

        final visible = <int>[];
        for (int i = 0; i < widget.items.length; i++) {
          if ((i - _position).abs() <= window) visible.add(i);
        }
        // Paint far-to-near so the centered card ends up on top.
        visible.sort((a, b) => (b - _position).abs().compareTo((a - _position).abs()));

        final flow = GestureDetector(
          onHorizontalDragUpdate: (d) {
            _snap.stop();
            setState(() => _position = (_position - d.delta.dx / step).clamp(0.0, _last.toDouble()));
          },
          onHorizontalDragEnd: (d) => _onEnd(d.primaryVelocity ?? 0),
          child: Column(
            children: [
              const Spacer(),
              SizedBox(
                height: band,
                child: ClipRect(
                  child: SizedBox.expand(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // The centre card's face, without its reflection.
                        IgnorePointer(child: SizedBox(key: _slot, width: cardW, height: cardH)),
                        for (final i in visible) _card(i, cardW, cardH, nearGap, farStep),
                        if (portrait) Positioned(left: 0, right: 0, bottom: gap * 0.35, child: _label()),
                      ],
                    ),
                  ),
                ),
              ),
              if (!portrait) ...[
                const SizedBox(height: 8),
                _label(),
                const SizedBox(height: 20),
              ],
              const Spacer(),
            ],
          ),
        );
        final focus = Actions(
          actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _openCentre())},
          // One focus stop for the flow; the ring goes round the centre card.
          child: DpadFocusRect(target: _slot, shape: widget.focusShape, child: Focus(autofocus: true, onKeyEvent: _onKey, child: flow)),
        );
        final wrap = widget.items.isEmpty ? null : widget.items[_position.round().clamp(0, _last)].wrapFocus;
        return wrap?.call(focus) ?? focus;
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
      child: ExcludeFocus(child: _cardWithReflection(cardW, cardH, widget.items[i].face, dim: 1 - opacity)),
    );

    // Horizontal placement kept separate from the perspective tilt/scale so the
    // math stays predictable. Down by half the reflection: the face is what
    // sits in the middle.
    return Transform.translate(
      offset: Offset(x, (2 + cardH * 0.42) / 2),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012) // perspective
          ..rotateY(rot)
          ..scaleByDouble(scale, scale, scale, 1.0),
        // The reflection may hang past the bottom, where the flow clips it.
        child: OverflowBox(maxHeight: double.infinity, child: card),
      ),
    );
  }

  /// The far cards fade by [dim] towards black, not towards transparent: a
  /// see-through card showed the titles of the ones behind it.
  Widget _cardWithReflection(double w, double h, Widget face, {required double dim}) {
    if (dim > 0) face = DecoratedBox(position: DecorationPosition.foreground, decoration: BoxDecoration(color: Colors.black.withValues(alpha: dim)), child: face);
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
