import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/file_ops.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_importer.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_platforms.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_store.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/utils/remote_tree.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shown instead of starting an import that would keep no platform.
const noLaunchboxConsolesMessage = 'None of your consoles has LaunchBox data yet';

typedef LaunchboxImporterFactory = LaunchboxImporter Function(LaunchboxStore store, Directory cacheDir);

const _useCoversKey = 'launchbox_use_covers';

/// Whether game thumbnails show LaunchBox's front cover. The catalog reads it
/// here rather than from [LaunchboxState]: it loads long before Settings
/// first refreshes that.
Future<bool> launchboxUseCovers() async {
  try {
    return (await SharedPreferences.getInstance()).getBool(_useCoversKey) ?? false;
  } catch (e) {
    debugPrint('LaunchBox covers setting unreadable: $e');
    return false;
  }
}

/// The shape of [TaskQueueService.enqueueTransfer].
typedef TransferEnqueue = String Function(
  WidgetRef ref,
  BuildContext context, {
  required String title,
  required String source,
  required String verb,
  required String label,
  required TransferJob run,
  String? outputPath,
});

class LaunchboxState {
  const LaunchboxState({
    this.loading = true,
    this.manifest,
    this.wanted = const {},
    this.importing = false,
    this.message,
    this.useCovers = false,
  });

  /// Until the first manifest read.
  final bool loading;

  /// Null: metadata is off.
  final LaunchboxManifest? manifest;

  /// LaunchBox platforms of the configured consoles.
  final Set<String> wanted;
  final bool importing;

  /// The last import's outcome: "Already up to date", "Updated", or the error.
  final String? message;

  /// LaunchBox's front covers as game thumbnails, where it has one.
  final bool useCovers;

  /// Platforms a console needs that the last import did not keep.
  Set<String> get missing => manifest == null ? const {} : wanted.difference(manifest!.platforms);

  LaunchboxState copyWith({
    bool? loading,
    LaunchboxManifest? manifest,
    bool clearManifest = false,
    Set<String>? wanted,
    bool? importing,
    String? message,
    bool clearMessage = false,
    bool? useCovers,
  }) =>
      LaunchboxState(
        loading: loading ?? this.loading,
        manifest: clearManifest ? null : (manifest ?? this.manifest),
        wanted: wanted ?? this.wanted,
        importing: importing ?? this.importing,
        message: clearMessage ? null : (message ?? this.message),
        useCovers: useCovers ?? this.useCovers,
      );
}

final launchboxProvider = StateNotifierProvider<LaunchboxNotifier, LaunchboxState>((ref) => LaunchboxNotifier(ref));

class LaunchboxNotifier extends StateNotifier<LaunchboxState> {
  LaunchboxNotifier(
    this._ref, {
    LaunchboxStore? store,
    Future<Iterable<Console>> Function()? consoles,
    LaunchboxImporterFactory? importer,
    Future<Directory> Function()? cacheDir,
    TransferEnqueue? enqueue,
  })  : _givenStore = store,
        _consoles = consoles ?? _catalogConsoles,
        _importer = importer ?? ((store, cacheDir) => LaunchboxImporter(store: store, cacheDir: cacheDir)),
        _cacheDir = cacheDir ?? getApplicationCacheDirectory,
        _enqueue = enqueue ?? TaskQueueService.enqueueTransfer,
        super(const LaunchboxState());

  // The provider's own ref, not the card's: an import outlives the Settings
  // page that started it.
  final Ref _ref;
  final LaunchboxStore? _givenStore;
  final Future<Iterable<Console>> Function() _consoles;
  final LaunchboxImporterFactory _importer;
  final Future<Directory> Function() _cacheDir;
  final TransferEnqueue _enqueue;

  /// Bumped per [refresh]; only the newest one writes the state, so a slow
  /// read from before an import or a delete cannot land after it.
  int _refreshes = 0;

  /// The import's Task Manager row, kept for Retry and Cancel.
  String? _taskId;

  /// Whether the job is running: until then a row that leaves the queue
  /// means the job never will.
  bool _running = false;
  ProviderSubscription<bool>? _rowWatch;

  static Future<Iterable<Console>> _catalogConsoles() async => (await CatalogService().getConsoles()).values;

  Future<LaunchboxStore> _store() async => _givenStore ?? await LaunchboxService.instance.store();

  /// Never throws: the card calls it from initState. A failed read shows
  /// what the state already had.
  Future<void> refresh() async {
    final gen = ++_refreshes;
    final LaunchboxManifest? manifest;
    final Set<String> wanted;
    final bool useCovers;
    try {
      wanted = {
        for (final c in await _consoles())
          if (launchboxPlatformFor(c) case final p?) p,
      };
      manifest = await (await _store()).readManifest();
      useCovers = await launchboxUseCovers();
    } catch (e) {
      debugPrint('LaunchBox refresh failed: $e');
      if (mounted && gen == _refreshes) state = state.copyWith(loading: false);
      return;
    }
    if (!mounted || gen != _refreshes) return;
    state = state.copyWith(loading: false, manifest: manifest, clearManifest: manifest == null, wanted: wanted, useCovers: useCovers);
  }

  /// Queues an import of [LaunchboxState.wanted] as a Task Manager row.
  void startImport(WidgetRef ref, BuildContext context) {
    if (state.importing) return;
    // 110 MB for an index of nothing.
    if (state.wanted.isEmpty) {
      state = state.copyWith(message: noLaunchboxConsolesMessage);
      return;
    }
    state = state.copyWith(importing: true, clearMessage: true);
    final id = _taskId = _enqueue(
      ref,
      context,
      title: 'LaunchBox metadata',
      source: 'launchbox',
      verb: 'Updating',
      label: 'LaunchBox metadata',
      // Read when the job runs, so a Retry imports the consoles of then.
      run: (onProgress) => _import(state.wanted, onProgress),
    );
    _rowWatch?.close();
    // A waiting row cancelled from the Task Manager is just dropped: the job
    // never runs to say so.
    _rowWatch = _ref.listen<bool>(gameStateManagerProvider.select((games) => games.containsKey(id)), (_, present) {
      if (present || id != _taskId) return;
      _rowWatch?.close();
      _rowWatch = null;
      if (!_running && state.importing) state = state.copyWith(importing: false, message: 'Cancelled');
    });
  }

  /// Stops the import: a running job at its next progress report, a waiting
  /// one by taking it out of the queue, as the file browsers' Cancel does.
  void cancelImport() {
    final id = _taskId;
    if (id == null || !state.importing) return;
    final row = _ref.read(taskQueueProvider).tasks.where((t) => t.id == id).lastOrNull;
    if (row?.status == TaskQueueStatus.running) {
      _ref.read(extractionProvider.notifier).cancel(id);
    } else {
      _ref.read(taskQueueProvider.notifier).cancelQueuedTask(id);
    }
  }

  /// The task's job. Rethrows so the row shows the failure too. Also runs
  /// again from the Task Manager's Retry, so it marks itself importing.
  Future<void> _import(Set<String> platforms, FileOpsProgress onProgress) async {
    _running = true;
    if (mounted) state = state.copyWith(importing: true, clearMessage: true);
    final LaunchboxImportResult result;
    try {
      final importer = _importer(await _store(), await _cacheDir());
      result = await importer.run(platforms, onProgress: onProgress);
    } catch (e) {
      if (mounted) state = state.copyWith(importing: false, message: e is TaskCancelledException ? 'Cancelled' : '$e');
      rethrow;
    } finally {
      _running = false;
    }
    if (mounted) {
      state = state.copyWith(importing: false, message: result == LaunchboxImportResult.updated ? 'Updated' : 'Already up to date');
    }
    LaunchboxService.instance.invalidate();
    await refresh();
    if (mounted) await _ref.read(catalogProvider.notifier).reapplyLaunchbox();
  }

  /// Saves the choice and swaps the open list's thumbnails at once.
  Future<void> setUseCovers(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(_useCoversKey, on);
    if (mounted) state = state.copyWith(useCovers: on);
    if (mounted) await _ref.read(catalogProvider.notifier).reapplyLaunchbox();
  }

  /// Deletes every imported file, the match caches with them.
  Future<void> turnOff() async {
    String? error;
    try {
      await (await _store()).deleteAll();
    } catch (e) {
      // Some files may be gone already; the refresh shows what is left.
      error = 'Could not delete the metadata: $e';
    }
    LaunchboxService.instance.invalidate();
    if (mounted) state = state.copyWith(message: error, clearMessage: error == null);
    await refresh();
    if (mounted) await _ref.read(catalogProvider.notifier).reapplyLaunchbox();
  }
}
