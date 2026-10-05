import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/footer/footer.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp() : super(const AppState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  String getDownloadDir(String? consoleId) => '/downloads';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  _FakeGames([super.state = const {}]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('d-pad reaches the footer, A opens the task manager, B closes it', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => _FakeApp()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(
          body: Column(children: [
            Expanded(child: Center(child: ElevatedButton(autofocus: true, onPressed: () {}, child: const Text('above')))),
            const Footer(),
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();

    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(TaskPanelModal), findsOneWidget);

    // The current tab (Downloads) holds focus.
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(find.descendant(of: find.byWidget(focused.widget), matching: find.text('Downloads')), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(TaskPanelModal), findsNothing);
  });

  testWidgets('a running network transfer counts as downloading in the footer, not extracting', (t) async {
    GameState st(String n, bool transfer) =>
        GameState(game: Game(title: n, url: 'https://x/$n.bin', size: 0, consoleId: 'manual'), status: GameStatus.extracting, isTransfer: transfer);
    final net = st('net', true);
    await t.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        appStateProvider.overrideWith((ref) => _FakeApp()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames({net.game.gameId: net})),
      ],
      child: const MaterialApp(home: Scaffold(body: Footer())),
    ));
    await t.pump();
    expect(find.text('Downloading 1'), findsOneWidget);

    final conv = st('conv', false);
    await t.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        appStateProvider.overrideWith((ref) => _FakeApp()),
        catalogProvider.overrideWith((ref) => _FakeCatalog()),
        settingsProvider.overrideWith((ref) => _FakeSettings()),
        gameStateManagerProvider.overrideWith((ref) => _FakeGames({net.game.gameId: net, conv.game.gameId: conv})),
      ],
      child: const MaterialApp(home: Scaffold(body: Footer())),
    ));
    await t.pump();
    expect(find.text('Downloading 1 • Extracting 1'), findsOneWidget);
  });
}
