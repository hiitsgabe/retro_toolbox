import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog() : super(const CatalogState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _DirSettings extends _FakeSettings {
  _DirSettings(this.dir);
  final String dir;
  @override
  String getDownloadDir(String? consoleId) => dir;
}

void main() {
  Set<GameAction> completedActions(String outputPath) {
    final c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => _FakeCatalog()),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
    ]);
    addTearDown(c.dispose);
    const game = Game(title: 'net', url: 'https://manual/net-1.task', size: 0, consoleId: 'manual');
    final games = c.read(gameStateManagerProvider.notifier);
    games.registerTransientGame(game, isTransfer: true, outputPath: outputPath);
    games.updateExtractionState(game.gameId, ExtractionStatus.completed, 1);
    final s = c.read(gameStateManagerProvider)[game.gameId]!;
    expect(s.status, GameStatus.downloaded);
    expect(s.outputPath, outputPath);
    return s.availableActions;
  }

  test('a finished transfer of an archive offers Extract', () {
    expect(completedActions('/x/a.zip'), {GameAction.extract});
  });

  test('a finished transfer of anything else offers nothing', () {
    expect(completedActions('/x/a.bin'), isEmpty);
  });

  test('a finished .rar offers Extract only when this build can extract rar', () {
    final saved = GameStateManager.rarSupported;
    addTearDown(() => GameStateManager.rarSupported = saved);
    GameStateManager.rarSupported = () => false;
    expect(completedActions('/x/a.rar'), isEmpty);
    GameStateManager.rarSupported = () => true;
    expect(completedActions('/x/a.rar'), {GameAction.extract});
  });

  test('a handler warning stays on the game after it resolves', () async {
    final dir = Directory.systemTemp.createTempSync('rt_note');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/game.cue').writeAsStringSync('c');
    final c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => _FakeCatalog()),
      settingsProvider.overrideWith((ref) => _DirSettings(dir.path)),
    ]);
    addTearDown(c.dispose);
    const game = Game(title: 'game.zip', url: 'https://h/game.zip', size: 1, consoleId: 'c');
    final games = c.read(gameStateManagerProvider.notifier);
    games.registerTransientGame(game);

    const note = 'Skipped Convert to CHD: chdman not found. Files kept.';
    games.updateExtractionState(game.gameId, ExtractionStatus.completed, 1, error: note);
    for (var i = 0; i < 100 && c.read(gameStateManagerProvider)[game.gameId]!.status == GameStatus.loading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    final s = c.read(gameStateManagerProvider)[game.gameId]!;
    expect(s.status, isNot(GameStatus.loading));
    expect(s.errorMessage, note);
  });
}
