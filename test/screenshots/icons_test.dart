import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

import 'support.dart';

/// Every pixel icon at 48 px on a label, as a cartridge shows it, for review.
class _Sheet extends StatelessWidget {
  const _Sheet();

  @override
  Widget build(BuildContext context) {
    const k = StyleTokens.classic;
    final areas = AppArea.values;
    var i = 0;
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final MapEntry(key: name, value: glyph) in PixelIcons.all.entries)
              SizedBox(
                width: 76,
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: k.area(areas[i++ % areas.length]), borderRadius: BorderRadius.circular(3)),
                    child: PixelIcon(glyph, size: 48, color: k.surface),
                  ),
                  const SizedBox(height: 4),
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}

void main() {
  screenshotSetUp();

  testWidgets('pixel icon sheet', (t) async {
    await launch(t, const _Sheet());
    // Wider than any device, so the whole set fits in one picture.
    t.view.physicalSize = const Size(980, 470) * t.view.devicePixelRatio;
    await frames(t);
    await snap(t, 'pixel_icons');
  }, skip: !screenshotsEnabled);
}
