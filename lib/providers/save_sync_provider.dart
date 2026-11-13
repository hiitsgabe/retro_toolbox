import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/drive_backend.dart';
import 'package:retro_toolbox/services/save_sync/drive_transport.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/errors.dart';
import 'package:retro_toolbox/services/save_sync/google_auth.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_config.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';
import 'package:retro_toolbox/services/save_sync/row_state.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';

enum SyncAccess { none, shizuku, root }

/// Where the hub lives. [unknown] until the first refresh reads the stored
/// choice; [none] until the user makes one.
enum HubKind { unknown, none, folder, drive }

/// What Android itself shows for an installed package.
class AppInfo {
  const AppInfo(this.label, this.icon);

  final String label;

  /// PNG bytes, or null when the icon could not be read. The same instance is
  /// handed out every time so the image decodes once for the whole list.
  final Uint8List? icon;
}

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
    this.appInfo = const {},
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

  /// Package to the icon and label Android itself shows for it. Empty until
  /// the look-up answers, and empty for good on a host with no platform side.
  final Map<String, AppInfo> appInfo;

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
    Map<String, AppInfo>? appInfo,
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
        appInfo: appInfo ?? this.appInfo,
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

  /// Icons and labels for this process's life. The same [AppInfo] instance is
  /// handed back every time, so the list decodes each PNG once instead of once
  /// per rebuild. Packages that answered with nothing are remembered too, so a
  /// game the device cannot show is not asked about on every refresh.
  static final _appInfo = <String, AppInfo?>{};

  RecipeIndex? _index;

  /// The published catalog, read only when somebody is about to choose an app.
  /// Null when this build was seeded with nowhere to look, which changes what
  /// the picker can offer and nothing else.
  Future<RecipeCatalog?> catalog() async {
    final base = const String.fromEnvironment('SAVE_SYNC_CATALOG_URL');
    if (base.isEmpty) return null;
    _index ??= RecipeIndex(baseUrl: base, cacheDir: Directory('${(await getApplicationSupportDirectory()).path}/save_sync'));
    return _index!.load();
  }

  /// Where this device keeps its own save-sync files.
  String get saveSyncDir => _paths.saveSync;

  /// Looks for an app's save folder and reports what is directly inside it,
  /// so somebody describing the app is shown the real thing rather than asked
  /// to type a path.
  Future<({String root, List<({String name, bool isDir})> entries})?> probeSaveFolder(String package) async {
    final shell = await _shell(await ShizukuShell.status());
    if (shell == null) return null;
    final fs = ShellGameFs(shell, PathGuard([for (final a in Area.values) _paths.area(a, package)]));
    for (final area in Area.values) {
      for (final root in ['${_paths.area(area, package)}/files', _paths.area(area, package)]) {
        if (!await fs.isDir(root)) continue;
        final entries = await fs.listDir(root);
        if (entries.isNotEmpty) return (root: root, entries: entries);
      }
    }
    return null;
  }

  /// Every app with a launcher entry, for the picker. Icons come along, since
  /// the same call already has the package manager open.
  Future<List<({String package, AppInfo info})>> launchableApps() async {
    try {
      final got = await _native.invokeListMethod<Object?>('launchableApps');
      final out = <({String package, AppInfo info})>[];
      for (final e in got ?? const []) {
        if (e is! Map) continue;
        final package = e['package'];
        if (package is! String) continue;
        final info = AppInfo((e['label'] as String?) ?? package, e['icon'] is Uint8List ? e['icon'] as Uint8List : null);
        _appInfo[package] = info;
        out.add((package: package, info: info));
      }
      out.sort((a, b) => a.info.label.toLowerCase().compareTo(b.info.label.toLowerCase()));
      return out;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Adds apps to the hub's configuration, so the choice reaches every other
  /// device. Writing only the change is what keeps two handhelds from
  /// colliding when they add different apps at the same time.
  Future<void> addApps(Map<String, String?> packageToRecipe) async {
    if (packageToRecipe.isEmpty) return;
    final sync = await _sync();
    final choice = sync.hubChoice;
    if (choice == null) return;
    final at = DateTime.now().toUtc();
    final deviceId = await sync.deviceId(await _deviceModel());
    final hub = Hub(_backend(choice));
    await hub.open(deviceId: deviceId);
    await hub.putConfig(
      {for (final e in packageToRecipe.entries) e.key: ConfigEntry(recipe: e.value, updatedAt: at, by: deviceId)},
      deviceId: deviceId,
      now: at,
    );
    await refresh();
  }

  /// Asks Android for the icon and label of any package not asked about yet.
  /// One call for the whole list. Silent where there is no platform side, so
  /// widget tests see an empty map instead of an error.
  Future<Map<String, AppInfo>> _loadAppInfo(Iterable<String> packages) async {
    final wanted = {for (final p in packages) p};
    final missing = [for (final p in wanted) if (!_appInfo.containsKey(p)) p];
    if (missing.isNotEmpty) {
      try {
        final got = await _native.invokeMapMethod<String, dynamic>('appInfo', {'packages': missing});
        for (final p in missing) {
          final e = got?[p];
          _appInfo[p] = e is Map
              ? AppInfo((e['label'] as String?) ?? '', e['icon'] is Uint8List ? e['icon'] as Uint8List : null)
              : null;
        }
      } on MissingPluginException {
        for (final p in missing) {
          _appInfo[p] = null;
        }
      } on PlatformException {
        for (final p in missing) {
          _appInfo[p] = null;
        }
      }
    }
    return {
      for (final p in wanted)
        if (_appInfo[p] != null) p: _appInfo[p]!,
    };
  }

  Future<SyncState>? _syncState;

  /// One store for the notifier's life: each store caches what it read, so a second one would write a binding
  /// or base over the first one's newer copy. A failed open is tried again on the next call.
  Future<SyncState> _sync() => _syncState ??= PrefsStore.open().then(SyncState.new, onError: (Object e, StackTrace st) {
        _syncState = null;
        Error.throwWithStackTrace(e, st);
      });

  Future<void>? _refreshing;
  bool _again = false;

  /// Set only between the owner picking a place and the refresh that reads it.
  bool _creatingHub = false;

  /// One refresh at a time: two would build two engines, and one could recover a pull the other is running.
  /// A refresh asked for while one runs (a sign out during the report upload) runs once more after it,
  /// so the caller never gets back a state built from the hub it just left.
  Future<void> refresh() {
    // A new engine has its own queue: a refresh during an action would scan the unit mid-pull.
    if (state.busyRecipe != null) return Future.value();
    final running = _refreshing;
    if (running != null) {
      _again = true;
      return running;
    }
    return _refreshing = _refreshAgainWhileAsked().whenComplete(() => _refreshing = null);
  }

  Future<void> _refreshAgainWhileAsked() async {
    do {
      _again = false;
      await _doRefresh();
    } while (_again && state.busyRecipe == null);
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
        // Written here, so they win: somebody described this app's saves by
        // hand, which says more than any published copy can.
        final mine = await _store.loadUser(Directory(p.join(_paths.saveSync, 'recipes')));
        for (final r in mine.recipes) {
          _recipes[r.id] = (r, 'user');
        }
        problems = {...mine.rejected, ...load.rejected, for (final f in load.tooNew) f: 'needs a newer Retro Toolbox'};
      }
      // Recipes another hub published, and their problems, do not belong to this one.
      void leaveHub(String? id) {
        if (id == _hubId) return;
        _recipes.removeWhere((_, r) => r.$2 == 'hub');
        problems = {for (final e in problems.entries) if (!e.key.startsWith('hub: ')) e.key: e.value};
        _hubId = id;
      }

      // No place chosen yet is the only state with nothing to show. A device
      // with no privileged access still opens the hub, still reads the
      // configuration and still builds its rows: reading a hub needs no
      // privilege, and a screen that goes blank hides what the owner set up.
      if (choice == null) {
        leaveHub(null);
        state = state.copyWith(loading: false, games: const [], recipeProblems: problems);
        return;
      }
      final model = await _deviceModel();
      final deviceId = await sync.deviceId(model);
      final hub = Hub(_backend(choice));
      leaveHub(hub.backend.id);
      // Only the refresh that follows the owner choosing a place may make a
      // hub there. Every later one must fail on an empty listing instead of
      // minting a second hub over a card that is simply not in the slot.
      await hub.open(deviceId: deviceId, create: _creatingHub);
      _creatingHub = false;
      for (final e in (await hub.recipes()).entries) {
        final known = _recipes[e.key];
        if (known != null && known.$2 != 'hub') continue;
        try {
          _recipes[e.key] = (Recipe.parse(e.value.recipe), 'hub');
        } catch (err) {
          problems = {...problems, 'hub: ${e.key}': '$err'};
        }
      }
      var config = await hub.config();
      // The recipe body travels with the decision, so a device adopting this
      // configuration needs neither the network nor a catalog of its own.
      Future<void> publish(Iterable<String> packages) async {
        for (final (recipe, source) in _recipes.values) {
          if (source == 'hub' || !packages.contains(recipe.packages.first)) continue;
          try {
            await hub.publishRecipe(recipe.raw, source: source, deviceId: deviceId);
          } catch (_) {
            // A hub that will not take the body still carries the saves.
          }
        }
      }

      // Reading a hub needs no privilege, so a device with no access still
      // shows what the owner set up, every row blocked and saying why.
      if (shell == null) {
        state = state.copyWith(
          loading: false,
          recipeProblems: problems,
          games: [
            for (final (recipe, source) in _recipes.values)
              if (config.packages.contains(recipe.packages.first)) GameStatus(recipe, source, const NotInstalled()),
          ],
        );
        return;
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
      final all = await gameStatuses(_recipes.values, (r, source) => engine.status(r, source: source));
      // An existing hub has no configuration folder, and one nobody has added
      // apps to has nothing in it. Either way this device writes one from the
      // games it actually has, so the list it shows travels to the next
      // handheld instead of living only here.
      if (config.isEmpty) {
        final at = DateTime.now().toUtc();
        final adopt = {
          for (final g in all)
            if (g.bind is! NotInstalled) g.recipe.packages.first: ConfigEntry(recipe: g.recipe.id, updatedAt: at, by: deviceId),
        };
        if (adopt.isNotEmpty && await hub.putConfig(adopt, deviceId: deviceId, now: at)) config = await hub.config();
      }
      await publish(config.packages);
      // Membership is the configuration: a recipe the app happens to ship is
      // a candidate to add, not a row.
      final games = config.isEmpty ? all : [for (final g in all) if (config.packages.contains(g.recipe.packages.first)) g];
      // The engine is published with the games it produced: until then the catch below sees no engine and clears them.
      _engine = engine;
      // Settled here, once, and never in build: the list is rebuilt on every
      // icon that lands, and a sort that runs there would reorder rows under
      // the owner's thumb.
      games.sort((a, b) {
        final byRank = rowRank(rowStateFor(a, hasAccess: access != SyncAccess.none))
            .compareTo(rowRank(rowStateFor(b, hasAccess: access != SyncAccess.none)));
        return byRank != 0 ? byRank : a.recipe.name.toLowerCase().compareTo(b.recipe.name.toLowerCase());
      });
      // The rows go up first; the icons land on the frame after. A list that
      // waits for the package manager is a list that stutters.
      state = state.copyWith(loading: false, games: games, recipeProblems: problems);
      final info = await _loadAppInfo([for (final g in games) ...g.recipe.packages]);
      if (info.isNotEmpty) state = state.copyWith(appInfo: info);
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

  Future<void> push(String recipeId, {String? unit}) => _act(recipeId, (e, r, s) => e.push(r, source: s, only: unit));

  Future<void> pull(String recipeId, {String? unit}) => _act(recipeId, (e, r, s) => e.pull(r, source: s, only: unit));

  /// Which handhelds left a backup of this unit in the hub, newest name
  /// first. Empty when the hub is not open or nothing has been replaced yet.
  Future<List<({String device, String name, DateTime at})>> backupsFor(String recipeId, String unit) async {
    final engine = _engine;
    if (engine == null) return const [];
    final out = <({String device, String name, DateTime at})>[];
    for (final d in await engine.hub.backupDevices(recipeId, unit)) {
      final meta = await engine.hub.backup(d, recipeId, unit);
      if (meta != null) out.add((device: d, name: meta.deviceName, at: meta.createdAt));
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  /// Puts a backup back over what is here now.
  Future<void> restoreBackup(String recipeId, String unit, {required String fromDevice}) =>
      _act(recipeId, (e, r, s) => e.restoreBackup(r, unit, fromDevice: fromDevice, source: s));

  /// Settles a unit both sides changed by keeping one version.
  Future<void> resolve(String recipeId, String unit, {required String keep}) =>
      _act(recipeId, (e, r, s) => e.resolve(r, unit, keep: keep, source: s));

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
    _creatingHub = true;
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
      _creatingHub = true;
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
