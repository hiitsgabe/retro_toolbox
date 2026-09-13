import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

Future<SharedPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
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
    'generalSettings': {'downloadDir': '/home/user/roms'},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    'nszDecompressEnabled': true,
  });
}

String _snesKey() => SecretRef.addonToken(kBuiltinAddonId, 'snes');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('load drains the secret from the file into the vault', () async {
    await _prefsWith({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});
    final vault = MemoryVault();

    await SettingsService().loadSettings(vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_snesKey()), 'tok-snes');
  });

  test('load returns settings rehydrated with the vault secret', () async {
    await _prefsWith({'app_settings': _appSettings(authTokenSnes: 'tok-snes')});

    final settings = await SettingsService().loadSettings(MemoryVault());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('load rewrites app_settings without the secret', () async {
    final prefs = await _prefsWith({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});

    await SettingsService().loadSettings(MemoryVault());

    final saved = prefs.getString('app_settings')!;
    expect(saved, isNot(contains('AK')));
    expect(saved, isNot(contains('tok-snes')));
    expect(saved, contains('/roms/snes'));
  });

  test('load leaves app_settings untouched when there was no secret', () async {
    // Weak bite: with no secret the cleaned JSON equals the raw, so this passes
    // whether or not the rewrite is skipped. Locking the write needs injecting
    // SharedPreferences, deferred.
    final withoutSecret = _appSettings();
    final prefs = await _prefsWith({'app_settings': withoutSecret});

    await SettingsService().loadSettings(MemoryVault());

    expect(prefs.getString('app_settings'), withoutSecret);
  });

  test('save writes the secret into the vault', () async {
    await _prefsWith({'app_settings': _appSettings()});
    final vault = MemoryVault();
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_snesKey()), 'tok-snes');
  });

  test('save keeps the secret out of app_settings', () async {
    final prefs = await _prefsWith({'app_settings': _appSettings()});
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, MemoryVault());

    expect(prefs.getString('app_settings'), isNot(contains('AK')));
    expect(prefs.getString('app_settings'), isNot(contains('tok-snes')));
  });

  test('save does NOT erase from the vault what is null in settings', () async {
    // A save from a user action while the load is still in flight sees
    // `const AppSettings()`, all null; erasing on null would drop every
    // credential. Deletion is explicit and has its own method.
    await _prefsWith({'app_settings': _appSettings()});
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(_snesKey(), 'tok-snes');

    await SettingsService().saveSettings(const AppSettings(), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_snesKey()), 'tok-snes');
  });

  test('clearing IA credentials takes all three', () async {
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(SecretRef.iaSecretKey, 'SK');
    await vault.write(SecretRef.iaCookies, 'logged-in-sig=xyz');

    await SettingsService().clearIaSecrets(vault);

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
    expect(await vault.read(SecretRef.iaSecretKey), isNull);
    expect(await vault.read(SecretRef.iaCookies), isNull);
  });

  test('clearing one console token leaves the neighbor', () async {
    final vault = MemoryVault();
    await vault.write(_snesKey(), 'tok-snes');
    await vault.write(SecretRef.addonToken(kBuiltinAddonId, 'n64'), 'tok-n64');

    await SettingsService().writeAddonToken(kBuiltinAddonId, 'snes', '', vault);

    expect(await vault.read(_snesKey()), isNull);
    expect(await vault.read(SecretRef.addonToken(kBuiltinAddonId, 'n64')), 'tok-n64');
  });
}
