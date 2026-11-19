import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/catalog_source.dart';
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
import 'package:retro_toolbox/services/save_sync/title_catalog.dart';

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
    this.titles = const {},
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

  /// Title id to what it is called. Loaded only when a recipe covers more
  /// than one save, since only an emulator names its folders after a console's
  /// own ids.
  final Map<String, TitleInfo> titles;

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
    Map<String, TitleInfo>? titles,
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
        titles: titles ?? this.titles,
        recipeProblems: recipeProblems ?? this.recipeProblems,
        busyRecipe: clearBusy ? null : (busyRecipe ?? this.busyRecipe),
        messages: messages ?? this.messages,
        error: clearError ? null : (error ?? this.error),
      );
}

final saveSyncProvider = StateNotifierProvider<SaveSyncNotifier, SaveSyncState>((ref) => SaveSyncNotifier());

/// Whether this build has Save Sync (Android only, as the Tools menu gates
/// it). A provider so Settings can be tested with it either way.
final saveSyncAvailableProvider = Provider<bool>((ref) => Platform.isAndroid);

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
  SaveSyncNotifier({
    DevicePaths paths = const DevicePaths(),
    RecipeStore? store,
    GoogleAuth? google,
    DriveTransport? driveTransport,
    RecipeIndex Function(String base)? catalogIndex,
  })  : _paths = paths,
        _store = store ?? const RecipeStore(),
        _google = google ?? PluginGoogleAuth(),
        _transport = driveTransport,
        _catalogIndex = catalogIndex,
        super(const SaveSyncState());

  final DevicePaths _paths;
  final RecipeStore _store;
  final GoogleAuth _google;

  /// Tests hand in their own catalog; null builds the real one.
  final RecipeIndex Function(String base)? _catalogIndex;
  DriveTransport? _transport;
  SaveSyncEngine? _engine;

  /// The backend id the hub recipes in [_recipes] came from.
  String? _hubId;

  /// The catalog base the repo recipes in [_recipes] came from.
  String? _repoBase;

  /// Recipe id to (recipe, source).
  final _recipes = <String, (Recipe, String)>{};

  static const _native = MethodChannel('retrotoolbox/native');

  /// Icons and labels for this process's life. The same [AppInfo] instance is
  /// handed back every time, so the list decodes each PNG once instead of once
  /// per rebuild. Packages that answered with nothing are remembered too, so a
  /// game the device cannot show is not asked about on every refresh.
  static final _appInfo = <String, AppInfo?>{};

  static const _define = String.fromEnvironment('SAVE_SYNC_CATALOG_URL');

  RecipeIndex? _index;
  String? _indexBase;

  /// The owner's recipe source, or null when the default is in use.
  Future<String?> catalogSetting() async => (await _sync()).catalogUrl;

  /// Where recipes are read from right now.
  Future<String> catalogBase() async => resolveCatalogBase(setting: await catalogSetting(), define: _define);

  /// Makes [url] the recipe source; null goes back to the default. False,
  /// storing nothing, for a value that is not an https address.
  Future<bool> setCatalogSetting(String? url) async {
    final normalized = url == null ? null : normalizeCatalogUrl(url);
    if (url != null && normalized == null) return false;
    await (await _sync()).setCatalogUrl(normalized);
    // The refresh sees the new base and drops what the old source brought.
    await refresh();
    return true;
  }

  /// The catalog reader for the current source, rebuilt when the source changes.
  Future<RecipeIndex> _openIndex() async {
    final base = await catalogBase();
    final open = _index;
    if (open != null && _indexBase == base) return open;
    final make = _catalogIndex;
    final index = make != null ? make(base) : RecipeIndex(baseUrl: base, cacheDir: catalogCacheDir((await getApplicationSupportDirectory()).path, base));
    // Set together after the last await, so a caller never sees one base's
    // reader filed under another base.
    _index = index;
    _indexBase = base;
    return index;
  }

  /// The published catalog, for the picker. Null only when there is no place
  /// to keep it (no support directory), which changes what the picker can
  /// offer and nothing else.
  Future<RecipeCatalog?> catalog() async {
    try {
      return await (await _openIndex()).load();
    } catch (_) {
      return null;
    }
  }

  /// The catalog's recipe for each chosen app it publishes, each body
  /// matching the index's sha256. [chosen] is the hub configuration, package
  /// to entry; removed apps are skipped, and so is a catalog recipe whose id
  /// is not the one the configuration names. Ids a recipe written here
  /// already owns are skipped. A catalog that cannot be read gives nothing
  /// and no error: the hub still carries the bodies.
  Future<({Map<String, Recipe> recipes, Map<String, String> problems})> _repoRecipes(Map<String, ConfigEntry> chosen) async {
    final recipes = <String, Recipe>{};
    final problems = <String, String>{};
    try {
      final index = await _openIndex();
      final published = await index.load();
      for (final MapEntry(key: pkg, value: wanted) in chosen.entries) {
        if (wanted.removed) continue;
        final entry = published.byPackage[pkg];
        if (entry == null || (wanted.recipe != null && wanted.recipe != entry.id)) continue;
        if (recipes.containsKey(entry.id) || _recipes[entry.id]?.$2 == 'user') continue;
        final body = await index.ensureBody(entry);
        if (body == null) continue;
        try {
          recipes[entry.id] = Recipe.parse(body);
        } on RecipeTooNew {
          problems['repo: ${entry.id}'] = 'needs a newer Retro Toolbox';
        } catch (e) {
          problems['repo: ${entry.id}'] = '$e';
        }
      }
    } catch (_) {
      // No support directory or no network: the hub still has the bodies.
    }
    return (recipes: recipes, problems: problems);
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

  /// Package to the recipe this app already knows for it, whatever layer it
  /// came from. The picker needs this: an app a hub or the catalog already
  /// brought a recipe for must not read as one nothing has been written for.
  Map<String, String> get knownRecipeByPackage => {
        for (final (recipe, _) in _recipes.values)
          for (final pkg in recipe.packages) pkg: recipe.id,
      };

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
  ///
  /// A recipe only the catalog has is downloaded first, so its row appears at
  /// once. One that cannot be downloaded or does not parse stops the whole
  /// add, writes nothing, and comes back as the reason.
  Future<String?> addApps(Map<String, String?> packageToRecipe) async {
    if (packageToRecipe.isEmpty) return null;
    final fetched = <String, Recipe>{};
    RecipeCatalog? published;
    for (final e in packageToRecipe.entries) {
      final id = e.value;
      if (id == null || _recipes.containsKey(id)) continue;
      published ??= await catalog();
      final entry = published?.byPackage[e.key];
      if (entry == null || entry.id != id) continue;
      final body = await (await _openIndex()).ensureBody(entry);
      if (body == null) return 'Could not download the recipe for ${e.key}';
      try {
        fetched[id] = Recipe.parse(body);
      } catch (err) {
        return 'The recipe for ${e.key} is not valid: $err';
      }
    }
    final opened = await openHub();
    if (opened == null) return null;
    final (:hub, :deviceId) = opened;
    for (final e in fetched.entries) {
      _recipes[e.key] = (e.value, 'repo');
    }
    final at = DateTime.now().toUtc();
    await hub.putConfig(
      {for (final e in packageToRecipe.entries) e.key: ConfigEntry(recipe: e.value, updatedAt: at, by: deviceId)},
      deviceId: deviceId,
      now: at,
    );
    await refresh();
    return null;
  }

  /// The hub this device chose, opened, and this device's id in it. Null when
  /// no hub is chosen yet. Never creates one: that is the owner's pick only.
  Future<({Hub hub, String deviceId})?> openHub() async {
    final sync = await _sync();
    final choice = sync.hubChoice;
    if (choice == null) return null;
    final deviceId = await sync.deviceId(await _deviceModel());
    final hub = Hub(_backend(choice));
    await hub.open(deviceId: deviceId);
    return (hub: hub, deviceId: deviceId);
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
      // Written here, so they win: somebody described this app's saves by
      // hand, which says more than any published copy can. Read every
      // refresh, since the recipe wizard writes here while the app runs.
      final mine = await _store.loadUser(Directory(p.join(_paths.saveSync, 'recipes')));
      for (final r in mine.recipes) {
        _recipes[r.id] = (r, 'user');
      }
      problems = {
        for (final e in problems.entries)
          if (e.key.startsWith('hub: ') || e.key.startsWith('repo: ')) e.key: e.value,
        ...mine.rejected,
        for (final f in mine.tooNew) f: 'needs a newer Retro Toolbox',
      };
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
      // Recipes another source published, and their problems, do not belong
      // to this one. Checked here rather than when the setting changes, so a
      // refresh already running cannot bring the old source's back.
      final base = await catalogBase();
      if (base != _repoBase) {
        _recipes.removeWhere((_, r) => r.$2 == 'repo');
        problems = {for (final e in problems.entries) if (!e.key.startsWith('repo: ')) e.key: e.value};
        _repoBase = base;
      }
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
      // The catalog's copy of every chosen app's recipe, matching its index.
      // A device that upgraded from a build that bundled the recipe has only
      // the hub's older copy and must not stay on it. Collected first and
      // applied here, so a slow catalog that times out changes nothing later.
      final repo = await _repoRecipes(config.entries).timeout(
        const Duration(seconds: 20),
        onTimeout: () => (recipes: const <String, Recipe>{}, problems: const <String, String>{}),
      );
      for (final e in repo.recipes.entries) {
        if (_recipes[e.key]?.$2 != 'user') _recipes[e.key] = (e.value, 'repo');
      }
      problems = {
        for (final e in problems.entries)
          if (!e.key.startsWith('repo: ')) e.key: e.value,
        ...repo.problems,
      };
      // The recipe body travels with the decision, so a device adopting this
      // configuration needs neither the network nor a catalog of its own.
      Future<void> publish(Iterable<String> packages) async {
        // A snapshot: an add can put a recipe in while this awaits the hub.
        for (final (recipe, source) in _recipes.values.toList()) {
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
            for (final (recipe, source) in _recipes.values.toList())
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
      final all = await gameStatuses(_recipes.values.toList(), (r, source) => engine.status(r, source: source));
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
      // Membership is the configuration: a recipe this device knows, from
      // the catalog, the hub or written here, is a candidate to add, not a row.
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
      // Same again for the ids inside an emulator: the rows are already up, and
      // a list where every recipe holds one save never pays for the catalog.
      if (games.any((g) => g.units.length > 1)) {
        final titles = await TitleCatalog.load();
        if (titles.isNotEmpty && mounted) state = state.copyWith(titles: titles);
      }
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

  /// Reads only which hub is chosen (and its Google account), without the
  /// shell and game scan of [refresh]: enough for Settings to say who is
  /// signed in.
  Future<void> loadHub() async {
    try {
      final choice = (await _sync()).hubChoice;
      state = state.copyWith(
        hubKind: switch (choice) {
          null => HubKind.none,
          FolderHub() => HubKind.folder,
          DriveHub() => HubKind.drive,
        },
        hubFolder: choice is FolderHub ? choice.path : '',
        googleEmail: choice is DriveHub ? choice.email : '',
        googleAvailable: _google.available,
      );
    } catch (e) {
      debugPrint('Save Sync hub read failed: $e');
    }
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
