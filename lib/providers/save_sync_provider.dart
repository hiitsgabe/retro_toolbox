import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';

enum SyncAccess { none, shizuku, root }

class SaveSyncState {
  const SaveSyncState({
    this.loading = false,
    this.access = SyncAccess.none,
    this.shizukuRunning = false,
    this.hubFolder = '',
    this.games = const [],
    this.recipeProblems = const {},
    this.busyRecipe,
    this.messages = const [],
    this.error,
  });

  final bool loading;
  final SyncAccess access;
  final bool shizukuRunning;
  final String hubFolder;
  final List<GameStatus> games;

  /// Recipe file to why it was not loaded.
  final Map<String, String> recipeProblems;
  final String? busyRecipe;

  /// Results of the last action, one line per unit.
  final List<String> messages;
  final String? error;

  SaveSyncState copyWith({
    bool? loading,
    SyncAccess? access,
    bool? shizukuRunning,
    String? hubFolder,
    List<GameStatus>? games,
    Map<String, String>? recipeProblems,
    String? busyRecipe,
    bool clearBusy = false,
    List<String>? messages,
    String? error,
    bool clearError = false,
  }) =>
      SaveSyncState(
        loading: loading ?? this.loading,
        access: access ?? this.access,
        shizukuRunning: shizukuRunning ?? this.shizukuRunning,
        hubFolder: hubFolder ?? this.hubFolder,
        games: games ?? this.games,
        recipeProblems: recipeProblems ?? this.recipeProblems,
        busyRecipe: clearBusy ? null : (busyRecipe ?? this.busyRecipe),
        messages: messages ?? this.messages,
        error: clearError ? null : (error ?? this.error),
      );
}

final saveSyncProvider = StateNotifierProvider<SaveSyncNotifier, SaveSyncState>((ref) => SaveSyncNotifier());

/// Every recipe's status, one at a time. A status that throws becomes that
/// game's error, so one bad game never empties the whole list.
Future<List<GameStatus>> gameStatuses(Iterable<(Recipe, String)> recipes, Future<GameStatus> Function(Recipe r, String source) status) async {
  final games = <GameStatus>[];
  for (final (r, source) in recipes) {
    try {
      games.add(await status(r, source));
    } catch (e) {
      games.add(GameStatus(r, source, const NeedsDiscovery('status failed'), error: '$e'));
    }
  }
  return games;
}

class SaveSyncNotifier extends StateNotifier<SaveSyncState> {
  SaveSyncNotifier({DevicePaths paths = const DevicePaths(), RecipeStore? store})
      : _paths = paths,
        _store = store ?? RecipeStore(),
        super(const SaveSyncState());

  final DevicePaths _paths;
  final RecipeStore _store;
  SaveSyncEngine? _engine;

  /// Recipe id to (recipe, source).
  final _recipes = <String, (Recipe, String)>{};

  static const _native = MethodChannel('retrotoolbox/native');

  Future<SyncState>? _syncState;

  /// One store for the notifier's life: each store caches what it read, so a second one would write a binding
  /// or base over the first one's newer copy. A failed open is tried again on the next call.
  Future<SyncState> _sync() => _syncState ??= PrefsStore.open().then(SyncState.new, onError: (Object e, StackTrace st) {
        _syncState = null;
        Error.throwWithStackTrace(e, st);
      });

  Future<void>? _refreshing;

  /// One refresh at a time: two would build two engines, and one could recover a pull the other is running.
  Future<void> refresh() {
    // A new engine has its own queue: a refresh during an action would scan the unit mid-pull.
    if (state.busyRecipe != null) return Future.value();
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    state = state.copyWith(loading: true, clearError: true);
    _engine = null;
    try {
      // Access and the hub folder reach state as soon as they are known, so a hub that fails to open
      // (a removed SD card) does not also show "no access" and "not set".
      final sync = await _sync();
      final hubFolder = sync.hubFolder ?? '${_paths.sdcard}/Retro Toolbox Saves';
      state = state.copyWith(hubFolder: hubFolder);
      final shizuku = await ShizukuShell.status();
      state = state.copyWith(shizukuRunning: shizuku.running);
      final shell = await _shell(shizuku);
      final access = switch (shell?.privilege) {
        null => SyncAccess.none,
        Privilege.root => SyncAccess.root,
        _ => SyncAccess.shizuku,
      };
      state = state.copyWith(access: access);
      var problems = state.recipeProblems;
      if (_recipes.isEmpty) {
        final load = await _store.loadBundled();
        for (final r in load.recipes) {
          _recipes[r.id] = (r, 'bundled');
        }
        problems = {...load.rejected, for (final f in load.tooNew) f: 'needs a newer Retro Toolbox'};
      }
      if (shell == null) {
        state = state.copyWith(loading: false, games: const [], recipeProblems: problems);
        return;
      }
      final model = await _deviceModel();
      final deviceId = await sync.deviceId(model);
      final hub = Hub(FolderBackend(Directory(hubFolder)));
      await hub.open(deviceId: deviceId);
      for (final e in (await hub.recipes()).entries) {
        final known = _recipes[e.key];
        if (known != null && known.$2 != 'hub') continue;
        try {
          _recipes[e.key] = (Recipe.parse(e.value.recipe), 'hub');
        } catch (err) {
          problems = {...problems, 'hub: ${e.key}': '$err'};
        }
      }
      final engine = SaveSyncEngine(
        shell: shell,
        hub: hub,
        state: sync,
        paths: _paths,
        deviceId: deviceId,
        deviceName: model,
        model: model,
        appVersion: (await PackageInfo.fromPlatform()).version,
      );
      final games = await gameStatuses(_recipes.values, (r, source) => engine.status(r, source: source));
      // The engine is published with the games it produced: until then the catch below sees no engine and clears them.
      _engine = engine;
      state = state.copyWith(loading: false, games: games, recipeProblems: problems);
      await engine.report(games, access: access.name);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e', games: _engine == null ? const [] : null);
    }
  }

  Future<PrivilegedShell?> _shell(ShizukuStatus s) async {
    if (s.granted) return ShizukuShell(uid: s.uid);
    if (!Platform.isAndroid || appFlavor == 'play') return null;
    // Probed every round: root can vanish after an OTA.
    return await ProcessShell.rootAvailable() ? ProcessShell(viaSu: true) : null;
  }

  Future<String> _deviceModel() async {
    try {
      final m = (await _native.invokeMethod<String>('deviceModel'))?.trim() ?? '';
      return m.isEmpty ? 'Android' : m;
    } on MissingPluginException {
      return Platform.operatingSystem;
    } on PlatformException {
      return 'Android';
    }
  }

  Future<void> _act(String recipeId, Future<List<String>> Function(SaveSyncEngine engine, Recipe recipe, String source) action) async {
    if (state.busyRecipe != null) return;
    state = state.copyWith(busyRecipe: recipeId, messages: const []);
    // Busy is set first so no new refresh starts; wait out the one in flight, then take its engine.
    await _refreshing;
    final engine = _engine;
    final entry = _recipes[recipeId];
    if (engine == null || entry == null) {
      state = state.copyWith(clearBusy: true);
      return;
    }
    List<String> messages;
    try {
      messages = await action(engine, entry.$1, entry.$2);
    } catch (e) {
      messages = ['$e'];
    }
    state = state.copyWith(clearBusy: true, messages: messages);
    await refresh();
  }

  Future<void> push(String recipeId) => _act(recipeId, (e, r, s) => e.push(r, source: s));

  Future<void> pull(String recipeId) => _act(recipeId, (e, r, s) => e.pull(r, source: s));

  Future<List<CheckLine>> check(String recipeId) async {
    final engine = _engine;
    final entry = _recipes[recipeId];
    if (engine == null || entry == null) return const [CheckLine(CheckLevel.fail, 'Access', 'No access to game folders; start Shizuku first')];
    return engine.check(entry.$1, source: entry.$2);
  }

  Future<void> confirmBinding(Binding b) async {
    await (await _sync()).setBinding(b);
    await refresh();
  }

  Future<void> setHubFolder(String path) async {
    await (await _sync()).setHubFolder(path);
    await refresh();
  }

  Future<void> requestShizuku() async {
    await ShizukuShell.requestPermission();
    await refresh();
  }
}
