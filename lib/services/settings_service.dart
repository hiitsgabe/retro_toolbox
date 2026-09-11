import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';

  /// O addon a que pertencem os consoles do catálogo de hoje.
  ///
  /// Enquanto existe uma fonte só, este id é constante. Quando houver N
  /// addons, este espelho continua sendo só do embutido, e o token dos outros
  /// passa a ser lido sob demanda no cofre (Task 19). Ele vive aqui, e não em
  /// [SecretRef], porque é fato sobre a instalação e não sobre o formato da
  /// chave.
  static const String builtinAddonId = 'builtin';

  final DirectoryService _directoryService = DirectoryService();

  Future<AppSettings> loadSettings(SecretVault vault) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);

      if (settingsJson != null) {
        final cru = jsonDecode(settingsJson) as Map<String, dynamic>;
        final limpo = await SecretMigration(vault: vault, builtinAddonId: builtinAddonId).drain(cru);

        // Só reescreve se a migração de fato tirou alguma coisa. A carga roda
        // em toda abertura do app; reescrever sempre é escrita em disco por
        // nada. A comparação é segura porque `drain` não mexe no mapa que
        // recebeu.
        final limpoJson = jsonEncode(limpo);
        if (limpoJson != jsonEncode(cru)) {
          await prefs.setString(_settingsKey, limpoJson);
        }

        final hidratado = await _hydrate(AppSettings.fromJson(limpo), vault);
        return hidratado;
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }

    final defaultDownloadDir = await _directoryService.getDownloadDir();
    return AppSettings(
      generalSettings: BaseSettings(downloadDir: defaultDownloadDir, autoExtract: true),
    );
  }

  /// Devolve as settings com os segredos postos de volta, vindos do cofre.
  ///
  /// Sem isto, a migração seria perda de dados: o app inteiro lê
  /// `settings.consoleSettings[id].authToken`, e ele acabou de sair do arquivo.
  Future<AppSettings> _hydrate(AppSettings settings, SecretVault vault) async {
    final consoles = <String, BaseSettings>{};
    for (final entrada in settings.consoleSettings.entries) {
      final token = await vault.read(SecretRef.addonToken(builtinAddonId, entrada.key));
      consoles[entrada.key] = token == null ? entrada.value : entrada.value.withAuthToken(token);
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
      await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  /// Grava o que existe e **não apaga o que está `null`**.
  ///
  /// Apagar aqui seria tentador e é errado: `SettingsNotifier` salva a partir
  /// de ação do usuário enquanto a carga ainda está no ar, e nesse instante o
  /// estado é `const AppSettings()`, tudo `null`. Salvar apagando transformaria
  /// um clique apressado no boot em perda de todas as credenciais, sem erro na
  /// tela. Quem apaga são [clearIaSecrets] e [clearConsoleToken], chamados de
  /// propósito.
  Future<void> _writeSecrets(AppSettings settings, SecretVault vault) async {
    await _writeIfPresent(vault, SecretRef.iaAccessKey, settings.iaAccessKey);
    await _writeIfPresent(vault, SecretRef.iaSecretKey, settings.iaSecretKey);
    await _writeIfPresent(vault, SecretRef.iaCookies, settings.iaCookies);
    for (final entrada in settings.consoleSettings.entries) {
      await _writeIfPresent(vault, SecretRef.addonToken(builtinAddonId, entrada.key), entrada.value.authToken);
    }
  }

  Future<void> _writeIfPresent(SecretVault vault, String chave, String? valor) async {
    if (valor == null || valor.isEmpty) return;
    await vault.write(chave, valor);
  }

  Future<void> clearIaSecrets(SecretVault vault) async {
    await vault.delete(SecretRef.iaAccessKey);
    await vault.delete(SecretRef.iaSecretKey);
    await vault.delete(SecretRef.iaCookies);
  }

  Future<void> clearConsoleToken(String consoleId, SecretVault vault) async {
    await vault.delete(SecretRef.addonToken(builtinAddonId, consoleId));
  }

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
