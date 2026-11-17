import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_importer.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_store.dart';
import 'package:retro_toolbox/utils/remote_tree.dart';
import 'package:retro_toolbox/widgets/settings/launchbox_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

const snes = 'Super Nintendo Entertainment System';
const nes = 'Nintendo Entertainment System';

const consoles = [
  Console(id: 'snes-usa', name: 'SNES', urls: [], platform: 'snes'),
  Console(id: 'nes-usa', name: 'NES', urls: [], platform: 'nes'),
  // No built-in platform and no override: no metadata for it.
  Console(id: 'odd', name: 'Odd', urls: [], platform: 'notaplatform'),
  Console(id: 'mine', name: 'Mine', urls: [], platform: 'notaplatform', launchboxPlatform: 'My Platform'),
];

typedef Outcome = Future<LaunchboxImportResult> Function(LaunchboxStore store, Set<String> platforms, void Function(int, int) onProgress);

class FakeImporter extends LaunchboxImporter {
  FakeImporter(LaunchboxStore store, Directory cacheDir, this.outcome) : super(store: store, cacheDir: cacheDir);
  final Outcome outcome;

  @override
  Future<LaunchboxImportResult> run(Set<String> platforms, {required void Function(int done, int total) onProgress}) =>
      outcome(store, platforms, onProgress);
}

class FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  FakeCatalog() : super(const CatalogState());
  int reapplied = 0;

  @override
  Future<void> reapplyLaunchbox() async => reapplied++;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  FakeSettings() : super(const AppSettings());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Holds rows without running them. A cancel drops the row and its Task
/// Manager state, as the real queue does.
class FakeQueue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  FakeQueue(this.ref) : super(const TaskQueueState());
  final Ref ref;
  final cancelled = <String>[];

  void add(String id) => state = TaskQueueState(tasks: [...state.tasks, QueuedTask(id: id, type: TaskType.remoteTransfer, createdAt: DateTime.now())]);

  void markRunning(String id) =>
      state = TaskQueueState(tasks: [for (final t in state.tasks) t.id == id ? t.copyWith(status: TaskQueueStatus.running) : t]);

  @override
  void cancelQueuedTask(String taskId) {
    cancelled.add(taskId);
    state = TaskQueueState(tasks: [for (final t in state.tasks) if (t.id != taskId) t]);
    ref.read(gameStateManagerProvider.notifier).resetAfterCancel(taskId);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Stops a running job the way fileTask does: its next progress report throws.
class FakeExtraction extends StateNotifier<ExtractionState> implements ExtractionNotifier {
  FakeExtraction() : super(const ExtractionState());
  final cancelled = <String>{};

  @override
  void cancel(String taskId) => cancelled.add(taskId);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class ThrowingStore extends LaunchboxStore {
  ThrowingStore(super.root);
  @override
  Future<void> deleteAll() async => throw const FileSystemException('Permission denied');
}

/// The fake enqueue never touches them.
class NoRef implements WidgetRef {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class NoContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Counts imports instead of running them, and keeps the last turnOff so a
/// widget test can wait for its disk work.
class CountingNotifier extends LaunchboxNotifier {
  CountingNotifier(super.ref, {super.store, super.consoles});
  int imports = 0;
  int cancels = 0;
  final covers = <bool>[];
  Future<void>? turningOff;

  @override
  void startImport(WidgetRef ref, BuildContext context) => imports++;

  @override
  Future<void> turnOff() => turningOff = super.turnOff();

  @override
  void cancelImport() => cancels++;

  @override
  Future<void> setUseCovers(bool on) async => covers.add(on);

  void showImporting(String lastMessage) => state = state.copyWith(importing: true, message: lastMessage);
}

void main() {
  late Directory tmp;
  late LaunchboxStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('lb_setting_');
    store = LaunchboxStore(Directory('${tmp.path}/launchbox'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> writeManifest(Set<String> platforms, DateTime importedAt) =>
      store.writeManifest(LaunchboxManifest(etag: '"e1"', importedAt: importedAt, platforms: platforms));

  group('notifier', () {
    late FakeCatalog catalog;
    late FakeQueue queue;
    late FakeExtraction extraction;
    late List<TransferJob> jobs;
    late List<String> titles;
    late List<String> ids;

    ProviderContainer container(Outcome outcome, {Future<Iterable<Console>> Function()? consoleSource, LaunchboxStore? storeOverride}) {
      catalog = FakeCatalog();
      extraction = FakeExtraction();
      jobs = [];
      titles = [];
      ids = [];
      late ProviderContainer c;
      c = ProviderContainer(overrides: [
        catalogProvider.overrideWith((ref) => catalog),
        settingsProvider.overrideWith((ref) => FakeSettings()),
        taskQueueProvider.overrideWith((ref) => queue = FakeQueue(ref)),
        extractionProvider.overrideWith((ref) => extraction),
        launchboxProvider.overrideWith(
          (ref) => LaunchboxNotifier(
            ref,
            store: storeOverride ?? store,
            consoles: consoleSource ?? () async => consoles,
            importer: (store, cacheDir) => FakeImporter(store, cacheDir, outcome),
            cacheDir: () async => tmp,
            // What enqueueTransfer does, minus the WidgetRef: a Task Manager
            // state and a waiting row.
            enqueue: (ref, context, {required title, required source, required verb, required label, required run, outputPath}) {
              titles.add('$title: $verb $label ($source)');
              jobs.add(run);
              final game = Game(title: title, url: 'https://manual/net-${jobs.length}.task', size: 0, consoleId: 'manual');
              c.read(gameStateManagerProvider.notifier).registerTransientGame(game, isTransfer: true);
              (c.read(taskQueueProvider.notifier) as FakeQueue).add(game.gameId);
              ids.add(game.gameId);
              return game.gameId;
            },
          ),
        ),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('refresh wants the platforms of consoles that have one, and reads the manifest', () async {
      final c = container((_, __, ___) async => LaunchboxImportResult.updated);
      final n = c.read(launchboxProvider.notifier);
      expect(c.read(launchboxProvider).loading, isTrue);

      await n.refresh();
      var s = c.read(launchboxProvider);
      expect(s.loading, isFalse);
      expect(s.wanted, {snes, nes, 'My Platform'});
      expect(s.manifest, isNull);
      expect(s.missing, isEmpty, reason: 'nothing is missing while metadata is off');
      expect(c.read(launchboxVersionProvider), isNull);

      await writeManifest({snes, nes}, DateTime.utc(2026, 11, 16));
      await n.refresh();
      s = c.read(launchboxProvider);
      expect(s.manifest!.platforms, {snes, nes});
      expect(s.missing, {'My Platform'});
      expect(c.read(launchboxVersionProvider), '"e1"');
    });

    test('a slow refresh that started first does not overwrite a newer one', () async {
      final answers = <Completer<Iterable<Console>>>[];
      final c = container((_, __, ___) async => LaunchboxImportResult.updated, consoleSource: () {
        answers.add(Completer());
        return answers.last.future;
      });
      final n = c.read(launchboxProvider.notifier);
      final older = n.refresh();
      final newer = n.refresh();
      expect(answers, hasLength(2), reason: 'each asks for consoles before any await');
      answers[1].complete([consoles.first]);
      await newer;
      answers[0].complete(consoles);
      await older;
      expect(c.read(launchboxProvider).wanted, {snes});
    });

    test('a waiting row cancelled from the Task Manager unlocks the card', () async {
      final c = container((_, __, ___) async => LaunchboxImportResult.updated);
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      n.startImport(NoRef(), NoContext());
      expect(c.read(launchboxProvider).importing, isTrue);

      queue.cancelQueuedTask(ids.single);
      final s = c.read(launchboxProvider);
      expect(s.importing, isFalse);
      expect(s.message, 'Cancelled');
      n.startImport(NoRef(), NoContext());
      expect(jobs, hasLength(2), reason: 'a new import can start');
    });

    test('Cancel on a waiting import takes it out of the queue', () async {
      final c = container((_, __, ___) async => LaunchboxImportResult.updated);
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      n.startImport(NoRef(), NoContext());
      n.cancelImport();
      expect(queue.cancelled, ids);
      expect(extraction.cancelled, isEmpty);
      expect(c.read(launchboxProvider).importing, isFalse);
      expect(c.read(launchboxProvider).message, 'Cancelled');
    });

    test('Cancel on a running import stops the job, which says Cancelled', () async {
      final atGate = Completer<void>();
      final gate = Completer<void>();
      final c = container((store, platforms, onProgress) async {
        onProgress(0, 1000);
        atGate.complete();
        await gate.future;
        onProgress(500, 1000);
        return LaunchboxImportResult.updated;
      });
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      n.startImport(NoRef(), NoContext());
      final id = ids.single;
      queue.markRunning(id);
      // The job's progress callback as fileTask builds it.
      final job = jobs.single((done, total) {
        if (extraction.cancelled.contains(id)) throw const TaskCancelledException();
      });
      await atGate.future;

      n.cancelImport();
      expect(extraction.cancelled, {id});
      expect(queue.cancelled, isEmpty);
      expect(c.read(launchboxProvider).importing, isTrue, reason: 'still unwinding');
      // The real cancel also drops the row; the job, not the row watch, reports it.
      queue.cancelQueuedTask(id);
      expect(c.read(launchboxProvider).importing, isTrue);

      gate.complete();
      await expectLater(job, throwsA(isA<TaskCancelledException>()));
      final s = c.read(launchboxProvider);
      expect(s.importing, isFalse);
      expect(s.message, 'Cancelled');
      expect(catalog.reapplied, 0);
    });

    test('a retried job imports the consoles of when it runs', () async {
      var round = 0;
      final asked = <Set<String>>[];
      final c = container((_, platforms, __) async {
        asked.add(platforms);
        if (round++ == 0) throw const HttpException('offline');
        return LaunchboxImportResult.updated;
      }, consoleSource: () async => round == 0 ? consoles : [consoles.first]);
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      n.startImport(NoRef(), NoContext());
      await expectLater(jobs.single((_, __) {}), throwsA(isA<HttpException>()));
      await n.refresh();
      expect(c.read(launchboxProvider).importing, isFalse);

      // Retry runs the same job again, without startImport.
      final retry = jobs.single((_, __) {});
      expect(c.read(launchboxProvider).importing, isTrue, reason: 'a retried job locks the card too');
      await retry;
      expect(asked, [
        {snes, nes, 'My Platform'},
        {snes},
      ]);
    });

    test('with no console LaunchBox knows, nothing is downloaded', () async {
      final c = container((_, __, ___) async => LaunchboxImportResult.updated, consoleSource: () async => [consoles[2]]);
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      expect(c.read(launchboxProvider).wanted, isEmpty);
      n.startImport(NoRef(), NoContext());
      expect(jobs, isEmpty);
      expect(c.read(launchboxProvider).importing, isFalse);
      expect(c.read(launchboxProvider).message, noLaunchboxConsolesMessage);
    });

    test('a delete that fails is reported and the card shows what is left', () async {
      await writeManifest({snes}, DateTime.utc(2026, 11, 16));
      final c = container((_, __, ___) async => LaunchboxImportResult.updated, storeOverride: ThrowingStore(store.root));
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      await n.turnOff();
      final s = c.read(launchboxProvider);
      expect(s.message, contains('Permission denied'));
      expect(s.manifest, isNotNull, reason: 'refreshed: the files are still there');
      expect(catalog.reapplied, 1);
    });

    test('the queued job reports progress as counts and ends with Updated', () async {
      late bool importingDuringRun;
      Set<String>? asked;
      late ProviderContainer c;
      c = container((store, platforms, onProgress) async {
        importingDuringRun = c.read(launchboxProvider).importing;
        asked = platforms;
        onProgress(0, 1000);
        onProgress(500, 1000);
        onProgress(1000, 1000);
        await store.writeManifest(LaunchboxManifest(etag: null, importedAt: DateTime.utc(2026, 11, 17), platforms: platforms));
        return LaunchboxImportResult.updated;
      });
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();

      n.startImport(NoRef(), NoContext());
      expect(titles, ['LaunchBox metadata: Updating LaunchBox metadata (launchbox)']);
      expect(c.read(launchboxProvider).importing, isTrue, reason: 'importing from the moment it is queued');

      final progress = <(int, int)>[];
      await jobs.single((done, total) => progress.add((done, total)));
      expect(importingDuringRun, isTrue);
      expect(asked, {snes, nes, 'My Platform'});
      expect(progress, [(0, 1000), (500, 1000), (1000, 1000)]);

      final s = c.read(launchboxProvider);
      expect(s.importing, isFalse);
      expect(s.message, 'Updated');
      expect(s.manifest!.platforms, {snes, nes, 'My Platform'}, reason: 'refreshed after the import');
      expect(catalog.reapplied, 1);
    });

    test('a 304 ends with Already up to date', () async {
      final c = container((_, __, ___) async => LaunchboxImportResult.upToDate);
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      n.startImport(NoRef(), NoContext());
      await jobs.single((_, __) {});
      expect(c.read(launchboxProvider).message, 'Already up to date');
      expect(c.read(launchboxProvider).importing, isFalse);
    });

    test('a failing import is rethrown for the task row and recorded on the card', () async {
      final c = container((_, __, ___) async => throw const HttpException('LaunchBox answered HTTP 500'));
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      n.startImport(NoRef(), NoContext());
      await expectLater(jobs.single((_, __) {}), throwsA(isA<HttpException>()));
      final s = c.read(launchboxProvider);
      expect(s.importing, isFalse);
      expect(s.message, contains('LaunchBox answered HTTP 500'));
      expect(catalog.reapplied, 0, reason: 'a failed import changed nothing on disk');
    });

    test('covers are off until chosen, the choice is kept, and the open list switches at once', () async {
      var c = container((_, __, ___) async => LaunchboxImportResult.updated);
      var n = c.read(launchboxProvider.notifier);
      await n.refresh();
      expect(c.read(launchboxProvider).useCovers, isFalse);

      await n.setUseCovers(true);
      expect(c.read(launchboxProvider).useCovers, isTrue);
      expect(catalog.reapplied, 1);

      c = container((_, __, ___) async => LaunchboxImportResult.updated);
      n = c.read(launchboxProvider.notifier);
      await n.refresh();
      expect(c.read(launchboxProvider).useCovers, isTrue, reason: 'read back by a new notifier');
      expect(await launchboxUseCovers(), isTrue);

      await n.setUseCovers(false);
      expect(await launchboxUseCovers(), isFalse);
      expect(catalog.reapplied, 1, reason: "the new notifier's own catalog");
    });

    test('starting an import while one runs does nothing', () async {
      final c = container((_, __, ___) async => LaunchboxImportResult.updated);
      final n = c.read(launchboxProvider.notifier);
      await n.refresh();
      n.startImport(NoRef(), NoContext());
      n.startImport(NoRef(), NoContext());
      expect(jobs, hasLength(1));
      await jobs.single((_, __) {});
      n.startImport(NoRef(), NoContext());
      expect(jobs, hasLength(2), reason: 'a finished import lets the next one start');
    });
  });

  group('card', () {
    late CountingNotifier notifier;

    Future<void> pump(WidgetTester t) async {
      await t.runAsync(() async {
        await t.pumpWidget(ProviderScope(
          overrides: [
            catalogProvider.overrideWith((ref) => FakeCatalog()),
            launchboxProvider.overrideWith((ref) => notifier = CountingNotifier(ref, store: store, consoles: () async => consoles)),
          ],
          child: const MaterialApp(home: Scaffold(body: LaunchboxSetting())),
        ));
        // The card refreshes on open; this later one is the one that lands.
        await notifier.refresh();
      });
      await t.pump();
    }

    testWidgets('off: explains the download; Cancel starts nothing, Download imports', (t) async {
      await pump(t);
      expect(find.textContaining('Downloads about 110 MB once'), findsOneWidget);
      expect(find.text('Update'), findsNothing);

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(notifier.imports, 0);

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.text('Download'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(notifier.imports, 1);
    });

    testWidgets('on: shows the import date, the platform count and the consoles it misses', (t) async {
      // Early in the UTC day, so west of Greenwich the local date is the day before.
      final at = DateTime.utc(2026, 11, 16, 1);
      await t.runAsync(() => writeManifest({snes, nes}, at));
      await pump(t);
      final local = at.toLocal();
      final date = '${local.year}-${'${local.month}'.padLeft(2, '0')}-${'${local.day}'.padLeft(2, '0')}';
      expect(find.text('Updated $date · 2 platforms'), findsOneWidget);
      expect(find.text('New consoles need an update: My Platform'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('on with every platform imported: no update warning', (t) async {
      await t.runAsync(() => writeManifest({snes, nes, 'My Platform'}, DateTime.utc(2026, 11, 16, 12)));
      await pump(t);
      expect(find.textContaining('New consoles need an update'), findsNothing);
    });

    bool cancelFocused() {
      var inCancel = false;
      FocusManager.instance.primaryFocus!.context!.visitAncestorElements((e) {
        inCancel = e.widget is TextButton && find.descendant(of: find.byWidget(e.widget), matching: find.text('Cancel')).evaluate().isNotEmpty;
        return !inCancel;
      });
      return inCancel;
    }

    testWidgets('both dialogs open with Cancel focused', (t) async {
      await pump(t);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(cancelFocused(), isTrue);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();

      await t.runAsync(() async {
        await writeManifest({snes}, DateTime.utc(2026, 11, 16, 12));
        await notifier.refresh();
      });
      await t.pump();
      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect(find.text('Delete the downloaded metadata?'), findsOneWidget);
      expect(cancelFocused(), isTrue);
    });

    testWidgets('a controller reaches the switch, then Update, then covers', (t) async {
      await t.runAsync(() => writeManifest({snes}, DateTime.utc(2026, 11, 16, 12)));
      await pump(t);
      String? focused() {
        String? label;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
          if (e.widget case SwitchListTile(:final Text title)) label = title.data == 'Use LaunchBox metadata' ? 'switch' : 'covers';
          if (e.widget is FilledButton) label = 'update';
          return label == null;
        });
        return label;
      }

      final order = <String?>[];
      for (var i = 0; i < 3; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pump();
        order.add(focused());
      }
      expect(order, ['switch', 'update', 'covers']);
    });

    testWidgets('turning off asks, then deletes the store and goes back to off', (t) async {
      await t.runAsync(() => writeManifest({snes}, DateTime.utc(2026, 11, 16, 12)));
      await pump(t);
      expect(find.text('Update'), findsOneWidget);

      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      expect(find.text('Delete the downloaded metadata?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(notifier.turningOff, isNull);
      expect(store.root.existsSync(), isTrue);

      await t.tap(find.byType(Switch).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Delete'));
      await t.pump();
      // turnOff started in the fake zone: its disk work finishes in real time
      // and its continuations only run on a pump, so take turns.
      var done = false;
      notifier.turningOff!.then((_) => done = true);
      for (var i = 0; i < 100 && !done; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await t.pump();
      }
      expect(done, isTrue);
      await t.pumpAndSettle();
      expect(store.root.existsSync(), isFalse);
      expect(find.textContaining('Downloads about 110 MB once'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
    });

    testWidgets('off with no console LaunchBox knows: says so and cannot be turned on', (t) async {
      await t.runAsync(() async {
        await t.pumpWidget(ProviderScope(
          overrides: [
            catalogProvider.overrideWith((ref) => FakeCatalog()),
            launchboxProvider.overrideWith((ref) => notifier = CountingNotifier(ref, store: store, consoles: () async => [consoles[2]])),
          ],
          child: const MaterialApp(home: Scaffold(body: LaunchboxSetting())),
        ));
        await notifier.refresh();
      });
      await t.pump();
      expect(find.text(noLaunchboxConsolesMessage), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged, isNull);
    });

    testWidgets('the covers switch shows only with metadata on, and sets the choice', (t) async {
      const covers = 'Use LaunchBox covers for thumbnails';
      await pump(t);
      expect(find.text(covers), findsNothing);

      await t.runAsync(() async {
        await writeManifest({snes}, DateTime.utc(2026, 11, 16, 12));
        await notifier.refresh();
      });
      await t.pump();
      expect(find.text(covers), findsOneWidget);
      expect(find.text("Instead of the catalog's box art, when LaunchBox has one"), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, covers)).value, isFalse);

      await t.tap(find.text(covers));
      await t.pump();
      expect(notifier.covers, [true]);
    });

    testWidgets('while importing the card points at the Task Manager', (t) async {
      await t.runAsync(() => writeManifest({snes}, DateTime.utc(2026, 11, 16, 12)));
      await pump(t);
      notifier.showImporting('Updated');
      await t.pump();
      expect(find.text('Importing, see the Task Manager'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
      expect(find.text('Updated'), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byType(SwitchListTile).first).onChanged, isNull);
      await t.tap(find.text('Cancel'));
      expect(notifier.cancels, 1);
    });
  });
}
