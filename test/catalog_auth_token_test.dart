import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

void main() {
  test('o token sai do catálogo salvo', () async {
    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'url': 'https://ultranx.exemplo/',
          'auth': {'token': 'tok-secreto', 'cookies': true},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    expect(limpo, isNot(contains('tok-secreto')));
  });

  test('o token colhido vai para o cofre, chaveado por addon e console', () async {
    final vault = MemoryVault();

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secreto'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-secreto');
  });

  test('o resto do auth sobrevive', () async {
    // Limpar demais aqui quebra o login: `cookies`, `cookie_name`, `signin` e
    // `message` são configuração do catálogo, não segredo.
    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {
            'token': 'tok-secreto',
            'cookies': true,
            'cookie_name': 'ultranx_session',
            'message': 'Entre para baixar',
          },
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(limpo) as List).first['auth'] as Map;
    expect(auth['cookies'], isTrue);
    expect(auth['cookie_name'], 'ultranx_session');
    expect(auth['message'], 'Entre para baixar');
    expect(auth.containsKey('token'), isFalse);
    expect(auth['requires_token'], isTrue);
  });

  test('o console limpo continua declarando que pede token', () async {
    // O caso que faz esta Task ser uma correção e não uma regressão. Sem a
    // marca, um console cujo bloco de auth era só o token fica com `auth`
    // vazio, `hasTokenAuth` vira falso, e o usuário perde de uma vez a tela
    // onde digitaria o token e o aviso de que falta token. Ele veria uma fonte
    // privada falhando calada.
    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secreto'},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(limpo) as List).first['auth'] as Map<String, dynamic>;
    final console = Console(id: 'ultranx', name: 'UltraNX', urls: const [], auth: auth);

    expect(console.hasTokenAuth, isTrue);
  });

  test('console sem auth passa intacto', () async {
    final original = jsonEncode([
      {'name': 'Nintendo 64', 'url': 'https://exemplo/n64/'},
    ]);

    final limpo = await CatalogService.harvestAuthTokens(original, vault: MemoryVault(), addonId: 'x');

    expect(jsonDecode(limpo), jsonDecode(original));
  });

  test('o formato de mapa legado também é limpo', () async {
    // O app aceita as duas formas (`catalog_service.dart:79-100`). Limpar só a
    // de array deixaria o buraco aberto para quem usa a antiga, que é
    // exatamente quem tem catálogo mais velho.
    final vault = MemoryVault();

    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode({
        'ultranx': {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secreto'},
        },
      }),
      vault: vault,
      addonId: 'meu_addon',
    );

    expect(limpo, isNot(contains('tok-secreto')));
    expect(await vault.read(SecretRef.addonToken('meu_addon', 'ultranx')), 'tok-secreto');
  });

  test('token vazio não cria chave no cofre, mas deixa a marca', () async {
    // `{'token': ''}` é como um catálogo compartilhado declara "este console
    // pede token, e eu não estou te dando o meu". Não há segredo para guardar,
    // e a marca tem que ficar do mesmo jeito: é ela que mantém a tela de login
    // de pé para o usuário digitar o token dele.
    final vault = MemoryVault();

    final limpo = await CatalogService.harvestAuthTokens(
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
    expect((jsonDecode(limpo) as List).first['auth']['requires_token'], isTrue);
  });

  test('a entrada de descoberta também perde o token', () async {
    // `list_systems: true` não vira console (`catalog_service.dart:87`), então
    // é tentador pular. Não pule: o arquivo compartilhado é o mesmo, e o token
    // lá dentro vaza igual. Ele vai para o cofre pelo id do nome, para não ser
    // perdido se um dia o app passar a usar essas entradas.
    final vault = MemoryVault();

    final limpo = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'Descoberta',
          'list_systems': true,
          'auth': {'token': 'tok-descoberta'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(limpo, isNot(contains('tok-descoberta')));
    expect(await vault.read(SecretRef.addonToken('ultranx', 'descoberta')), 'tok-descoberta');
  });

  test('o cofre já preenchido ganha do arquivo', () async {
    // Mesma regra da migração: reinstalar um catálogo velho não pode devolver
    // ao usuário um token que ele já trocou.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'ultranx'), 'tok-novo');

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-velho'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-novo');
  });

  test('JSON de formato desconhecido volta como veio', () async {
    // Quem valida formato é `setCatalogFromJson`, com mensagem de erro própria.
    // A colheita não pode levantar antes e trocar essa mensagem por um stack
    // trace.
    const cru = '"isto não é um catálogo"';

    expect(await CatalogService.harvestAuthTokens(cru, vault: MemoryVault(), addonId: 'x'), cru);
  });
}
