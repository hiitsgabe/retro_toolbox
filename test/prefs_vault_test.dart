import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/prefs_vault.dart';

import 'vault_contract.dart';

Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runVaultContract('PrefsVault', () async => PrefsVault(await _emptyPrefs()));

  test('secret is stored outside the settings key', () async {
    SharedPreferences.setMockInitialValues({'app_settings': '{"nszDecompressEnabled":true}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);

    await vault.write('ia/accessKey', 'ABCDEF');

    expect(prefs.getString('app_settings'), '{"nszDecompressEnabled":true}');
    expect(prefs.getString('secret:ia/accessKey'), 'ABCDEF');
  });

  test('secret survives a new instance over the same prefs', () async {
    final prefs = await _emptyPrefs();
    await PrefsVault(prefs).write('ia/accessKey', 'ABCDEF');

    expect(await PrefsVault(prefs).read('ia/accessKey'), 'ABCDEF');
  });

  test('deleting a whole addon leaves non-secret keys untouched', () async {
    SharedPreferences.setMockInitialValues({'app_settings': '{"downloadDir":"/home/roms"}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'AAA');
    await vault.write(SecretRef.addonToken('ultranx_2', 'snes'), 'BBB');

    await vault.deleteWithPrefix(SecretRef.addonPrefix('ultranx'));

    expect(prefs.getString('app_settings'), '{"downloadDir":"/home/roms"}');
    expect(await vault.read(SecretRef.addonToken('ultranx_2', 'snes')), 'BBB');
    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
  });

  test('open() builds over the real prefs, the production path', () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();

    final vault = await PrefsVault.open();
    await vault.write(SecretRef.iaAccessKey, 'ABCDEF');

    expect(await vault.read(SecretRef.iaAccessKey), 'ABCDEF');
  });
}
