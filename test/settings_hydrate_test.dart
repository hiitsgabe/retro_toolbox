import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// A file where the general settings are configured and the console is not.
/// `autoExtract: false` in the general block makes the defect visible: if
/// hydration invents `autoExtract: true` on the console, the console wins.
String _file() => jsonEncode({
      'consoleSettings': {
        'snes': {'downloadDir': '/roms/snes'},
      },
      'generalSettings': {'downloadDir': '/home/user/roms', 'autoExtract': false, 'maxParallelDownloads': 10},
    });

Future<void> _prefsWith(String appSettings) async {
  SharedPreferences.setMockInitialValues({'app_settings': appSettings});
  SharedPreferences.resetStatic();
}

Future<SecretVault> _vaultWithSnesToken() async {
  final vault = MemoryVault();
  await vault.write(SecretRef.addonToken(kBuiltinAddonId, 'snes'), 'tok-snes');
  return vault;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hydrating a console token does not inject autoExtract', () async {
    await _prefsWith(_file());

    final settings = await SettingsService().loadSettings(await _vaultWithSnesToken());

    expect(settings.consoleSettings['snes']?.autoExtract, isNull);
    expect(SettingsService().getSetting<bool>(settings, AppSettings.autoExtract, 'snes'), isFalse);
  });

  test('hydrating a console token does not inject parallelism limits', () async {
    await _prefsWith(_file());

    final settings = await SettingsService().loadSettings(await _vaultWithSnesToken());

    expect(settings.consoleSettings['snes']?.maxParallelDownloads, isNull);
    expect(settings.consoleSettings['snes']?.maxParallelExtractions, isNull);
    expect(SettingsService().getSetting<int>(settings, AppSettings.maxParallelDownloads, 'snes'), 10);
  });

  test('hydration still delivers the token and the configured values', () async {
    // Control: without it, deleting all hydration would pass the two
    // absence assertions above.
    await _prefsWith(_file());

    final settings = await SettingsService().loadSettings(await _vaultWithSnesToken());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('saving an empty secret does not erase what is in the vault', () async {
    // `vault.write` with an empty string deletes, so the empty-value guard
    // stops a routine save from erasing the credential.
    await _prefsWith(_file());
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');

    await SettingsService().saveSettings(const AppSettings(iaAccessKey: ''), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
  });
}
