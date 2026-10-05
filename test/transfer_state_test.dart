import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:retro_toolbox/widgets/game_list/game_progress_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _FakeQueue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _FakeQueue(List<QueuedTask> tasks) : super(TaskQueueState(tasks: tasks));
  final enqueued = <(String, TaskType, Map<String, dynamic>)>[];
  @override
  void enqueue(String taskId, TaskType type, Map<String, dynamic> params) => enqueued.add((taskId, type, params));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _game = Game(title: 'net', url: 'https://manual/net-1.task', size: 0, consoleId: 'manual');

void main() {
  late ProviderContainer c;
  late GameStateManager games;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => _FakeCatalog()),
      settingsProvider.overrideWith((ref) => _FakeSettings()),
    ]);
    addTearDown(c.dispose);
    games = c.read(gameStateManagerProvider.notifier);
    games.registerTransientGame(_game, isTransfer: true);
  });
  GameState now() => c.read(gameStateManagerProvider)[_game.gameId]!;

  test('queued and running transfers read as downloads', () {
    games.updateQueueState(_game.gameId, TaskType.remoteTransfer);
    expect(now().statusText, 'Dl. Queued');
    games.updateExtractionState(_game.gameId, ExtractionStatus.extracting, 0.5);
    expect(now().status, GameStatus.extracting);
    expect(now().statusText, 'Downloading');
    expect(now().isTransfer, isTrue);
  });

  test('a finished transfer lands in Completed', () {
    games.updateExtractionState(_game.gameId, ExtractionStatus.extracting, 0.5);
    games.updateExtractionState(_game.gameId, ExtractionStatus.completed, 1);
    expect(now().status, GameStatus.downloaded);
    expect(now().hasJustCompleted, isTrue);
  });

  test('a failed transfer offers retry download, not retry extraction', () {
    games.updateExtractionState(_game.gameId, ExtractionStatus.extracting, 0.5);
    games.updateExtractionState(_game.gameId, ExtractionStatus.failed, 0);
    expect(now().status, GameStatus.downloadFailed);
    expect(now().availableActions, {GameAction.retryDownload, GameAction.cancel});
  });

  test('a non-transfer extraction failure still offers retry extraction', () {
    const g = Game(title: 'x', url: 'https://x/x.zip', size: 0, consoleId: 'manual');
    games.registerTransientGame(g);
    games.updateExtractionState(g.gameId, ExtractionStatus.extracting, 0.1);
    games.updateExtractionState(g.gameId, ExtractionStatus.failed, 0);
    final s = c.read(gameStateManagerProvider)[g.gameId]!;
    expect(s.status, GameStatus.extractionFailed);
    expect(s.availableActions, contains(GameAction.retryExtraction));
  });

  testWidgets('the progress row says Downloading / Queued for download for a transfer, Extracting for the rest', (t) async {
    Future<void> show(GameState s) => t.pumpWidget(MaterialApp(home: Scaffold(body: GameProgressBar(gameState: s))));
    GameState st(GameStatus status, bool transfer) =>
        GameState(game: _game, status: status, isTransfer: transfer, showProgressBar: true, currentProgress: 0.4);
    await show(st(GameStatus.extracting, true));
    expect(find.text('Downloading...'), findsOneWidget);
    await show(st(GameStatus.extractionQueued, true));
    expect(find.text('Queued for download'), findsOneWidget);
    await show(st(GameStatus.extracting, false));
    expect(find.text('Extracting...'), findsOneWidget);
    await show(st(GameStatus.extractionQueued, false));
    expect(find.text('Queued for extraction'), findsOneWidget);
  });

  testWidgets('retry download on a failed transfer re-enqueues the transfer with its original job', (t) async {
    Future<void> job(void Function(int, int) _) async {}
    final original = QueuedTask(
      id: _game.gameId,
      type: TaskType.remoteTransfer,
      status: TaskQueueStatus.failed,
      createdAt: DateTime(2026),
      params: {'taskId': _game.gameId, 'source': 'smb', 'verb': 'Downloading', 'label': 'x', 'run': job},
    );
    final queue = _FakeQueue([original]);
    late WidgetRef ref;
    await t.pumpWidget(ProviderScope(
      overrides: [taskQueueProvider.overrideWith((_) => queue)],
      child: MaterialApp(home: Consumer(builder: (ctx, r, _) {
        ref = r;
        return const SizedBox();
      })),
    ));
    final ctx = t.element(find.byType(SizedBox));
    await runGameAction(ref, ctx, _game, GameState(game: _game, status: GameStatus.downloadFailed, isTransfer: true), GameAction.retryDownload);
    expect(queue.enqueued.single.$1, _game.gameId);
    expect(queue.enqueued.single.$2, TaskType.remoteTransfer);
    expect(queue.enqueued.single.$3['run'], same(job));
  });
}
