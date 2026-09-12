import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';

void main() {
  test('a chave de token carrega o addon e o console, nessa ordem', () {
    expect(SecretRef.addonToken('ultranx', 'nintendo_64'), 'addon:ultranx/nintendo_64');
  });

  test('dois addons servindo o mesmo console não dividem a chave', () {
    // Este é o caso que justifica a chave inteira. O id do console vem do
    // NOME dele (`catalog_service.dart:_nameToId`), então dois addons que
    // sirvam "Nintendo 64" produzem `nintendo_64` os dois. Se a chave fosse
    // só do console, o login do segundo apagaria o do primeiro em silêncio.
    expect(
      SecretRef.addonToken('ultranx', 'nintendo_64'),
      isNot(SecretRef.addonToken('meu_rts', 'nintendo_64')),
    );
  });

  test('as chaves do Internet Archive são as três da seção 6.2', () {
    expect(SecretRef.iaAccessKey, 'ia/accessKey');
    expect(SecretRef.iaSecretKey, 'ia/secretKey');
    expect(SecretRef.iaCookies, 'ia/cookies');
  });

  test('debrid é chaveado por provedor, porque vai ter mais de um', () {
    expect(SecretRef.debrid('realdebrid'), 'debrid/realdebrid');
  });

  test('o prefixo de um addon casa com as chaves dele e com mais nenhuma', () {
    final prefixo = SecretRef.addonPrefix('ultranx');

    expect(SecretRef.addonToken('ultranx', 'nintendo_64').startsWith(prefixo), isTrue);
    expect(SecretRef.addonToken('ultranx', 'snes').startsWith(prefixo), isTrue);
    expect(SecretRef.addonToken('ultranx_2', 'snes').startsWith(prefixo), isFalse);
    expect(SecretRef.iaAccessKey.startsWith(prefixo), isFalse);
  });

  test('um id com barra ou dois-pontos não consegue forjar a chave de outro', () {
    // Sem sanear, o addon de id `a/b` mais o console `c` daria
    // `addon:a/b/c`, que é a mesma coisa que o addon `a` mais o console
    // `b/c`. Os ids de hoje são slugs e isso não acontece, mas a chave é
    // permanente e o gerador de id não é: o saneamento mora aqui, no lado
    // que não pode mudar depois.
    expect(
      SecretRef.addonToken('a/b', 'c'),
      isNot(SecretRef.addonToken('a', 'b/c')),
    );
  });

  test('sanear não colapsa ids que só diferem em pontuação', () {
    expect(SecretRef.addonToken('meu-rts', 'snes'), isNot(SecretRef.addonToken('meu_rts', 'snes')));
  });
}
