import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _catalogWithToken = '''
[{"name": "SNES", "urls": ["https://example.org/snes/"], "auth": {"token": "file-secret"}}]
''';

const _catalogWithoutConsole = '[]';

/// A notifier with a store in a temp directory and no `path_provider`.
///
/// `invalidateCache` is replaced because the default goes through
/// `getApplicationCacheDirectory`, which throws in a test with no platform.
Future<AddonNotifier> _notifier() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('addon_install_test');
  addTearDown(() => root.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), root);
  await store.save(const []);
  final notifier = AddonNotifier(Future.value(store), invalidateCache: () async {});
  addTearDown(notifier.dispose);
  await notifier.ready;
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('downloads, harvests the token and installs the clean catalog', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    final addon = await installAddonFromUrl(
      'https://example.org/catalog.json',
      notifier: notifier,
      vault: vault,
      fetch: (_) async => _catalogWithToken,
    );

    expect(notifier.state.map((a) => a.id), [addon.id]);
    // The token left the file and is in the vault under the (addon, console)
    // pair. This case asserts that URL install goes through the harvest.
    expect(await vault.read(SecretRef.addonToken(addon.id, 'snes')), 'file-secret');
  });

  test('the id comes from Addon.idFromUrl and the name from the host', () async {
    final notifier = await _notifier();

    final addon = await installAddonFromUrl(
      'https://WWW.Example.org/catalog.json?v=2',
      notifier: notifier,
      vault: MemoryVault(),
      fetch: (_) async => _catalogWithToken,
    );

    expect(addon.id, Addon.idFromUrl('https://example.org/catalog.json'));
    expect(addon.name, 'example.org');
    expect(addon.url, 'https://WWW.Example.org/catalog.json?v=2');
  });

  test('reinstalling the same source via another url form does not duplicate', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    await installAddonFromUrl('http://www.example.org/catalog.json/',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogWithToken);
    await installAddonFromUrl('https://example.org/catalog.json',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogWithToken);

    expect(notifier.state.length, 1);
  });

  test('a non-JSON body installs nothing', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://example.org/catalog.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => '<html>login</html>'),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('valid JSON with no console installs nothing', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://example.org/catalog.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => _catalogWithoutConsole),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('a network error propagates and installs nothing', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://example.org/catalog.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => throw const HttpException('HTTP 404 fetching catalog')),
      throwsA(isA<HttpException>()),
    );
    expect(notifier.state, isEmpty);
  });
}
