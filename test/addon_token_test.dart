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

/// Container com o `settingsProvider` de verdade sobre um cofre de mentira.
///
/// O `app_settings` entra semeado com `{}` de propósito. Sem a chave,
/// `loadSettings` cai no ramo padrão, que chama
/// `DirectoryService.getDownloadDir`, que em Android pergunta permissão por
/// plugin e num teste sem plataforma não responde. Com a chave, a carga segue
/// o caminho normal e `AppSettings.fromJson({})` devolve os padrões.
Future<({ProviderContainer container, MemoryVault vault})> _montar() async {
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
      url: 'https://exemplo.org/snes/$title',
      size: 2048,
      consoleId: 'snes',
      sourceId: sourceId,
    );

ConsoleSource _fonte(String addonId, {Map<String, dynamic>? auth}) =>
    ConsoleSource(addonId: addonId, url: 'https://$addonId/snes/', auth: auth);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setAddonToken e readAddonToken', () {
    test('grava o token na chave do par (addon, console)', () async {
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok');
      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), 'tok');
    });

    test('ler o que nunca foi gravado devolve vazio, e não null', () async {
      // Vazio e não `null` porque todo chamador pergunta `isEmpty`. O cofre
      // devolve `null`, e é aqui que a tradução acontece, uma vez só.
      final m = await _montar();

      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), '');
    });

    test('token vazio apaga a chave', () async {
      final m = await _montar();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken('ultranx', 'snes', 'tok');

      await notifier.setAddonToken('ultranx', 'snes', '');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    });

    test('o token do embutido espelha nas settings', () async {
      // O espelho é o que mantém de pé `consoleHasToken` e os dois
      // `_authHeaders` de LAN, que leem síncrono e não sabem de addon.
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });

    test('o token de um addon de terceiro não espelha nas settings', () async {
      // O caso que faz esta Task ser sobre segurança. Se espelhasse, o
      // servidor do Tinfoil mandaria a credencial do UltraNX para o servidor
      // do embutido, porque ele lê o espelho sem perguntar de qual addon é.
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
    });

    test('apagar o token do embutido limpa o espelho', () async {
      final m = await _montar();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      await notifier.setAddonToken(kBuiltinAddonId, 'snes', '');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), isNull);
    });

    test('dois addons no mesmo console guardam tokens separados', () async {
      final m = await _montar();
      final notifier = m.container.read(settingsProvider.notifier);

      await notifier.setAddonToken('ultranx', 'snes', 'tok-ultranx');
      await notifier.setAddonToken('fulano', 'snes', 'tok-fulano');

      expect(await notifier.readAddonToken('ultranx', 'snes'), 'tok-ultranx');
      expect(await notifier.readAddonToken('fulano', 'snes'), 'tok-fulano');
    });

    test('setConsoleAuthToken é o caso particular do embutido', () async {
      // Quatro telas ainda chamam o nome antigo. Ele não pode virar outra
      // coisa por baixo.
      final m = await _montar();

      await m.container.read(settingsProvider.notifier).setConsoleAuthToken('snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), 'tok');
      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });
  });

  group('addonsThatNeedToken', () {
    test('addon cuja fonte pede token entra', () {
      final pedem = addonsThatNeedToken(
        [_game('Xenoblade.nsp', sourceId: 'ultranx')],
        [_fonte('ultranx', auth: const {'requires_token': true})],
      );

      expect(pedem, ['ultranx']);
    });

    test('addon cuja fonte não pede token fica fora', () {
      final pedem = addonsThatNeedToken(
        [_game('Chrono Trigger.zip', sourceId: 'myrient')],
        [_fonte('myrient')],
      );

      expect(pedem, isEmpty);
    });

    test('a conta de um addon não bloqueia o download do outro', () {
      // O motivo de a pergunta ser por fonte. O console é servido pelos dois, e
      // o lote só tem arquivo do aberto: cobrar a conta do privado aqui seria
      // impedir um download que não precisa dela.
      final pedem = addonsThatNeedToken(
        [_game('Chrono Trigger.zip', sourceId: 'myrient')],
        [_fonte('myrient'), _fonte('ultranx', auth: const {'requires_token': true})],
      );

      expect(pedem, isEmpty);
    });

    test('jogo de addon que não serve mais este console fica fora', () {
      // Cache de um addon removido. Bloquear por causa dele seria cobrar conta
      // de uma fonte que não existe mais, e o usuário não teria onde digitar.
      final pedem = addonsThatNeedToken(
        [_game('Xenoblade.nsp', sourceId: 'removido')],
        [_fonte('myrient')],
      );

      expect(pedem, isEmpty);
    });

    test('cada addon entra uma vez, mesmo com muitos jogos', () {
      final pedem = addonsThatNeedToken(
        [
          _game('Xenoblade.nsp', sourceId: 'ultranx'),
          _game('Zelda.nsp', sourceId: 'ultranx'),
          _game('Mario.nsp', sourceId: 'ultranx'),
        ],
        [_fonte('ultranx', auth: const {'requires_token': true})],
      );

      expect(pedem, ['ultranx']);
    });
  });
}
