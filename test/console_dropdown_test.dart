import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/header/console_dropdown.dart';

void main() {
  const snes = Console(id: 'snes', name: 'Super Nintendo', urls: [], gameFilesFormat: ['.sfc']);

  for (final style in [CardStyle.classic, CardStyle.vita]) {
    testWidgets('${style.name}: the console name is in the style\'s title face, not the platform default', (t) async {
      // DropdownButton does not merge its style with the text around it: a
      // style with no family falls to the platform font (boxes in tests).
      await t.pumpWidget(MaterialApp(
        theme: appTheme(style),
        home: Scaffold(body: ConsoleDropdown(consoles: const [snes], selectedConsole: snes, onConsoleSelect: (_) {})),
      ));
      final text = find.text('Super Nintendo').first;
      final shown = DefaultTextStyle.of(t.element(text)).style.merge(t.widget<Text>(text).style);
      expect(shown.fontFamily, StyleTokens.forStyle(style).titleFont);
    });
  }
}
