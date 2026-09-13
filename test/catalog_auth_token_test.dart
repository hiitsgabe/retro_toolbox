import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

void main() {
  test('token is removed from the saved catalog', () async {
    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'url': 'https://ultranx.example/',
          'auth': {'token': 'tok-secret', 'cookies': true},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    expect(cleaned, isNot(contains('tok-secret')));
  });

  test('harvested token is stored in the vault keyed by addon and console', () async {
    final vault = MemoryVault();

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secret'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-secret');
  });

  test('non-token auth fields survive the harvest', () async {
    // `cookies`, `cookie_name`, `signin` and `message` are catalog config, not secrets.
    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {
            'token': 'tok-secret',
            'cookies': true,
            'cookie_name': 'ultranx_session',
            'message': 'Sign in to download',
          },
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(cleaned) as List).first['auth'] as Map;
    expect(auth['cookies'], isTrue);
    expect(auth['cookie_name'], 'ultranx_session');
    expect(auth['message'], 'Sign in to download');
    expect(auth.containsKey('token'), isFalse);
    expect(auth['requires_token'], isTrue);
  });

  test('scrubbed console still declares it requires a token', () async {
    // Without the mark, `auth` ends up empty, `hasTokenAuth` goes false, and a
    // private source fails silently: no login screen, no missing-token warning.
    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secret'},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(cleaned) as List).first['auth'] as Map<String, dynamic>;
    final console = Console(id: 'ultranx', name: 'UltraNX', urls: const [], auth: auth);

    expect(console.hasTokenAuth, isTrue);
  });

  test('console with no auth passes through unchanged', () async {
    final original = jsonEncode([
      {'name': 'Nintendo 64', 'url': 'https://example/n64/'},
    ]);

    final cleaned = await CatalogService.harvestAuthTokens(original, vault: MemoryVault(), addonId: 'x');

    expect(jsonDecode(cleaned), jsonDecode(original));
  });

  test('legacy map format is also scrubbed', () async {
    // The app accepts both formats. Scrubbing only the array form would leave
    // the hole open for older catalogs that use the map format.
    final vault = MemoryVault();

    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode({
        'ultranx': {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secret'},
        },
      }),
      vault: vault,
      addonId: 'meu_addon',
    );

    expect(cleaned, isNot(contains('tok-secret')));
    expect(await vault.read(SecretRef.addonToken('meu_addon', 'ultranx')), 'tok-secret');
  });

  test('empty token does not create a vault key but leaves the requires_token mark', () async {
    // `{'token': ''}` means "needs a token, mine is not included": nothing to
    // store, but the mark must stay or the login screen never appears.
    final vault = MemoryVault();

    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': '', 'cookies': true},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), isNull);
    expect((jsonDecode(cleaned) as List).first['auth']['requires_token'], isTrue);
  });

  test('discovery entry also loses its token', () async {
    // `list_systems: true` entries do not become consoles, but the shared file
    // is the same object and the token leaks just the same. It is stored under
    // the name-derived id so it is not lost if the app ever uses these entries.
    final vault = MemoryVault();

    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'Discovery',
          'list_systems': true,
          'auth': {'token': 'tok-discovery'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(cleaned, isNot(contains('tok-discovery')));
    expect(await vault.read(SecretRef.addonToken('ultranx', 'discovery')), 'tok-discovery');
  });

  test('vault already filled beats the file', () async {
    // Same rule as migration: reinstalling an old catalog must not replace a
    // token the user already updated.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'ultranx'), 'tok-new');

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-old'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-new');
  });

  test('unknown JSON format is returned as-is', () async {
    // Format validation belongs to `setCatalogFromJson`, with its own error
    // message. The harvest must not throw first and replace that message with a
    // stack trace.
    const raw = '"this is not a catalog"';

    expect(await CatalogService.harvestAuthTokens(raw, vault: MemoryVault(), addonId: 'x'), raw);
  });
}
