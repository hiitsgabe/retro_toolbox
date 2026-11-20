import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A 16 by 16 one-colour bitmap: 16 rows of 16 characters, `#` is ink and
/// `.` is clear. The set is [PixelIcons].
@immutable
class PixelGlyph {
  const PixelGlyph(this.rows);

  final List<String> rows;

  static const size = 16;

  bool isSet(int col, int row) => rows[row].codeUnitAt(col) == 0x23;
}

/// Paints a [PixelGlyph] with hard edges in the IconTheme colour. Each glyph
/// pixel is a whole number of device pixels, so the art stays crisp at any
/// size; the glyph sits centred in a box of [size].
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.glyph, {super.key, this.size, this.color, this.semanticLabel});

  final PixelGlyph glyph;

  /// Null: the IconTheme size.
  final double? size;

  /// Null: the IconTheme colour.
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final ink = color ?? theme.color ?? const Color(0xFF000000);
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel == null,
      child: SizedBox.square(dimension: side, child: CustomPaint(painter: PixelGlyphPainter(glyph, ink, dpr))),
    );
  }
}

class PixelGlyphPainter extends CustomPainter {
  PixelGlyphPainter(this.glyph, this.color, this.devicePixelRatio);

  final PixelGlyph glyph;
  final Color color;
  final double devicePixelRatio;

  /// The glyph as one path, a rect per run of ink in a row, in a box of
  /// [size]: glyph pixels snapped to whole device pixels (one at least), the
  /// glyph centred on a device pixel edge.
  static Path pathFor(PixelGlyph glyph, Size size, double devicePixelRatio) {
    final device = math.max(1, (size.shortestSide * devicePixelRatio / PixelGlyph.size).floor());
    final cell = device / devicePixelRatio;
    final side = cell * PixelGlyph.size;
    double snap(double v) => (v * devicePixelRatio).roundToDouble() / devicePixelRatio;
    final left = snap((size.width - side) / 2), top = snap((size.height - side) / 2);
    final path = Path();
    for (var r = 0; r < PixelGlyph.size; r++) {
      var c = 0;
      while (c < PixelGlyph.size) {
        if (!glyph.isSet(c, r)) {
          c++;
          continue;
        }
        final start = c;
        while (c < PixelGlyph.size && glyph.isSet(c, r)) {
          c++;
        }
        path.addRect(Rect.fromLTWH(left + start * cell, top + r * cell, (c - start) * cell, cell));
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    // No anti-aliasing: edges land on device pixels, a soft edge would blur.
    canvas.drawPath(
      pathFor(glyph, size, devicePixelRatio),
      Paint()
        ..color = color
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(PixelGlyphPainter old) => old.glyph != glyph || old.color != color || old.devicePixelRatio != devicePixelRatio;
}
