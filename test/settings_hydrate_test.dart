import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// Arquivo de quem configurou o geral e **não** configurou o console.
///
/// `autoExtract: false` no geral é o que torna o defeito visível: se a
/// hidratação inventar `autoExtract: true` no console, o console passa a
/// ganhar do geral, porque `getSetting` consulta o console primeiro.
String _arquivo() => jsonEncode({
      'consoleSettings': {
        'snes': {'downloadDir': '/roms/snes'},
      },
      'generalSettings': {'downloadDir': '/casa/roms', 'autoExtract': false, 'maxParallelDownloads': 10},
    });

Future<void> _prefsCom(String appSettings) async {
  SharedPreferences.setMockInitialValues({'app_settings': appSettings});
  SharedPreferences.resetStatic();
}

Future<SecretVault> _cofreComTokenDoSnes() async {
  final vault = MemoryVault();
  await vault.write(SecretRef.addonToken(kBuiltinAddonId, 'snes'), 'tok-snes');
  return vault;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('o console com token no cofre não ganha `autoExtract` que ninguém pediu', () async {
    await _prefsCom(_arquivo());

    final settings = await SettingsService().loadSettings(await _cofreComTokenDoSnes());

    expect(settings.consoleSettings['snes']?.autoExtract, isNull);
    expect(SettingsService().getSetting<bool>(settings, AppSettings.autoExtract, 'snes'), isFalse);
  });

  test('o console com token no cofre não ganha os dois limites de paralelismo', () async {
    await _prefsCom(_arquivo());

    final settings = await SettingsService().loadSettings(await _cofreComTokenDoSnes());

    expect(settings.consoleSettings['snes']?.maxParallelDownloads, isNull);
    expect(settings.consoleSettings['snes']?.maxParallelExtractions, isNull);
    expect(SettingsService().getSetting<int>(settings, AppSettings.maxParallelDownloads, 'snes'), 10);
  });

  test('a hidratação continua entregando o token e o que o usuário configurou', () async {
    // O controle. Sem ele, apagar a hidratação inteira faria os dois casos de
    // cima passarem, e eles são asserções sobre ausência.
    await _prefsCom(_arquivo());

    final settings = await SettingsService().loadSettings(await _cofreComTokenDoSnes());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('salvar com segredo vazio não apaga o que está no cofre', () async {
    // A guarda `valor.isEmpty` de `_writeIfPresent`. Sem ela, `vault.write`
    // com string vazia vira `delete` (`secret_vault.dart:38-41`), e um
    // salvamento comum apagaria a credencial.
    await _prefsCom(_arquivo());
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');

    await SettingsService().saveSettings(const AppSettings(iaAccessKey: ''), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
  });
}
