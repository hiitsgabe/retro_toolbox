import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
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
    // tirar o segredo de dentro do `app_settings`, cujo erro de leitura
    // imprime o próprio JSON de volta: a `FormatException` do `jsonDecode`
    // embute o trecho da fonte, e o `debugPrint` do caminho de erro
    // (`settings_service.dart:21`) manda isso para o log com o segredo dentro.
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

  test('apagar um addon inteiro não encosta em quem não é segredo', () async {
    // A única propriedade que **só** esta implementação tem. O contrato
    // compartilhado exercita a fronteira entre dois addons, mas roda igual
    // para `MemoryVault`, que não divide store com ninguém. Este cofre divide:
    // ele varre o mesmo `shared_preferences` onde mora o `app_settings`.
    SharedPreferences.setMockInitialValues({'app_settings': '{"downloadDir":"/casa/roms"}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'AAA');
    await vault.write(SecretRef.addonToken('ultranx_2', 'snes'), 'BBB');

    await vault.deleteWithPrefix(SecretRef.addonPrefix('ultranx'));

    expect(prefs.getString('app_settings'), '{"downloadDir":"/casa/roms"}');
    expect(await vault.read(SecretRef.addonToken('ultranx_2', 'snes')), 'BBB');
    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
  });

  test('`open()` abre sobre o prefs de verdade, que é o caminho da produção', () async {
    // Os outros casos constroem pelo construtor, e `vault_provider.dart:39`
    // liga `PrefsVault.open` como reserva. Sem este caso, o único caminho que
    // a produção percorre é o único sem teste.
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();

    final vault = await PrefsVault.open();
    await vault.write(SecretRef.iaAccessKey, 'ABCDEF');

    expect(await vault.read(SecretRef.iaAccessKey), 'ABCDEF');
  });
}
