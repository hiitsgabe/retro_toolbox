import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Conta escritas, para provar que um mapa sem segredo não encosta no cofre.
class _VaultEspiao extends MemoryVault {
  int escritas = 0;

  @override
  Future<void> write(String key, String value) {
    escritas++;
    return super.write(key, value);
  }
}

Map<String, dynamic> _settings({
  String? iaAccessKey,
  String? iaSecretKey,
  String? iaCookies,
  Map<String, dynamic>? consoleSettings,
}) {
  return {
    'consoleSettings': consoleSettings ?? <String, dynamic>{},
    'generalSettings': {'downloadDir': '/home/joao/roms', 'autoExtract': true},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
    if (iaCookies != null) 'iaCookies': iaCookies,
    'nszDecompressEnabled': true,
  };
}

void main() {
  test('as três credenciais do Internet Archive vão para o cofre', () async {
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz'));

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(SecretRef.iaSecretKey), 'SK');
    expect(await vault.read(SecretRef.iaCookies), 'logged-in-sig=xyz');
  });

  test('o token de cada console vai chaveado pelo addon, não só pelo console', () async {
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(consoleSettings: {
      'nintendo_64': {'downloadDir': '/roms/n64', 'authToken': 'tok-n64'},
      'snes': {'authToken': 'tok-snes'},
    }));

    expect(await vault.read(SecretRef.addonToken('builtin', 'nintendo_64')), 'tok-n64');
    expect(await vault.read(SecretRef.addonToken('builtin', 'snes')), 'tok-snes');
  });

  test('o mapa devolvido não tem mais nenhum dos quatro segredos', () async {
    final migracao = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final limpo = await migracao.drain(_settings(
      iaAccessKey: 'AK',
      iaSecretKey: 'SK',
      iaCookies: 'logged-in-sig=xyz',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    ));

    expect(limpo.containsKey('iaAccessKey'), isFalse);
    expect(limpo.containsKey('iaSecretKey'), isFalse);
    expect(limpo.containsKey('iaCookies'), isFalse);
    expect((limpo['consoleSettings'] as Map)['snes'], isNot(contains('authToken')));
  });

  test('o que não é segredo continua onde estava', () async {
    // Uma migração que limpa demais apaga a pasta de download do usuário.
    final migracao = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final limpo = await migracao.drain(_settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'downloadDir': '/roms/snes', 'authToken': 'tok-snes'},
      },
    ));

    expect(limpo['nszDecompressEnabled'], isTrue);
    expect((limpo['generalSettings'] as Map)['downloadDir'], '/home/joao/roms');
    expect((limpo['consoleSettings'] as Map)['snes'], containsPair('downloadDir', '/roms/snes'));
  });

  test('o cofre já preenchido ganha do arquivo, mas o texto puro sai mesmo assim', () async {
    // Acontece quando a primeira passada gravou no cofre e o salvamento do
    // arquivo limpo não chegou a acontecer. A cópia do arquivo é, por
    // definição, a velha: sobrescrever com ela devolveria ao usuário um token
    // que ele já trocou. Mas o texto puro tem que sair de qualquer jeito,
    // senão a migração nunca termina e o segredo mora nos dois lugares.
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'novo');
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final limpo = await migracao.drain(_settings(iaAccessKey: 'velho'));

    expect(await vault.read(SecretRef.iaAccessKey), 'novo');
    expect(limpo.containsKey('iaAccessKey'), isFalse);
  });

  test('valor vazio não vira chave no cofre', () async {
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(iaAccessKey: ''));

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
  });

  test('um consoleSettings malformado não derruba a migração', () async {
    // O arquivo vem do disco de um usuário que pode ter editado à mão, e a
    // migração roda na abertura do app. Um `as Map` otimista aqui vira app que
    // não abre, e o usuário não tem como consertar sem achar o arquivo.
    final vault = MemoryVault();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final limpo = await migracao.drain({
      'consoleSettings': {
        'snes': 'isto deveria ser um mapa',
        'n64': {'authToken': 'tok-n64'},
      },
      'nszDecompressEnabled': true,
    });

    expect(await vault.read(SecretRef.addonToken('builtin', 'n64')), 'tok-n64');
    expect((limpo['consoleSettings'] as Map)['snes'], 'isto deveria ser um mapa');
  });

  test('não muta o mapa que recebeu', () async {
    // O chamador da Grupo 2 tem o mapa que acabou de desserializar em mãos. Se
    // a migração mexer nele por dentro, o `consoleSettings` aninhado é o mesmo
    // objeto, e o token some do mapa do chamador antes de qualquer coisa ter
    // sido salva. Um `Map.from` raso não basta, e é esse o erro que este caso
    // pega.
    final migracao = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');
    final original = _settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    );

    await migracao.drain(original);

    expect(original['iaAccessKey'], 'AK');
    expect((original['consoleSettings'] as Map)['snes'], containsPair('authToken', 'tok-snes'));
  });

  test('um mapa sem segredo nenhum não escreve nada no cofre', () async {
    // A migração roda em toda abertura do app. No Linux com chaveiro, cada
    // escrita é uma ida ao D-Bus; no aparelho de quem nunca fez login, o número
    // certo de idas é zero.
    final vault = _VaultEspiao();
    final migracao = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migracao.drain(_settings(consoleSettings: {
      'snes': {'downloadDir': '/roms/snes'},
    }));

    expect(vault.escritas, 0);
  });
}
