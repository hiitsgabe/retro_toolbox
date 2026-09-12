import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _catalogoComToken = '''
[{"name": "SNES", "urls": ["https://exemplo.org/snes/"], "auth": {"token": "segredo-do-arquivo"}}]
''';

const _catalogoSemConsole = '[]';

/// Um notifier com store em diretório temporário e sem `path_provider`.
///
/// `invalidarCache` é trocado porque o padrão passa por
/// `getApplicationCacheDirectory`, que num teste sem plataforma lança.
Future<AddonNotifier> _notifier() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addon_install_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(const []);
  final notifier = AddonNotifier(Future.value(store), invalidarCache: () async {});
  addTearDown(notifier.dispose);
  await notifier.ready;
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('baixa, colhe o token e instala o catálogo limpo', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    final addon = await installAddonFromUrl(
      'https://exemplo.org/catalogo.json',
      notifier: notifier,
      vault: vault,
      fetch: (_) async => _catalogoComToken,
    );

    expect(notifier.state.map((a) => a.id), [addon.id]);
    // O token saiu do arquivo e está no cofre sob o par (addon, console). Quem
    // prova que ele saiu do JSON é `catalog_service_test.dart` (Task 8); o que
    // este caso afirma é que a instalação por URL passa pela colheita.
    expect(await vault.read(SecretRef.addonToken(addon.id, 'snes')), 'segredo-do-arquivo');
  });

  test('o id vem de Addon.idFromUrl e o nome vem do host', () async {
    final notifier = await _notifier();

    final addon = await installAddonFromUrl(
      'https://WWW.Exemplo.org/catalogo.json?v=2',
      notifier: notifier,
      vault: MemoryVault(),
      fetch: (_) async => _catalogoComToken,
    );

    expect(addon.id, Addon.idFromUrl('https://exemplo.org/catalogo.json'));
    expect(addon.name, 'exemplo.org');
    expect(addon.url, 'https://WWW.Exemplo.org/catalogo.json?v=2');
  });

  test('reinstalar a mesma fonte por outra forma da url não duplica', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    await installAddonFromUrl('http://www.exemplo.org/catalogo.json/',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogoComToken);
    await installAddonFromUrl('https://exemplo.org/catalogo.json',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogoComToken);

    expect(notifier.state.length, 1);
  });

  test('corpo que não é JSON não instala nada', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://exemplo.org/catalogo.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => '<html>login</html>'),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('JSON válido sem nenhum console não instala nada', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://exemplo.org/catalogo.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => _catalogoSemConsole),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('erro de rede sobe e não instala nada', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://exemplo.org/catalogo.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => throw const HttpException('HTTP 404 fetching catalog')),
      throwsA(isA<HttpException>()),
    );
    expect(notifier.state, isEmpty);
  });
}
