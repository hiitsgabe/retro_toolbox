import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

Future<SharedPreferences> _prefsCom(Map<String, Object> valores) async {
  SharedPreferences.setMockInitialValues(valores);
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

String _appSettings({String? iaAccessKey, String? authTokenSnes}) {
  return jsonEncode({
    'consoleSettings': {
      'snes': {
        'downloadDir': '/roms/snes',
        if (authTokenSnes != null) 'authToken': authTokenSnes,
      },
    },
    'generalSettings': {'downloadDir': '/home/joao/roms'},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    'nszDecompressEnabled': true,
  });
}

String _chaveDoSnes() => SecretRef.addonToken(SettingsService.builtinAddonId, 'snes');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('carregar tira o segredo do arquivo e o põe no cofre', () async {
    await _prefsCom({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});
    final vault = MemoryVault();

    await SettingsService().loadSettings(vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_chaveDoSnes()), 'tok-snes');
  });

  test('carregar devolve as settings com o segredo, lido do cofre', () async {
    // O app inteiro lê `settings.consoleSettings[id].authToken`. Se a carga
    // drenasse sem reidratar, a migração apagaria o login de todo mundo na
    // primeira abertura depois da atualização.
    await _prefsCom({'app_settings': _appSettings(authTokenSnes: 'tok-snes')});

    final settings = await SettingsService().loadSettings(MemoryVault());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('carregar reescreve o app_settings sem o segredo', () async {
    final prefs = await _prefsCom({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});

    await SettingsService().loadSettings(MemoryVault());

    final salvo = prefs.getString('app_settings')!;
    expect(salvo, isNot(contains('AK')));
    expect(salvo, isNot(contains('tok-snes')));
    expect(salvo, contains('/roms/snes'));
  });

  test('carregar não reescreve o app_settings quando não havia segredo', () async {
    // A carga roda em toda abertura. Reescrever sempre é escrita em disco por
    // nada. ATENÇÃO ao que este caso tranca e ao que não tranca: ele compara o
    // conteúdo, e quando não há segredo o JSON limpo é idêntico ao cru, então
    // ele fica verde tanto para "não reescreveu" quanto para "reescreveu igual".
    // Medido por mutação: tirar o `if` de `settings_service.dart:38` não o
    // derruba. Trancar o ato de escrever exigiria injetar o `SharedPreferences`
    // no `SettingsService`, que hoje o chama direto; está anotado para a fatia 5.
    final semSegredo = _appSettings();
    final prefs = await _prefsCom({'app_settings': semSegredo});

    await SettingsService().loadSettings(MemoryVault());

    expect(prefs.getString('app_settings'), semSegredo);
  });

  test('salvar grava o segredo no cofre', () async {
    await _prefsCom({'app_settings': _appSettings()});
    final vault = MemoryVault();
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_chaveDoSnes()), 'tok-snes');
  });

  test('salvar não escreve segredo dentro do app_settings', () async {
    final prefs = await _prefsCom({'app_settings': _appSettings()});
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, MemoryVault());

    expect(prefs.getString('app_settings'), isNot(contains('AK')));
    expect(prefs.getString('app_settings'), isNot(contains('tok-snes')));
  });

  test('salvar NÃO apaga do cofre o que está null nas settings', () async {
    // A corrida real: `SettingsNotifier` salva a partir de ação do usuário
    // enquanto a carga ainda está no ar, e nesse instante o estado é
    // `const AppSettings()`, tudo null. Se salvar apagasse o que está null, um
    // clique apressado no boot levaria todas as credenciais junto, sem erro
    // nenhum na tela. Apagar é operação explícita, e tem método próprio.
    await _prefsCom({'app_settings': _appSettings()});
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(_chaveDoSnes(), 'tok-snes');

    await SettingsService().saveSettings(const AppSettings(), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_chaveDoSnes()), 'tok-snes');
  });

  test('apagar as credenciais do IA leva as três', () async {
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(SecretRef.iaSecretKey, 'SK');
    await vault.write(SecretRef.iaCookies, 'logged-in-sig=xyz');

    await SettingsService().clearIaSecrets(vault);

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
    expect(await vault.read(SecretRef.iaSecretKey), isNull);
    expect(await vault.read(SecretRef.iaCookies), isNull);
  });

  test('apagar o token de um console não leva o do vizinho', () async {
    final vault = MemoryVault();
    await vault.write(_chaveDoSnes(), 'tok-snes');
    await vault.write(SecretRef.addonToken(SettingsService.builtinAddonId, 'n64'), 'tok-n64');

    await SettingsService().clearConsoleToken('snes', vault);

    expect(await vault.read(_chaveDoSnes()), isNull);
    expect(await vault.read(SecretRef.addonToken(SettingsService.builtinAddonId, 'n64')), 'tok-n64');
  });
}
