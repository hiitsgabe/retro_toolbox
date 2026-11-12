import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/drive_backend.dart';
import 'package:retro_toolbox/services/save_sync/drive_transport.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/errors.dart';
import 'package:retro_toolbox/services/save_sync/google_auth.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';

enum SyncAccess { none, shizuku, root }

/// Where the hub lives. [unknown] until the first refresh reads the stored
/// choice; [none] until the user makes one.
enum HubKind { unknown, none, folder, drive }

class SaveSyncState {
  const SaveSyncState({
    this.loading = false,
    this.access = SyncAccess.none,
    this.shizukuRunning = false,
    this.hubKind = HubKind.unknown,
    this.hubFolder = '',
    this.googleEmail = '',
    this.googleAvailable = false,
    this.signingIn = false,
    this.signInAgain = false,
    this.signInError,
    this.games = const [],
    this.recipeProblems = const {},
    this.busyRecipe,
    this.messages = const [],
    this.error,
  });

  final bool loading;
  final SyncAccess access;
  final bool shizukuRunning;
  final HubKind hubKind;

  /// The folder hub's path; '' for a Drive hub.
  final String hubFolder;

  /// The Drive hub's account; '' for a folder hub.
  final String googleEmail;

  /// This build can sign in to Google.
  final bool googleAvailable;
  final bool signingIn;

  /// Google wants the user again before the Drive hub opens.
  final bool signInAgain;

  /// Why the last sign-in did not finish.
  final String? signInError;
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
    HubKind? hubKind,
    String? hubFolder,
    String? googleEmail,
    bool? googleAvailable,
    bool? signingIn,
    bool? signInAgain,
    String? signInError,
    bool clearSignInError = false,
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
        hubKind: hubKind ?? this.hubKind,
        hubFolder: hubFolder ?? this.hubFolder,
        googleEmail: googleEmail ?? this.googleEmail,
        googleAvailable: googleAvailable ?? this.googleAvailable,
        signingIn: signingIn ?? this.signingIn,
        signInAgain: signInAgain ?? this.signInAgain,
        signInError: clearSignInError ? null : (signInError ?? this.signInError),
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
  SaveSyncNotifier({DevicePaths paths = const DevicePaths(), RecipeStore? store, GoogleAuth? google, DriveTransport? driveTransport})
      : _paths = paths,
        _store = store ?? RecipeStore(),
        _google = google ?? PluginGoogleAuth(),
        _transport = driveTransport,
        super(const SaveSyncState());

  final DevicePaths _paths;
  final RecipeStore _store;
  final GoogleAuth _google;
  DriveTransport? _transport;
  SaveSyncEngine? _engine;

  /// The backend id the hub recipes in [_recipes] came from.
  String? _hubId;

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
      // Access and the hub reach state as soon as they are known, so a hub that fails to open
      // (a removed SD card, Google offline) does not also show "no access" and "not set".
      final sync = await _sync();
      final choice = sync.hubChoice;
      state = state.copyWith(
        hubKind: switch (choice) {
          null => HubKind.none,
          FolderHub() => HubKind.folder,
          DriveHub() => HubKind.drive,
        },
        hubFolder: choice is FolderHub ? choice.path : '',
        googleEmail: choice is DriveHub ? choice.email : '',
        googleAvailable: _google.available,
        signInAgain: false,
      );
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
      if (shell == null || choice == null) {
        state = state.copyWith(loading: false, games: const [], recipeProblems: problems);
        return;
      }
      final model = await _deviceModel();
      final deviceId = await sync.deviceId(model);
      final hub = Hub(_backend(choice));
      if (hub.backend.id != _hubId) {
        // Recipes another hub published do not belong to this one.
        _recipes.removeWhere((_, r) => r.$2 == 'hub');
        _hubId = hub.backend.id;
      }
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
    } on DriveSignInNeeded catch (e) {
      state = state.copyWith(loading: false, error: '$e', signInAgain: true, games: _engine == null ? const [] : null);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e', games: _engine == null ? const [] : null);
    }
  }

  /// A new backend each refresh, so Drive listings are never older than the refresh.
  HubBackend _backend(HubChoice choice) => switch (choice) {
        FolderHub(:final path) => FolderBackend(Directory(path)),
        DriveHub() when !_google.available => throw SyncBlocked('This build cannot sign in to Google; choose a folder for the hub'),
        DriveHub(:final accountId, :final email) => DriveBackend(
            accountId,
            DriveApi(_transport ??= HttpDriveTransport(), AccountTokens(_google, GoogleAccount(id: accountId, email: email))),
          ),
      };

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
    if (engine == null || entry == null) {
      if (state.access == SyncAccess.none) return const [CheckLine(CheckLevel.fail, 'Access', 'No access to game folders; start Shizuku first')];
      if (state.hubKind == HubKind.none) return const [CheckLine(CheckLevel.fail, 'Hub', 'Choose where saves go first')];
      return [CheckLine(CheckLevel.fail, 'Hub', 'The hub is not open${state.error == null ? '' : ': ${state.error}'}')];
    }
    return engine.check(entry.$1, source: entry.$2);
  }

  Future<void> confirmBinding(Binding b) async {
    await (await _sync()).setBinding(b);
    await refresh();
  }

  String get defaultHubFolder => '${_paths.sdcard}/Retro Toolbox Saves';

  /// Makes the folder at [path] (default: [defaultHubFolder]) the hub. Game folders are not touched.
  Future<void> setHubFolder([String? path]) async {
    await (await _sync()).setHubChoice(FolderHub(path ?? defaultHubFolder));
    state = state.copyWith(clearSignInError: true);
    await refresh();
  }

  /// Google's account sheet, then its Drive consent; the account's Drive becomes the hub.
  /// Game folders are not touched, and bases stay per hub, so nothing mixes.
  Future<void> signInWithGoogle() async {
    if (state.busyRecipe != null || state.signingIn) return;
    state = state.copyWith(signingIn: true, clearSignInError: true);
    try {
      final account = await _google.signIn();
      await (await _sync()).setHubChoice(DriveHub(accountId: account.id, email: account.email));
    } catch (e) {
      state = state.copyWith(signingIn: false, signInError: '$e');
      return;
    }
    state = state.copyWith(signingIn: false);
    await refresh();
  }

  /// Forgets the Google account on this device and asks for a hub again. Its bases stay stored under
  /// its own hub id, ready if the same account signs in again.
  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {
      // The hub choice is forgotten either way.
    }
    await (await _sync()).setHubChoice(null);
    await refresh();
  }

  Future<void> requestShizuku() async {
    await ShizukuShell.requestPermission();
    await refresh();
  }
}
