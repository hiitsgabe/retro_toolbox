import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/theme/device_class.dart';

/// Builds one face's image: [fallback] stands in while it loads and when it
/// fails (the details page's image builder, cut down).
typedef BoxFaceBuilder = Widget Function(BuildContext context, String url, Widget fallback);

/// The game's box: front and back. A turnable 3D box where the device has
/// the power for it, the two covers side by side on the framebuffer
/// handheld ([DeviceClass.pixel]).
class GameBoxView extends StatelessWidget {
  const GameBoxView({
    super.key,
    this.front,
    this.back,
    required this.face,
    this.onOpen,
    this.height = 300,
    this.aspect,
  });

  final String? front, back;
  final BoxFaceBuilder face;

  /// Tap (or A) on a face opens it; null: not tappable.
  final ValueChanged<String>? onOpen;
  final double height;

  /// Width over height of the box. Null: read from the front cover once it
  /// is in, 0.7 until then.
  final double? aspect;

  @override
  Widget build(BuildContext context) {
    final first = front ?? back;
    if (first == null) return const SizedBox.shrink();
    // Whole on screen, under the app bar and over the action bar.
    final height = math.min(this.height, MediaQuery.sizeOf(context).height * 0.42);
    final turns = DeviceClass.of(context) != DeviceClass.pixel && front != null && back != null;
    return _AspectOf(
      url: first,
      known: aspect,
      builder: (aspect) => turns
          ? GameBox3D(front: front!, back: back!, face: face, onOpen: onOpen, height: height, aspect: aspect)
          : _Flat(front: front, back: back, face: face, onOpen: onOpen, height: height, aspect: aspect),
    );
  }
}

/// Front and back side by side, each a focus stop that opens it.
class _Flat extends StatelessWidget {
  const _Flat({required this.front, required this.back, required this.face, required this.onOpen, required this.height, required this.aspect});

  final String? front, back;
  final BoxFaceBuilder face;
  final ValueChanged<String>? onOpen;
  final double height;
  final double aspect;

  @override
  Widget build(BuildContext context) {
    Widget cover(String url) {
      final art = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: height * aspect, height: height, child: face(context, url, _Blank(height: height, width: height * aspect))),
      );
      return onOpen == null ? art : InkWell(borderRadius: BorderRadius.circular(6), onTap: () => onOpen!(url), child: art);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(spacing: 16, runSpacing: 16, children: [
        if (front != null) cover(front!),
        if (back != null) cover(back!),
      ]),
    );
  }
}

/// The box in 3D: front, spine and back, turned about its upright axis.
/// Drag turns it; with focus, left and right turn it to the next face and A
/// opens the one facing the screen.
class GameBox3D extends StatefulWidget {
  const GameBox3D({
    super.key,
    required this.front,
    required this.back,
    required this.face,
    this.onOpen,
    this.height = 300,
    this.aspect = 0.7,
  });

  final String front, back;
  final BoxFaceBuilder face;
  final ValueChanged<String>? onOpen;
  final double height;
  final double aspect;

  /// The spine's width over the box's: a DVD case is about 14 by 135 mm.
  static const depth = 0.11;

  /// The angle it opens at: a three-quarter view, the spine showing.
  static const rest = -0.38;

  @override
  State<GameBox3D> createState() => GameBox3DState();
}

@visibleForTesting
class GameBox3DState extends State<GameBox3D> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController.unbounded(vsync: this, value: GameBox3D.rest);

  /// The turn, in radians: 0 is the front facing the screen, pi the back.
  double get angle => _turn.value;

  /// The face turned to the screen the most: the one A and a tap open.
  bool get showingBack => math.cos(angle) < 0;

  void _turnTo(double target) => _turn.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);

  /// Left and right go a quarter turn at a time, ending on a face or a spine.
  void _step(int direction) {
    final quarter = math.pi / 2;
    _turnTo(((angle / quarter).round() + direction) * quarter);
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _open() => widget.onOpen?.call(showingBack ? widget.back : widget.front);

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final w = h * widget.aspect;
    final d = w * GameBox3D.depth;
    return Align(
      alignment: Alignment.centerLeft,
      child: Actions(
        actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _open())},
        child: Focus(
          onKeyEvent: _onKey,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen == null ? null : _open,
            onHorizontalDragStart: (_) => _turn.stop(),
            onHorizontalDragUpdate: (e) => _turn.value += e.delta.dx / w * math.pi * 0.6,
            // Let go: it settles on the nearest face or spine, carried by the flick.
            onHorizontalDragEnd: (e) {
              final quarter = math.pi / 2;
              final flick = e.primaryVelocity == null ? 0.0 : e.primaryVelocity! / w * 0.15;
              _turnTo(((angle + flick) / quarter).round() * quarter);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                // Room for the box turned to its widest, the diagonal.
                width: math.sqrt(w * w + d * d) * 1.08,
                height: h * 1.08,
                child: AnimatedBuilder(
                  animation: _turn,
                  builder: (context, _) => Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: _faces(context, w, h, d)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The faces turned toward the screen, the far one first. A box is convex,
  /// so the faces that show never overlap and need no depth test.
  List<Widget> _faces(BuildContext context, double w, double h, double d) {
    final spine = Color.lerp(Theme.of(context).colorScheme.surfaceContainerHighest, Colors.black, 0.55)!;
    final faces = <(double normal, double width, double distance, Widget child)>[
      (0, w, d / 2, widget.face(context, widget.front, _Blank(height: h, width: w))),
      (math.pi, w, d / 2, widget.face(context, widget.back, _Blank(height: h, width: w))),
      (math.pi / 2, d, w / 2, _Spine(color: spine)),
      (-math.pi / 2, d, w / 2, _Spine(color: spine)),
    ];
    final shown = [
      for (final f in faces)
        if (math.cos(angle + f.$1) > 0.001) f,
    ]..sort((a, b) => math.cos(angle + a.$1).compareTo(math.cos(angle + b.$1)));
    return [
      for (final (normal, width, distance, child) in shown)
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle + normal)
            ..translateByDouble(0, 0, -distance, 1),
          child: SizedBox(
            width: width,
            height: h,
            // Darker as it turns away from the screen: the only light is in front.
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: (1 - math.cos(angle + normal)).clamp(0.0, 1.0) * 0.45), BlendMode.srcATop),
              child: ClipRRect(borderRadius: BorderRadius.circular(2), child: child),
            ),
          ),
        ),
    ];
  }
}

class _Spine extends StatelessWidget {
  const _Spine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.white, 0.12)!, color]),
      ),
    );
  }
}

class _Blank extends StatelessWidget {
  const _Blank({required this.height, this.width});

  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width ?? height * 0.7,
      height: height,
      color: scheme.surfaceContainerHigh,
      child: Icon(Icons.image_not_supported_outlined, size: math.min(48, height * 0.3), color: scheme.outline),
    );
  }
}

/// Builds with the width over height of the image at [url] once it is in
/// (0.7 until then), or with [known] right away.
class _AspectOf extends StatefulWidget {
  const _AspectOf({required this.url, required this.known, required this.builder});

  final String url;
  final double? known;
  final Widget Function(double aspect) builder;

  @override
  State<_AspectOf> createState() => _AspectOfState();
}

class _AspectOfState extends State<_AspectOf> {
  double _aspect = 0.7;
  ImageStream? _stream;
  late final _listener = ImageStreamListener((info, _) {
    final a = info.image.width / info.image.height;
    // A strip or a sliver is a bad scan, not a box.
    if (mounted && a.isFinite && a > 0.4 && a < 2.2) setState(() => _aspect = a);
  }, onError: (_, __) {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.known != null || _stream != null) return;
    // Small: only the size is wanted, and the face decodes its own copy.
    _stream = ResizeImage(CachedNetworkImageProvider(widget.url), width: 64, policy: ResizeImagePolicy.fit).resolve(createLocalImageConfiguration(context))
      ..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(widget.known ?? _aspect);
}
