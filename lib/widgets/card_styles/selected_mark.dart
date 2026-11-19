import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';

/// A game marked for a batch, drawn the way the active style marks it (its
/// [SelectedLook]): over [child], or round it. Nothing extra when not
/// [selected]; the tree under [child] stays the same either way, so toggling
/// does not reload its art.
class SelectedMark extends StatelessWidget {
  const SelectedMark({super.key, required this.selected, required this.child, this.radius = 0, this.circle = false, this.size = 22});

  final bool selected;
  final Widget child;

  /// The card's corner radius; [circle] for a round card (Vita bubbles).
  final double radius;
  final bool circle;

  /// The check badge's side; the other parts scale from it.
  final double size;

  /// Space between a ring drawn round the card and the card.
  static const ringGap = 4.0;

  @override
  Widget build(BuildContext context) {
    final look = StyleTokens.of(context).selected;
    final fold = selected && look.marker == SelectedMarker.foldedCorner ? size * 1.7 : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The 3DS corner folds over: the art loses that corner.
        ClipPath(clipper: _FoldClip(fold), clipBehavior: fold > 0 ? Clip.antiAlias : Clip.none, child: child),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                key: ValueKey('selected-${look.marker.name}'),
                clipBehavior: Clip.none,
                children: _parts(look, fold),
              ),
            ),
          ),
      ],
    );
  }

  BorderRadius get _corners => BorderRadius.circular(circle ? 9999 : radius);

  List<Widget> _parts(SelectedLook look, double fold) {
    final c = look.color;
    switch (look.marker) {
      case SelectedMarker.badgeAndBorder:
        return [
          Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(borderRadius: _corners, border: Border.all(color: c, width: look.border))),
          ),
          _corner(look, inset: look.border + 3, square: true),
        ];
      case SelectedMarker.dashedRing:
        return [
          Positioned.fill(
            left: -ringGap,
            top: -ringGap,
            right: -ringGap,
            bottom: -ringGap,
            child: CustomPaint(painter: _DashedRing(color: c, width: math.max(look.border, 2), circle: circle, radius: radius + ringGap)),
          ),
          // On a circle the corner of the box is off the card: sit on the rim.
          _corner(look, inset: 0, along: circle ? 0.78 : 1),
        ];
      case SelectedMarker.foldedCorner:
        return [
          Positioned(
            top: 0,
            right: 0,
            width: fold,
            height: fold,
            child: CustomPaint(
              painter: _Flap(c),
              child: Align(
                // A half-size check centred on the flap's centroid (a third
                // of the way in from its square corner).
                alignment: const Alignment(-2 / 3, 2 / 3),
                child: _Check(key: const ValueKey('badge-selected'), size: fold * 0.5, color: look.onColor),
              ),
            ),
          ),
        ];
      case SelectedMarker.tintAndPill:
        final pill = size * 0.9;
        return [
          Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(borderRadius: _corners, color: c.withValues(alpha: 0.30)))),
          Positioned(
            left: 0,
            right: 0,
            bottom: -pill / 2,
            child: Center(
              child: Container(
                key: const ValueKey('badge-selected'),
                height: pill,
                width: pill * 2.6,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(pill),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Center(child: _Check(size: pill * 0.8, color: look.onColor)),
              ),
            ),
          ),
        ];
      case SelectedMarker.checkAndBar:
        return [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: _corners,
              child: Align(alignment: Alignment.bottomCenter, child: SizedBox(height: look.bar, width: double.infinity, child: ColoredBox(color: c))),
            ),
          ),
          _corner(look, inset: 6),
        ];
    }
  }

  /// The check badge in the look's corner, [inset] from the edges; [along]
  /// pulls it towards the middle.
  Widget _corner(SelectedLook look, {required double inset, bool square = false, double along = 1}) {
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: Align(
          alignment: Alignment(look.corner.x * along, look.corner.y * along),
          child: Container(
            key: const ValueKey('badge-selected'),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: look.color,
              shape: square ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: square ? BorderRadius.circular(size * 0.25) : null,
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1))],
            ),
            child: Center(child: _Check(size: size * 0.72, color: look.onColor)),
          ),
        ),
      ),
    );
  }
}

/// A bold check mark: the icon font's is too thin at badge sizes.
class _Check extends StatelessWidget {
  const _Check({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _CheckPainter(color));
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawPath(
      Path()
        ..moveTo(s * 0.18, s * 0.52)
        ..lineTo(s * 0.40, s * 0.74)
        ..lineTo(s * 0.82, s * 0.28),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.15
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}

/// Everything on the near side of the fold line, which cuts off the top right
/// corner [fold] along each edge (nothing cut when 0). Reaches past the box
/// so the card's own shadow is kept.
class _FoldClip extends CustomClipper<Path> {
  const _FoldClip(this.fold);

  final double fold;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height, f = fold;
    const m = 24.0;
    if (f <= 0) return Path()..addRect((Offset.zero & size).inflate(m));
    // The line x - y = w - f, met at the top and right of the inflated box.
    return Path()
      ..moveTo(-m, -m)
      ..lineTo(w - f - m, -m)
      ..lineTo(w + m, f + m)
      ..lineTo(w + m, h + m)
      ..lineTo(-m, h + m)
      ..close();
  }

  @override
  bool shouldReclip(_FoldClip old) => old.fold != fold;
}

/// The folded-down corner: the triangle the top right corner makes when
/// folded over its diagonal, lit along the fold, casting a little shadow.
class _Flap extends CustomPainter {
  const _Flap(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final f = size.width;
    final flap = Path()
      ..moveTo(0, 0)
      ..lineTo(f, f)
      ..lineTo(0, f)
      ..close();
    canvas.drawShadow(flap, Colors.black, 3, false);
    final hsl = HSLColor.fromColor(color);
    canvas.drawPath(
      flap,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor(), color],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_Flap old) => old.color != color;
}

/// A dashed stroke round the box: a circle, or a rounded rectangle.
class _DashedRing extends CustomPainter {
  const _DashedRing({required this.color, required this.width, required this.circle, required this.radius});

  final Color color;
  final double width;
  final bool circle;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = circle ? (Path()..addOval(rect)) : (Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
    const dash = 7.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => old.color != color || old.width != width || old.circle != circle || old.radius != radius;
}
