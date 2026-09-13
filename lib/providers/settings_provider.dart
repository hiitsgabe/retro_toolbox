import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.watch(vaultProvider.future).then((choice) => choice.vault));
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
  final Future<SecretVault> _vault;

  /// Resolves once the initial load has arrived from prefs and the vault.
  late final Future<void> ready;

  SettingsNotifier(this._vault) : super(const AppSettings()) {
    ready = _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings(await _vault);
    state = settings;
  }

  /// Swaps the state and saves.
  Future<void> _persist(AppSettings next) async {
    state = next;
    await _settingsService.saveSettings(next, await _vault);
  }

  Future<void> setGeneralSetting<T>(String key, T value) async {
    final newState = state.copyWith(
      generalSettings: state.generalSettings.setSetting(key, value),
    );
    await _persist(newState);
  }

  Future<void> setConsoleSetting<T>(String consoleId, String key, T? value) async {
    final currentConsoleSettings = state.consoleSettings[consoleId] ?? const BaseSettings();

    final newState = state.copyWith(
      consoleSettings: {
        ...state.consoleSettings,
        consoleId: currentConsoleSettings.setSetting(key, value),
      },
    );

    await _persist(newState);
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

  Future<String?> selectDownloadDirectory() async {
    return await _settingsService.selectDownloadDirectory();
  }

  /// Stores, or clears, the token for an (addon, console) pair.
  ///
  /// The `AppSettings.consoleSettings` mirror is written only for the builtin
  /// addon: mirroring a third-party token there would make a LAN server send
  /// one server's credential to another. Third-party tokens live only in the
  /// vault; read them on demand via [readAddonToken].
  Future<void> setAddonToken(String addonId, String consoleId, String token) async {
    await _settingsService.writeAddonToken(addonId, consoleId, token, await _vault);
    if (addonId != kBuiltinAddonId) return;

    final current = state.consoleSettings[consoleId] ?? const BaseSettings();
    final updated = token.isEmpty ? current.copyWith(clearAuthToken: true) : current.copyWith(authToken: token);
    await _persist(state.copyWith(
      consoleSettings: {...state.consoleSettings, consoleId: updated},
    ));
  }

  Future<String> readAddonToken(String addonId, String consoleId) async =>
      _settingsService.readAddonToken(addonId, consoleId, await _vault);

  /// The builtin-addon special case: writes the (builtin, console) pair.
  Future<void> setConsoleAuthToken(String consoleId, String token) => setAddonToken(kBuiltinAddonId, consoleId, token);

  /// The synchronous mirror of the builtin addon only. Returns `null` for a
  /// third-party addon even with a token in the vault; use `readAddonToken`.
  String? getConsoleAuthToken(String consoleId) {
    return state.consoleSettings[consoleId]?.authToken;
  }

  Future<void> setIaCredentials(String accessKey, String secretKey, {String? cookies}) async {
    final newState = state.copyWith(iaAccessKey: accessKey, iaSecretKey: secretKey, iaCookies: cookies);
    await _persist(newState);
  }

  Future<void> clearIaCredentials() async {
    await _settingsService.clearIaSecrets(await _vault);
    await _persist(state.copyWith(clearIaCredentials: true));
  }

  Future<void> setCatalogSourceUrl(String? url) async {
    final newState = url == null || url.isEmpty
        ? state.copyWith(clearCatalogSourceUrl: true)
        : state.copyWith(catalogSourceUrl: url);
    await _persist(newState);
  }

  bool getNszDecompressEnabled() => state.nszDecompressEnabled;

  String? getNszKeysPath() => state.nszKeysPath;

  Future<void> setNszDecompressEnabled(bool enabled) async {
    final newState = state.copyWith(nszDecompressEnabled: enabled);
    await _persist(newState);
  }

  Future<void> setNszKeysPath(String keysPath) async {
    final newState = state.copyWith(
      nszKeysPath: keysPath.isEmpty ? null : keysPath,
      clearNszKeysPath: keysPath.isEmpty,
    );
    await _persist(newState);
  }

  Future<void> setChdmanPath(String chdmanPath) async {
    final newState = state.copyWith(
      chdmanPath: chdmanPath.isEmpty ? null : chdmanPath,
      clearChdmanPath: chdmanPath.isEmpty,
    );
    await _persist(newState);
  }

  String? getBoot9Path() => state.boot9Path;

  Future<void> setBoot9Path(String path) async {
    final newState = state.copyWith(
      boot9Path: path.isEmpty ? null : path,
      clearBoot9Path: path.isEmpty,
    );
    await _persist(newState);
  }

  Future<void> setPreferredLocalIp(String? ip) async {
    final newState = state.copyWith(
      preferredLocalIp: (ip == null || ip.isEmpty) ? null : ip,
      clearPreferredLocalIp: ip == null || ip.isEmpty,
    );
    await _persist(newState);
  }
}
