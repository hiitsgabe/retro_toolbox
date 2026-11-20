import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  test('a style with area accents takes the area colour, with ink that reads on it', () {
    final games = StyleTokens.classic.inArea(AppArea.games);
    expect(games.accent, StyleTokens.areaPalette[AppArea.games]);
    expect(games.onAccent, const Color(0xFFFFFFFF));
    final saves = StyleTokens.classic.inArea(AppArea.saves);
    expect(saves.accent, StyleTokens.areaPalette[AppArea.saves]);
    expect(saves.onAccent.computeLuminance(), lessThan(0.05));
    expect(StyleTokens.classic.inArea(null), same(StyleTokens.classic));
  });

  test('the other styles keep their own accent in every area', () {
    for (final k in [StyleTokens.vita, StyleTokens.threeDs, StyleTokens.wii, StyleTokens.switchStyle]) {
      for (final a in AppArea.values) {
        expect(k.inArea(a), same(k));
      }
    }
  });

  testWidgets('KitArea rethemes what is under it and keeps the text theme (the text floor)', (t) async {
    late ThemeData outer, inner;
    await pumpKit(
      t,
      Builder(builder: (context) {
        outer = Theme.of(context);
        return KitArea(area: AppArea.saves, child: Builder(builder: (context) {
          inner = Theme.of(context);
          return const SizedBox();
        }));
      }),
      style: CardStyle.classic,
      device: linux640,
    );
    expect(inner.colorScheme.primary, StyleTokens.areaPalette[AppArea.saves]);
    expect(StyleTokens.of(t.element(find.byType(SizedBox).last)).accent, StyleTokens.areaPalette[AppArea.saves]);
    expect(inner.textTheme, outer.textTheme);
    expect(inner.textTheme.labelSmall!.fontSize, greaterThanOrEqualTo(13));
  });

  testWidgets('the type scale never goes under the 640x480 floor', (t) async {
    late KitType type;
    await pumpKit(t, Builder(builder: (context) {
      type = KitType.of(context);
      return const SizedBox();
    }), device: linux640);
    for (final s in [type.title, type.subtitle, type.row, type.body, type.label, type.verb, type.mono(11)]) {
      expect(s.fontSize, greaterThanOrEqualTo(13));
    }
  });

  testWidgets('a panel draws a line between its rows, not after the last', (t) async {
    await pumpKit(t, const Scaffold(body: KitPanel(children: [Text('a'), Text('b'), Text('c')])));
    expect(find.byType(Divider), findsNWidgets(2));
  });
}
