import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/screens/m3u_screen.dart';
import 'package:retro_toolbox/screens/menu_grid_screen.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/screens/sport_games_grid_screen.dart';
import 'package:retro_toolbox/screens/sports_grid_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/backdrop/backdrop.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _nav = GlobalKey<NavigatorState>();

Future<void> pump(WidgetTester t, Widget home, {CardStyle cards = CardStyle.classic}) async {
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(ProviderScope(
    overrides: [patchersProvider.overrideWith((ref) async => [])],
    child: MaterialApp(navigatorKey: _nav, theme: appTheme(cards), home: home),
  ));
  await t.pump(const Duration(milliseconds: 300));
}

/// The page's [scaffold] sits on one Backdrop and paints no ground of its own.
void expectBackdropBehind(WidgetTester t, Finder scaffold) {
  expect(find.ancestor(of: scaffold, matching: find.byType(Backdrop)), findsOneWidget);
  final ground = t.widget<Material>(find.descendant(of: scaffold, matching: find.byType(Material)).first);
  expect(ground.color, Colors.transparent);
}

void main() {
  final screens = <String, Widget Function()>{
    'MenuScreen': () => const MenuScreen(),
    'ConsoleGridScreen': () => const ConsoleGridScreen(),
    'MenuGridScreen': () => const MenuGridScreen(title: 'Tools', tiles: []),
    'SportsGridScreen': () => const SportsGridScreen(),
    'SportGamesGridScreen': () => const SportGamesGridScreen(sport: 'soccer'),
    // It had none before every page got one.
    'HomeScreen (the game list)': () => const HomeScreen(),
  };
  for (final MapEntry(key: name, value: build) in screens.entries) {
    testWidgets('$name has the backdrop, once', (t) async {
      await pump(t, build());
      expect(find.byType(Backdrop), findsOneWidget);
      expectBackdropBehind(t, find.byType(Scaffold).first);
    });
  }

  testWidgets('a pushed tool page has a backdrop of its own', (t) async {
    await pump(t, const MenuGridScreen(title: 'Tools', tiles: []));
    _nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const M3uScreen()));
    await t.pumpAndSettle();
    expectBackdropBehind(t, find.descendant(of: find.byType(M3uScreen), matching: find.byType(Scaffold)).first);
  });

  testWidgets('dialogs and sheets are not pages: no backdrop of their own', (t) async {
    await pump(t, const MenuGridScreen(title: 'Tools', tiles: []));
    showDialog<void>(context: _nav.currentContext!, builder: (_) => const AlertDialog(content: Text('dialog')));
    await t.pumpAndSettle();
    expect(find.ancestor(of: find.text('dialog'), matching: find.byType(Backdrop)), findsNothing);
    _nav.currentState!.pop();
    await t.pumpAndSettle();
    showModalBottomSheet<void>(context: _nav.currentContext!, builder: (_) => const Text('sheet'));
    await t.pumpAndSettle();
    expect(find.ancestor(of: find.text('sheet'), matching: find.byType(Backdrop)), findsNothing);
    expect(find.byType(Backdrop), findsOneWidget);
  });

  testWidgets('each card style shows its own backdrop', (t) async {
    for (final cards in CardStyle.values) {
      await pump(t, const MenuGridScreen(title: 'Tools', tiles: []), cards: cards);
      await t.pumpAndSettle();
      expect(t.widget<Backdrop>(find.byType(Backdrop)).style, StyleTokens.forStyle(cards).backdrop, reason: cards.name);
    }
    expect(find.byKey(const ValueKey('backdrop-flat')), findsOneWidget);
  });

  testWidgets('Classic draws its dots', (t) async {
    await pump(t, const MenuGridScreen(title: 'Tools', tiles: []));
    expect(find.byKey(const ValueKey('backdrop-dots')), findsOneWidget);
  });

  testWidgets('the app follows the style provider: own backdrop, then the picked one', (t) async {
    SharedPreferences.setMockInitialValues({'setup_wizard_seen': true});
    final c = ProviderContainer(overrides: [patchersProvider.overrideWith((ref) async => [])]);
    addTearDown(c.dispose);
    await t.runAsync(() => c.read(styleProvider.notifier).loaded);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const RetroToolboxApp()));
    await t.pump();
    BackdropStyle shown() => t.widget<Backdrop>(find.byType(Backdrop)).style;
    expect(shown(), StyleTokens.classic.backdrop);
    await t.runAsync(() => c.read(styleProvider.notifier).setCards(CardStyle.switchStyle));
    await t.pumpAndSettle();
    expect(shown(), StyleTokens.switchStyle.backdrop);
    await t.runAsync(() => c.read(styleProvider.notifier).setBackdrop(const BackdropStyle(kind: BackdropKind.drift)));
    // Drift never settles: one frame starts the theme's change, the next ends it.
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(shown(), const BackdropStyle(kind: BackdropKind.drift));
    expect(find.byKey(const ValueKey('backdrop-drift')), findsOneWidget);
  });
}
