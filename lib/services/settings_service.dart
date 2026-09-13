import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

class SettingsService {
  /// The single key where the app stores its settings. Public because the
  /// addon migration (`addon_store.dart`) reads the pre-slice-4
  /// `catalogSourceUrl` from it.
  static const String settingsKey = 'app_settings';

  final DirectoryService _directoryService = DirectoryService();

  Future<AppSettings> loadSettings(SecretVault vault) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(settingsKey);

      if (settingsJson != null) {
        final raw = jsonDecode(settingsJson) as Map<String, dynamic>;
        final cleaned = await SecretMigration(vault: vault, builtinAddonId: kBuiltinAddonId).drain(raw);

        // Only rewrite when the migration actually removed something: load
        // runs on every app open.
        final cleanedJson = jsonEncode(cleaned);
        if (cleanedJson != jsonEncode(raw)) {
          await prefs.setString(settingsKey, cleanedJson);
        }

        return _hydrate(AppSettings.fromJson(cleaned), vault);
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }

    final defaultDownloadDir = await _directoryService.getDownloadDir();
    return AppSettings(
      generalSettings: BaseSettings(downloadDir: defaultDownloadDir, autoExtract: true),
    );
  }

  /// Returns the settings with secrets put back, read from the vault.
  Future<AppSettings> _hydrate(AppSettings settings, SecretVault vault) async {
    final consoles = <String, BaseSettings>{};
    for (final entry in settings.consoleSettings.entries) {
      final token = await vault.read(SecretRef.addonToken(kBuiltinAddonId, entry.key));
      consoles[entry.key] = token == null ? entry.value : entry.value.withAuthToken(token);
    }

    return settings.copyWith(
      consoleSettings: consoles,
      iaAccessKey: await vault.read(SecretRef.iaAccessKey),
      iaSecretKey: await vault.read(SecretRef.iaSecretKey),
      iaCookies: await vault.read(SecretRef.iaCookies),
    );
  }

  Future<void> saveSettings(AppSettings settings, SecretVault vault) async {
    try {
      await _writeSecrets(settings, vault);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(settingsKey, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  /// Writes what exists and does not delete what is `null`: a save triggered
  /// while the load is still in flight would otherwise wipe every credential.
  /// Deletion is [clearIaSecrets] and [writeAddonToken] with an empty value.
  Future<void> _writeSecrets(AppSettings settings, SecretVault vault) async {
    await _writeIfPresent(vault, SecretRef.iaAccessKey, settings.iaAccessKey);
    await _writeIfPresent(vault, SecretRef.iaSecretKey, settings.iaSecretKey);
    await _writeIfPresent(vault, SecretRef.iaCookies, settings.iaCookies);
    for (final entry in settings.consoleSettings.entries) {
      await _writeIfPresent(vault, SecretRef.addonToken(kBuiltinAddonId, entry.key), entry.value.authToken);
    }
  }

  Future<void> _writeIfPresent(SecretVault vault, String key, String? value) async {
    if (value == null || value.isEmpty) return;
    await vault.write(key, value);
  }

  Future<void> clearIaSecrets(SecretVault vault) async {
    await vault.delete(SecretRef.iaAccessKey);
    await vault.delete(SecretRef.iaSecretKey);
    await vault.delete(SecretRef.iaCookies);
  }

  /// The token for an (addon, console) pair in the vault. An empty value
  /// deletes.
  Future<void> writeAddonToken(String addonId, String consoleId, String token, SecretVault vault) async {
    final key = SecretRef.addonToken(addonId, consoleId);
    if (token.isEmpty) return vault.delete(key);
    return vault.write(key, token);
  }

  /// The pair's token, or an empty string. `null` becomes `''` here, once,
  /// because every caller asks `isEmpty`.
  Future<String> readAddonToken(String addonId, String consoleId, SecretVault vault) async =>
      await vault.read(SecretRef.addonToken(addonId, consoleId)) ?? '';

  T? getGeneralSetting<T>(AppSettings settings, String key) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    return settings.generalSettings.getSetting<T>(key);
  }

  T? getConsoleSetting<T>(AppSettings settings, String consoleId, String key) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    return settings.consoleSettings[consoleId]?.getSetting<T>(key);
  }

  T? getSetting<T>(AppSettings settings, String key, [String? consoleId]) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    if (consoleId != null) {
      final consoleValue = getConsoleSetting<T>(settings, consoleId, key);
      if (consoleValue != null) return consoleValue;
    }
    return getGeneralSetting<T>(settings, key);
  }

  Future<String?> selectDownloadDirectory() async {
    return await _directoryService.selectDownloadDirectory();
  }
}
