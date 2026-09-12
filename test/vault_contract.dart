import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// O contrato que TODA implementação de [SecretVault] cumpre.
///
/// Existe como função e não como arquivo de teste porque três implementações
/// precisam passar exatamente por ele: memória (Task 2), `shared_preferences`
/// (Task 3) e chaveiro do sistema (Task 4). Copiar os casos daria três cópias
/// que divergem na primeira correção.
///
/// [build] devolve um cofre **vazio** a cada chamada. É `Future` porque a
/// implementação de `shared_preferences` precisa de `await` para nascer.
void runVaultContract(String nome, Future<SecretVault> Function() build) {
  group('contrato de cofre: $nome', () {
    test('lê de volta o que escreveu', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');

      expect(await vault.read('ia/accessKey'), 'ABCDEF');
    });

    test('chave que nunca foi escrita devolve null', () async {
      final vault = await build();

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('escrever por cima substitui', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'velho');
      await vault.write('ia/accessKey', 'novo');

      expect(await vault.read('ia/accessKey'), 'novo');
    });

    test('apagar apaga', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.delete('ia/accessKey');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('escrever vazio apaga, em vez de guardar vazio', () async {
      // Sem isto, `read` devolve `''` num cofre e `null` no outro, e todo
      // chamador vira `if (t != null && t.isNotEmpty)`. A ausência tem uma
      // representação só, e é `null`.
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.write('ia/accessKey', '');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('apagar por prefixo leva só quem casa', () async {
      final vault = await build();
      await vault.write('addon:ultranx/snes', 'a');
      await vault.write('addon:ultranx/n64', 'b');
      await vault.write('addon:ultranx_2/snes', 'c');
      await vault.write('ia/accessKey', 'd');

      await vault.deleteWithPrefix('addon:ultranx/');

      expect(await vault.read('addon:ultranx/snes'), isNull);
      expect(await vault.read('addon:ultranx/n64'), isNull);
      expect(await vault.read('addon:ultranx_2/snes'), 'c');
      expect(await vault.read('ia/accessKey'), 'd');
    });

    test('apagar o que não existe não explode', () async {
      // Chamado na remoção de addon, que roda mesmo para addon que nunca
      // pediu login. Se lançar, remover addon vira erro de tela.
      final vault = await build();

      await vault.delete('addon:nunca/existiu');
      await vault.deleteWithPrefix('addon:nunca/');

      expect(await vault.read('addon:nunca/existiu'), isNull);
    });
  });
}
