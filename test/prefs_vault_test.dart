import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/services/prefs_vault.dart';

import 'vault_contract.dart';

Future<SharedPreferences> _prefsVazio() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runVaultContract('PrefsVault', () async => PrefsVault(await _prefsVazio()));

  test('o segredo não encosta na chave que guarda as settings', () async {
    // O ganho real desta implementação não é cifrar, porque ela não cifra. É
    // tirar o segredo de dentro do `app_settings`, que o app serializa
    // inteiro, imprime em `debugPrint` no caminho de erro
    // (`settings_service.dart:21`) e vai ganhar exportação na Grupo 3.
    SharedPreferences.setMockInitialValues({'app_settings': '{"nszDecompressEnabled":true}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);

    await vault.write('ia/accessKey', 'ABCDEF');

    expect(prefs.getString('app_settings'), '{"nszDecompressEnabled":true}');
    expect(prefs.getString('secret:ia/accessKey'), 'ABCDEF');
  });

  test('o segredo sobrevive a uma instância nova sobre o mesmo prefs', () async {
    // `MemoryVault` passaria o contrato inteiro e perderia tudo no
    // fechamento do app. O contrato não distingue os dois, este caso sim.
    final prefs = await _prefsVazio();
    await PrefsVault(prefs).write('ia/accessKey', 'ABCDEF');

    expect(await PrefsVault(prefs).read('ia/accessKey'), 'ABCDEF');
  });
}
