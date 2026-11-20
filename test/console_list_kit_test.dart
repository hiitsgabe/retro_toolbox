import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kit/kit_support.dart';
import 'screenshots/fakes.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the console list is a kit screen: its name and how many consoles', (t) async {
    await pumpKit(t, const ConsoleGridScreen(), overrides: consolesOverrides());
    expect(find.byType(KitScaffold), findsOneWidget);
    expect(find.text('GAMES LIBRARY'), findsOneWidget);
    expect(find.text('${consoles.length} consoles'), findsOneWidget);
  });

  // Every console is a Games tile, so every cartridge label was the Games red.
  testWidgets('Classic: the cartridges take the area palette in turn, no two neighbours alike', (t) async {
    await pumpKit(t, const ConsoleGridScreen(), device: linux640, overrides: consolesOverrides());
    await t.pump(const Duration(milliseconds: 100));
    final labels = find.byKey(const ValueKey('cartridge-label'));
    final colours = [for (final e in labels.evaluate()) ((e.widget as DecoratedBox).decoration as BoxDecoration).color!];
    expect(colours.length, greaterThanOrEqualTo(6));
    expect(colours.toSet().length, greaterThan(3));
    for (var i = 1; i < colours.length; i++) {
      expect(colours[i], isNot(colours[i - 1]), reason: 'cartridge $i');
    }
    expect(StyleTokens.areaPalette.values, containsAll(colours.toSet()));
  });

  testWidgets('no consoles: one line and Open Settings', (t) async {
    await pumpKit(t, const ConsoleGridScreen(), overrides: [appStateProvider.overrideWith((ref) => FakeApp(const AppState()))]);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });
}
