import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_list.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_grid/game_cover_flow.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_list.dart';
import 'package:retro_toolbox/widgets/game_list/game_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screenshots/fakes.dart';

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  String getDownloadDir(String? consoleId) => '/downloads';
  @override
  Future<void> get loaded => Future.value();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Counts the Classic toggle's view mode changes.
class _App extends FakeApp {
  _App(super.state);
  int toggles = 0;
  @override
  void toggleViewMode() => toggles++;
}

void main() {
  final games = snesGames();
  late ProviderContainer c;
  late _App app;

  /// The games screen in [cards] with [layout], under the app theme of the
  /// style as the app has it; games[1] is selected.
  Future<void> pump(WidgetTester t, CardStyle cards, GameLayout layout) async {
    SharedPreferences.setMockInitialValues({});
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final overrides = gamesOverrides(games, selected: {games[1].gameId});
    c = ProviderContainer(overrides: [
      // In place of the fakes' own app state, which comes first.
      appStateProvider.overrideWith((ref) => app = _App(AppState(consoles: {for (final c in consoles) c.id: c}, selectedConsole: consoles.first))),
      ...overrides.skip(1),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
    ]);
    addTearDown(c.dispose);
    await c.read(styleProvider.notifier).loaded;
    await c.read(styleProvider.notifier).setCards(cards);
    await c.read(styleProvider.notifier).setGameLayout(layout);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          navigatorKey: nav,
          theme: appTheme(ref.watch(styleProvider).cards),
          builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
          home: const HomeScreen(),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  Finder card(int i) => find.byWidgetPredicate((w) => w is GameGridItem && w.game.gameId == games[i].gameId);
  final marks = [for (final m in SelectedMarker.values) 'selected-${m.name}'];

  testWidgets("Vita with the grid layout: Classic's grid, the game marked the Vita way", (t) async {
    await pump(t, CardStyle.vita, GameLayout.grid);
    expect(find.byType(GameGrid), findsOneWidget);
    expect(find.byType(StyledGameList), findsNothing);
    final own = 'selected-${StyleTokens.vita.selected.marker.name}';
    expect(find.descendant(of: card(1), matching: find.byKey(ValueKey(own))), findsOneWidget);
    expect(find.descendant(of: card(0), matching: find.byKey(ValueKey(own))), findsNothing, reason: 'not selected');
    for (final other in marks.where((m) => m != own)) {
      expect(find.byKey(ValueKey(other)), findsNothing, reason: other);
    }
  });

  testWidgets("3DS with the list layout: Classic's list, the selected row marked the 3DS way", (t) async {
    await pump(t, CardStyle.threeDs, GameLayout.list);
    expect(find.byType(GameList), findsOneWidget);
    expect(find.byType(StyledGameList), findsNothing);
    Finder row(int i) => find.byWidgetPredicate((w) => w is GameRow && w.game.gameId == games[i].gameId);
    final own = 'selected-${StyleTokens.threeDs.selected.marker.name}';
    expect(find.descendant(of: row(1), matching: find.byKey(ValueKey(own))), findsOneWidget);
    expect(find.descendant(of: row(0), matching: find.byKey(ValueKey(own))), findsNothing, reason: 'not selected');
    for (final other in marks.where((m) => m != own)) {
      expect(find.byKey(ValueKey(other)), findsNothing, reason: other);
    }
  });

  testWidgets("Vita with the style default: its own layout, and no toggle", (t) async {
    await pump(t, CardStyle.vita, GameLayout.styleDefault);
    expect(find.byType(StyledGameList), findsOneWidget);
    expect(find.byType(GameGrid), findsNothing);
    expect(find.byTooltip('Change view'), findsNothing);
  });

  testWidgets('outside Classic the header toggle shows and moves the layout on', (t) async {
    await pump(t, CardStyle.switchStyle, GameLayout.grid);
    expect(find.byTooltip('Change view'), findsOneWidget);
    for (final (layout, view) in [
      (GameLayout.list, GameList),
      (GameLayout.coverFlow, GameCoverFlow),
      (GameLayout.grid, GameGrid),
    ]) {
      await t.tap(find.byTooltip('Change view'));
      await t.pump(const Duration(milliseconds: 300));
      expect(c.read(styleProvider).gameLayout, layout);
      expect(find.byType(view), findsOneWidget, reason: layout.name);
      final prefs = await SharedPreferences.getInstance();
      expect(AppStyle.fromJson(jsonDecodeMap(prefs.getString('app_style')!)).gameLayout, layout, reason: 'stored');
    }
    expect(app.toggles, 0, reason: "Classic's own view mode stays");
  });

  testWidgets("Classic with the style default: the toggle is Classic's own view mode", (t) async {
    await pump(t, CardStyle.classic, GameLayout.styleDefault);
    expect(find.byType(GameGrid), findsOneWidget);
    await t.tap(find.byTooltip('Change view'));
    await t.pump();
    expect(app.toggles, 1);
    expect(c.read(styleProvider).gameLayout, GameLayout.styleDefault);
  });
}
