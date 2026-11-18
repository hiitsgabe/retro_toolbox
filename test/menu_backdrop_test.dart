import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/screens/menu_grid_screen.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/screens/sport_games_grid_screen.dart';
import 'package:retro_toolbox/screens/sports_grid_screen.dart';
import 'package:retro_toolbox/widgets/backdrop/backdrop.dart';
import 'package:retro_toolbox/widgets/backdrop/menu_backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pump(WidgetTester t, Widget home, {List<Override> overrides = const []}) async {
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: [patchersProvider.overrideWith((ref) async => []), ...overrides],
    child: MaterialApp(home: home),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

void expectBackdropBehind(WidgetTester t) {
  expect(find.byType(Backdrop), findsOneWidget);
  final scaffold = t.widget<Scaffold>(find.descendant(of: find.byType(Backdrop), matching: find.byType(Scaffold)).first);
  expect(scaffold.backgroundColor, MenuBackdrop.scaffoldColor);
}

void main() {
  testWidgets('MenuScreen has the Style backdrop', (t) async {
    await pump(t, const MenuScreen());
    expectBackdropBehind(t);
  });

  testWidgets('ConsoleGridScreen has the Style backdrop', (t) async {
    await pump(t, const ConsoleGridScreen());
    expectBackdropBehind(t);
  });

  testWidgets('MenuGridScreen has the Style backdrop', (t) async {
    await pump(t, const MenuGridScreen(title: 'Tools', tiles: []));
    expectBackdropBehind(t);
  });

  testWidgets('SportsGridScreen has the Style backdrop', (t) async {
    await pump(t, const SportsGridScreen());
    expectBackdropBehind(t);
  });

  testWidgets('SportGamesGridScreen has the Style backdrop', (t) async {
    await pump(t, const SportGamesGridScreen(sport: 'soccer'));
    expectBackdropBehind(t);
  });

  testWidgets('the backdrop follows the style provider', (t) async {
    await pump(t, const MenuGridScreen(title: 'Tools', tiles: []));
    final c = ProviderScope.containerOf(t.element(find.byType(MenuGridScreen)));
    await c.read(styleProvider.notifier).setBackdrop(const BackdropStyle(kind: BackdropKind.drift));
    await t.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('backdrop-drift')), findsOneWidget);
    await c.read(styleProvider.notifier).setBackdrop(const BackdropStyle());
    await t.pump(const Duration(milliseconds: 1));
  });

  testWidgets('the game list has no backdrop', (t) async {
    await pump(t, const HomeScreen());
    expect(find.byType(Backdrop), findsNothing);
  });
}
