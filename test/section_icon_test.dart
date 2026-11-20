import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';

void main() {
  for (final style in CardStyle.values) {
    testWidgets('${style.name}: a section icon is ${style == CardStyle.classic ? 'the pixel one' : 'the line one'}', (t) async {
      await t.pumpWidget(MaterialApp(theme: appTheme(style), home: const Center(child: SectionIcon(SettingsSection.keys, color: Color(0xFF123456)))));
      final pixel = style == CardStyle.classic;
      expect(find.byType(PixelIcon), pixel ? findsOneWidget : findsNothing);
      expect(find.byType(SettingsIcon), pixel ? findsNothing : findsOneWidget);
      if (pixel) {
        final icon = t.widget<PixelIcon>(find.byType(PixelIcon));
        expect((icon.glyph, icon.color), (SettingsSection.keys.pixel, const Color(0xFF123456)));
      } else {
        expect(t.widget<SettingsIcon>(find.byType(SettingsIcon)).paths, SettingsSection.keys.icon);
      }
    });
  }
}
