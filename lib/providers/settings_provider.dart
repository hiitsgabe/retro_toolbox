import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/settings_service.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});

final settingProvider = Provider.family<dynamic, ({String key, String? consoleId})>((ref, params) {
  final settings = ref.watch(settingsProvider);
  if (params.consoleId != null) {
    return settings.consoleSettings[params.consoleId]?.getSetting(params.key) ?? settings.generalSettings.getSetting(params.key);
  }
  return settings.generalSettings.getSetting(params.key);
});

final settingWatcherProvider = Provider.family<Map<String, dynamic>, String>((ref, key) {
  final settings = ref.watch(settingsProvider);
  final result = <String, dynamic>{};

  result['general'] = settings.generalSettings.getSetting(key);

  for (final entry in settings.consoleSettings.entries) {
    result[entry.key] = entry.value.getSetting(key);
  }

  return result;
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _settingsService = SettingsService();

  /// Completes once saved settings are in [state]; until then getters return
  /// defaults (empty download dir, NSZ off).
  late final Future<void> loaded;

  SettingsNotifier() : super(const AppSettings()) {
    loaded = _loadSettings();
  }

  Future<void> _loadSettings() async {
    var settings = await _settingsService.loadSettings();
    if (settings.libraryEnabled == null) {
      // First run of a version with the opt-in: keep the library for anyone
      // who already set up a catalog. A catalog bundled in the build doesn't count.
      final hasCatalog = await CatalogService().hasUserCatalog().catchError((_) => false);
      settings = settings.copyWith(libraryEnabled: hasCatalog);
      await _settingsService.saveSettings(settings);
    }
    if (mounted) state = settings;
  }

  Future<void> setLibraryEnabled(bool enabled) async {
    final newState = state.copyWith(libraryEnabled: enabled);
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  /// Extra console servers (Settings → Extra servers): each one's switch
  /// gates its Servers-menu tile. [id] is 'tinfoil', 'fbi' or 'fpkgi'.
  Future<void> setExtraServerEnabled(String id, bool enabled) async {
    final newState = switch (id) {
      'tinfoil' => state.copyWith(tinfoilEnabled: enabled),
      'fbi' => state.copyWith(fbiEnabled: enabled),
      'fpkgi' => state.copyWith(fpkgiEnabled: enabled),
      _ => state,
    };
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> setGeneralSetting<T>(String key, T value) async {
    final newState = state.copyWith(
      generalSettings: state.generalSettings.setSetting(key, value),
    );
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> setConsoleSetting<T>(String consoleId, String key, T? value) async {
    final currentConsoleSettings = state.consoleSettings[consoleId] ?? const BaseSettings();

    final newState = state.copyWith(
      consoleSettings: {
        ...state.consoleSettings,
        consoleId: currentConsoleSettings.setSetting(key, value),
      },
    );

    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> setSetting<T>(String key, T value, [String? consoleId]) async {
    if (consoleId != null) {
      await setConsoleSetting(consoleId, key, value);
    } else {
      await setGeneralSetting(key, value);
    }
  }

  /// The settings a console can change from the general ones, in the order
  /// its page shows them.
  static const consoleKeys = [
    AppSettings.downloadDir,
    AppSettings.autoExtract,
    AppSettings.extractToFolder,
    AppSettings.groupDiscs,
    AppSettings.downloadAllDiscs,
    AppSettings.additionalHandler,
    AppSettings.chdIsoAsCd,
    AppSettings.updatesDir,
    AppSettings.updateDecompress,
    AppSettings.updateHandler,
  ];

  /// What [key] (an on/off setting) is for [consoleId] when the console does
  /// not change it: the general setting, else its default.
  bool generalBool(String key, String consoleId) => switch (key) {
        AppSettings.autoExtract => getGeneralSetting<bool>(key) ?? true,
        AppSettings.extractToFolder => getGeneralSetting<bool>(key) ?? !(CatalogService.consoleByIdSync(consoleId)?.extractContents ?? true),
        AppSettings.groupDiscs => getGeneralSetting<bool>(key) ?? false,
        AppSettings.downloadAllDiscs => getGeneralSetting<bool>(key) ?? true,
        AppSettings.chdIsoAsCd => false,
        _ => throw ArgumentError('Not an on/off console setting: $key'),
      };

  /// The handler [consoleId] runs when it does not choose one: the catalog's.
  GameHandler? defaultHandler(String consoleId) => resolveActiveHandler(
        saved: null,
        jsonDefault: CatalogService.consoleByIdSync(consoleId)?.additionalHandler,
        nszEnabled: state.nszDecompressEnabled,
      );

  /// The [consoleKeys] [consoleId] changes, in that order. A value the console
  /// saved counts only when it differs from what it would get anyway: older
  /// versions saved the defaults with every change, and those change nothing.
  List<String> changedKeys(String consoleId) {
    final own = state.consoleSettings[consoleId];
    if (own == null) return const [];
    final changed = <String>[];
    for (final key in consoleKeys) {
      final bool differs;
      switch (key) {
        case AppSettings.downloadDir:
          differs = own.downloadDir?.isNotEmpty ?? false;
        case AppSettings.additionalHandler:
          differs = own.additionalHandler != null && activeHandler(consoleId) != defaultHandler(consoleId);
        case AppSettings.chdIsoAsCd:
          differs = own.chdIsoAsCd == true && activeHandler(consoleId) == GameHandler.chdCompress;
        case AppSettings.updatesDir:
          differs = own.updatesDir?.isNotEmpty ?? false;
        case AppSettings.updateDecompress:
          differs = own.updateDecompress != null;
        case AppSettings.updateHandler:
          differs = own.updateHandler != null;
        default:
          final v = own.getSetting<bool>(key);
          differs = v != null && v != generalBool(key, consoleId);
      }
      if (differs) changed.add(key);
    }
    return changed;
  }

  /// [consoleId] follows the general [key] again.
  Future<void> resetConsoleSetting(String consoleId, String key) => resetConsoleSettings(consoleId, [key]);

  /// [consoleId] follows the general setting again for each of [keys].
  Future<void> resetConsoleSettings(String consoleId, Iterable<String> keys) async {
    var own = state.consoleSettings[consoleId];
    if (own == null) return;
    for (final key in keys) {
      own = own!.cleared(key);
    }
    final newState = state.copyWith(consoleSettings: {...state.consoleSettings, consoleId: own!});
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  T? getGeneralSetting<T>(String key) {
    return _settingsService.getGeneralSetting<T>(state, key);
  }

  T? getConsoleSetting<T>(String consoleId, String key) {
    return _settingsService.getConsoleSetting<T>(state, consoleId, key);
  }

  T? getSetting<T>(String key, [String? consoleId]) {
    return _settingsService.getSetting<T>(state, key, consoleId);
  }

  String getDownloadDir(String? consoleId) {
    // A console-specific directory override is used exactly as chosen;
    // roms_folder only nests under the general download directory.
    final override = consoleId != null ? getConsoleSetting<String>(consoleId, AppSettings.downloadDir) : null;
    if (override != null && override.isNotEmpty) return override;
    return defaultDownloadDir(consoleId);
  }

  /// Where [consoleId]'s games go when it does not choose a folder: the
  /// general download folder, with the console's roms_folder under it.
  String defaultDownloadDir(String? consoleId) {
    final base = getGeneralSetting<String>(AppSettings.downloadDir) ?? '';
    final romsFolder = CatalogService.consoleByIdSync(consoleId)?.romsFolder;
    if (base.isEmpty || romsFolder == null || romsFolder.isEmpty) return base;
    return p.join(base, romsFolder);
  }

  /// The handler that runs after a download for [consoleId], if any.
  GameHandler? activeHandler(String consoleId) => resolveActiveHandler(
        saved: getConsoleSetting<String>(consoleId, AppSettings.additionalHandler),
        jsonDefault: CatalogService.consoleByIdSync(consoleId)?.additionalHandler,
        nszEnabled: state.nszDecompressEnabled,
      );

  /// Whether [consoleId]'s CHD handler packs an .iso as a CD CHD (default: DVD).
  bool chdIsoAsCd(String consoleId) => getConsoleSetting<bool>(consoleId, AppSettings.chdIsoAsCd) ?? false;

  Future<void> setChdIsoAsCd(String consoleId, bool value) =>
      setConsoleSetting<bool>(consoleId, AppSettings.chdIsoAsCd, value);

  /// Where [consoleId]'s updates go when it does not choose a folder: a
  /// folder named updates in its download folder.
  String defaultUpdatesDir(String consoleId) {
    final base = getDownloadDir(consoleId);
    return base.isEmpty ? '' : p.join(base, 'updates');
  }

  /// Where [consoleId]'s updates go.
  String updatesDir(String consoleId) {
    final own = getConsoleSetting<String>(consoleId, AppSettings.updatesDir);
    return own != null && own.isNotEmpty ? own : defaultUpdatesDir(consoleId);
  }

  /// The folder [game] downloads to: its console's, or the updates folder.
  String downloadDirFor(Game game) => game.isUpdate ? updatesDir(game.consoleId) : getDownloadDir(game.consoleId);

  /// How [game] is unpacked after its download.
  Decompress decompressFor(Game game) {
    final catalog = CatalogService.consoleByIdSync(game.consoleId)?.decompress ?? Decompress.none;
    if (!game.isUpdate) return catalog;
    return resolveUpdateDecompress(getConsoleSetting<String>(game.consoleId, AppSettings.updateDecompress), catalog);
  }

  /// The handler that runs after [game]'s download, if any.
  GameHandler? activeHandlerFor(Game game) {
    final handler = activeHandler(game.consoleId);
    if (!game.isUpdate) return handler;
    return resolveUpdateHandler(getConsoleSetting<String>(game.consoleId, AppSettings.updateHandler), handler);
  }

  /// An update's unpacking: [game]'s unless [saved] (a Decompress name) says.
  static Decompress resolveUpdateDecompress(String? saved, Decompress game) => saved == null ? game : Decompress.fromId(saved);

  /// An update's handler: [game]'s unless [saved] says ('none': nothing).
  static GameHandler? resolveUpdateHandler(String? saved, GameHandler? game) =>
      saved == null ? game : (saved == 'none' ? null : GameHandler.fromId(saved));

  /// Saves [handler] (null = none) as [consoleId]'s choice over the catalog's.
  Future<void> setActiveHandler(String consoleId, GameHandler? handler) =>
      setConsoleSetting<String>(consoleId, AppSettings.additionalHandler, handler?.id ?? 'none');

  /// Whether [consoleId]'s list shows a multi-disc game as one entry.
  bool groupDiscs(String? consoleId) => getSetting<bool>(AppSettings.groupDiscs, consoleId) ?? false;

  /// Whether Download on a grouped game gets all its discs.
  bool downloadAllDiscs(String? consoleId) => getSetting<bool>(AppSettings.downloadAllDiscs, consoleId) ?? true;

  bool getAutoExtract(String? consoleId) {
    return getSetting(AppSettings.autoExtract, consoleId) ?? true;
  }

  /// When true, archives extract into a per-game subfolder. Defaults to the
  /// console config's extract_contents (true = extract into the download
  /// directory root, matching console_utils semantics).
  bool getExtractToFolder(String? consoleId) {
    final explicit = getSetting<bool>(AppSettings.extractToFolder, consoleId);
    if (explicit != null) return explicit;
    return !(CatalogService.consoleByIdSync(consoleId)?.extractContents ?? true);
  }

  int getMaxParallelDownloads() {
    return getGeneralSetting(AppSettings.maxParallelDownloads) ?? 5;
  }

  int getMaxParallelExtractions() {
    return getGeneralSetting(AppSettings.maxParallelExtractions) ?? 2;
  }

  Future<void> saveDownloadDirectory(String dir) => _settingsService.saveDownloadDirectory(dir);

  Future<void> setConsoleAuthToken(String consoleId, String token) async {
    final current = state.consoleSettings[consoleId] ?? const BaseSettings();
    // Not copyWith: it would pin this console's extraction to a default.
    final updated = BaseSettings.fromJson({...current.toJson(), 'authToken': token.isEmpty ? null : token});
    final newState = state.copyWith(
      consoleSettings: {...state.consoleSettings, consoleId: updated},
    );
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  String? getConsoleAuthToken(String consoleId) {
    return state.consoleSettings[consoleId]?.authToken;
  }

  Future<void> setIaCredentials(String accessKey, String secretKey, {String? cookies}) async {
    final newState = state.copyWith(iaAccessKey: accessKey, iaSecretKey: secretKey, iaCookies: cookies);
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> clearIaCredentials() async {
    final newState = state.copyWith(clearIaCredentials: true);
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> setCatalogSourceUrl(String? url) async {
    final newState = url == null || url.isEmpty
        ? state.copyWith(clearCatalogSourceUrl: true)
        : state.copyWith(catalogSourceUrl: url);
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  String? getNszKeysPath() => state.nszKeysPath;

  Future<void> setUseOnScreenKeyboard(bool enabled) async {
    final newState = state.copyWith(useOnScreenKeyboard: enabled);
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> setNszKeysPath(String keysPath) async {
    final newState = state.copyWith(
      nszKeysPath: keysPath.isEmpty ? null : keysPath,
      clearNszKeysPath: keysPath.isEmpty,
    );
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> setChdmanPath(String chdmanPath) async {
    final newState = state.copyWith(
      chdmanPath: chdmanPath.isEmpty ? null : chdmanPath,
      clearChdmanPath: chdmanPath.isEmpty,
    );
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  String? getBoot9Path() => state.boot9Path;

  Future<void> setBoot9Path(String path) async {
    final newState = state.copyWith(
      boot9Path: path.isEmpty ? null : path,
      clearBoot9Path: path.isEmpty,
    );
    state = newState;
    await _settingsService.saveSettings(newState);
  }

  Future<void> setPreferredLocalIp(String? ip) async {
    final newState = state.copyWith(
      preferredLocalIp: (ip == null || ip.isEmpty) ? null : ip,
      clearPreferredLocalIp: ip == null || ip.isEmpty,
    );
    state = newState;
    await _settingsService.saveSettings(newState);
  }
}
