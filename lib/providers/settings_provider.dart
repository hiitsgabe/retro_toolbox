import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_handler.dart';
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

    final base = getSetting(AppSettings.downloadDir, consoleId) ?? '';
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

  /// Saves [handler] (null = none) as [consoleId]'s choice over the catalog's.
  Future<void> setActiveHandler(String consoleId, GameHandler? handler) =>
      setConsoleSetting<String>(consoleId, AppSettings.additionalHandler, handler?.id ?? 'none');

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
    final updated = token.isEmpty
        ? current.copyWith(clearAuthToken: true)
        : current.copyWith(authToken: token);
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
