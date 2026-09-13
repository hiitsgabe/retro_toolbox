import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/utils/console_auth.dart';

/// A container with the real `settingsProvider` over a fake vault. `app_settings`
/// is seeded with `{}` so `loadSettings` does not fall into the default branch
/// that asks the platform for a download directory.
Future<({ProviderContainer container, MemoryVault vault})> _build() async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final vault = MemoryVault();
  final container = ProviderContainer(overrides: [
    vaultProvider.overrideWith((ref) async => VaultChoice(vault, encryptedAtRest: true)),
  ]);
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).ready;
  return (container: container, vault: vault);
}

Game _game(String title, {required String sourceId}) => Game(
      title: title,
      url: 'https://example.org/snes/$title',
      size: 2048,
      consoleId: 'snes',
      sourceId: sourceId,
    );

ConsoleSource _source(String addonId, {Map<String, dynamic>? auth}) =>
    ConsoleSource(addonId: addonId, url: 'https://$addonId/snes/', auth: auth);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setAddonToken and readAddonToken', () {
    test('writes the token to the (addon, console) key', () async {
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok');
      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), 'tok');
    });

    test('reading what was never written returns empty, not null', () async {
      // Empty, not `null`, because every caller asks `isEmpty`. The vault returns
      // `null`, and the translation happens here, once.
      final m = await _build();

      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), '');
    });

    test('an empty token deletes the key', () async {
      final m = await _build();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken('ultranx', 'snes', 'tok');

      await notifier.setAddonToken('ultranx', 'snes', '');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    });

    test('the built-in token mirrors into settings', () async {
      // The mirror keeps `consoleHasToken` and the two LAN `_authHeaders` alive;
      // they read synchronously and know nothing about addons.
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });

    test('a third-party addon token does not mirror into settings', () async {
      // The security case. If it mirrored, the Tinfoil server would send the
      // UltraNX credential to the built-in server, which reads the mirror
      // without asking which addon it belongs to.
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
    });

    test('deleting the built-in token clears the mirror', () async {
      final m = await _build();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      await notifier.setAddonToken(kBuiltinAddonId, 'snes', '');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), isNull);
    });

    test('two addons on the same console keep separate tokens', () async {
      final m = await _build();
      final notifier = m.container.read(settingsProvider.notifier);

      await notifier.setAddonToken('ultranx', 'snes', 'tok-ultranx');
      await notifier.setAddonToken('acme', 'snes', 'tok-acme');

      expect(await notifier.readAddonToken('ultranx', 'snes'), 'tok-ultranx');
      expect(await notifier.readAddonToken('acme', 'snes'), 'tok-acme');
    });

    test('setConsoleAuthToken is the built-in special case', () async {
      // No screen calls this name anymore, but the case stays: it locks the
      // equivalence with `setAddonToken(kBuiltinAddonId, ...)` for the day a
      // caller returns.
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setConsoleAuthToken('snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), 'tok');
      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });
  });

  group('addonsThatNeedToken', () {
    test('an addon whose source needs a token is included', () {
      final needing = addonsThatNeedToken(
        [_game('Aethel.nsp', sourceId: 'ultranx')],
        [_source('ultranx', auth: const {'requires_token': true})],
      );

      expect(needing, ['ultranx']);
    });

    test('an addon whose source needs no token is left out', () {
      final needing = addonsThatNeedToken(
        [_game('Crystal Vanguard.zip', sourceId: 'myrient')],
        [_source('myrient')],
      );

      expect(needing, isEmpty);
    });

    test('one addon\'s account does not block the other\'s download', () {
      // Why the question is per source. The console is served by both and the
      // batch only has the open one's file: charging the private account here
      // would block a download that does not need it.
      final needing = addonsThatNeedToken(
        [_game('Crystal Vanguard.zip', sourceId: 'myrient')],
        [_source('myrient'), _source('ultranx', auth: const {'requires_token': true})],
      );

      expect(needing, isEmpty);
    });

    test('a game from an addon no longer serving this console is left out', () {
      // Cache of a removed addon. Blocking on it would charge an account for a
      // source that no longer exists, with nowhere to type it.
      final needing = addonsThatNeedToken(
        [_game('Aethel.nsp', sourceId: 'removed')],
        [_source('myrient')],
      );

      expect(needing, isEmpty);
    });

    test('each addon enters once, even with many games', () {
      final needing = addonsThatNeedToken(
        [
          _game('Aethel.nsp', sourceId: 'ultranx'),
          _game('Kaelis.nsp', sourceId: 'ultranx'),
          _game('Pixel.nsp', sourceId: 'ultranx'),
        ],
        [_source('ultranx', auth: const {'requires_token': true})],
      );

      expect(needing, ['ultranx']);
    });
  });
}
