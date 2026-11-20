import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

final _full = PixelGlyph(List.filled(16, '#' * 16));

void main() {
  test('every glyph is 16 rows of 16 pixels, and no two are the same', () {
    for (final MapEntry(:key, :value) in PixelIcons.all.entries) {
      expect(value.rows, hasLength(16), reason: key);
      for (final row in value.rows) {
        expect(row, matches(RegExp(r'^[#.]{16}$')), reason: key);
      }
    }
    final drawings = PixelIcons.all.values.map((g) => g.rows.join()).toSet();
    expect(drawings, hasLength(PixelIcons.all.length));
  });

  test('the painted shape covers exactly the set pixels of every glyph', () {
    for (final MapEntry(:key, :value) in PixelIcons.all.entries) {
      final path = PixelGlyphPainter.pathFor(value, const Size(48, 48), 2.625);
      final box = PixelGlyphPainter.pathFor(_full, const Size(48, 48), 2.625).getBounds();
      final cell = box.width / 16;
      final origin = box.topLeft;
      for (var r = 0; r < 16; r++) {
        for (var c = 0; c < 16; c++) {
          final centre = origin + Offset((c + 0.5) * cell, (r + 0.5) * cell);
          expect(path.contains(centre), value.rows[r][c] == '#', reason: '$key at ($c, $r)');
        }
      }
    }
  });

  test('a glyph pixel is a whole number of device pixels, centred in the box', () {
    // 48 logical px at 2.625 is 126 device px: 7 a glyph pixel, 112 in all.
    // 50 at 2.625 leaves an odd 3.25 device px round the glyph: the edge snaps.
    final bounds = PixelGlyphPainter.pathFor(_full, const Size(50, 50), 2.625).getBounds();
    final full = PixelGlyphPainter.pathFor(_full, const Size(48, 48), 2.625).getBounds();
    expect(full.width * 2.625, moreOrLessEquals(112, epsilon: 1e-3));
    expect(full.center.dx, moreOrLessEquals(24, epsilon: 1e-3));
    expect(full.center.dy, moreOrLessEquals(24, epsilon: 1e-3));
    expect(bounds.left * 2.625, moreOrLessEquals((bounds.left * 2.625).roundToDouble(), epsilon: 1e-3));
    // Never smaller than a device pixel.
    expect(PixelGlyphPainter.pathFor(_full, const Size(8, 8), 1).getBounds().width, 16);
  });

  testWidgets('paints one hard-edged shape in the IconTheme colour', (t) async {
    await t.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: IconTheme(data: IconThemeData(color: Color(0xFF123456), size: 32), child: PixelIcon(PixelIcons.check)),
      ),
    ));
    final box = t.renderObject<RenderBox>(find.byType(PixelIcon));
    expect(box.size, const Size(32, 32));
    expect(
      find.descendant(of: find.byType(PixelIcon), matching: find.byType(CustomPaint)),
      paints
        ..something((method, args) {
          if (method != #drawPath) return false;
          final paint = args[1] as Paint;
          return paint.color.toARGB32() == 0xFF123456 && !paint.isAntiAlias;
        }),
    );
    expect(find.descendant(of: find.byType(PixelIcon), matching: find.byType(CustomPaint)), paintsExactlyCountTimes(#drawPath, 1));
  });
}
