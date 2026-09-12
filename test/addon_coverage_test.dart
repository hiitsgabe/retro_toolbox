import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {Map<String, dynamic>? auth}) =>
    Console(id: id, name: id.toUpperCase(), urls: urls, auth: auth);

AddonCatalog _catalogo(String addonId, Map<String, Console> consoles) => (addonId: addonId, consoles: consoles);

void main() {
  group('authNeedsToken', () {
    test('console sem bloco de auth não pede token', () {
      expect(authNeedsToken(null), isFalse);
    });

    test('a marca que a colheita deixou basta', () {
      // `requires_token` é o que a Task 8 grava no lugar do token que tira do
      // arquivo compartilhável. Sem este caso, um catálogo privado instalado
      // perderia justamente a tela onde o usuário digitaria o token dele.
      expect(authNeedsToken(const {'requires_token': true}), isTrue);
    });

    test('o campo cru do catálogo ainda conta', () {
      // O embutido nunca passou pela colheita, e um arquivo que o usuário
      // abriu na mão também não.
      expect(authNeedsToken(const {'token': 'tok'}), isTrue);
    });

    test('só a mensagem de login já conta', () {
      expect(authNeedsToken(const {'auth_message': 'Peça convite no fórum.'}), isTrue);
    });

    test('ia_s3 não pede token, nem com a marca', () {
      // O Internet Archive assina de outro jeito e tem tela própria em
      // Accounts. Um campo de token aqui seria campo que não autentica nada.
      expect(authNeedsToken(const {'type': 'ia_s3', 'requires_token': true}), isFalse);
    });

    test('auth que não fala de token não pede token', () {
      expect(authNeedsToken(const {'cookies': true, 'cookie_name': 'sess'}), isFalse);
    });

    test('hasTokenAuth é a função, e não uma segunda regra', () {
      // O caso que impede a volta da duplicação: se alguém mexer num dos dois
      // lugares, este expect para de valer.
      const auth = {'requires_token': true};
      expect(_console('snes', const ['https://a/'], auth: auth).hasTokenAuth, authNeedsToken(auth));
      expect(_console('snes', const ['https://a/']).hasTokenAuth, authNeedsToken(null));
    });
  });

  group('authForAddon', () {
    final fundido = mergeCatalogs([
      _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      _catalogo('ultranx', {
        'snes': _console('snes', const ['https://ultranx/snes/'], auth: const {'token': 'tok', 'cookies': true}),
      }),
    ]);

    test('devolve a auth da fonte do addon pedido', () {
      expect(authForAddon(fundido.sources['snes']!, 'ultranx'), {'token': 'tok', 'cookies': true});
    });

    test('addon que não serve este console devolve null', () {
      expect(authForAddon(fundido.sources['snes']!, 'arquivo-do-fulano'), isNull);
    });

    test('addon que serve sem declarar auth também devolve null', () {
      // As duas ausências viram o mesmo `null` de propósito: quem lê faz a
      // mesma coisa nos dois casos, que é não mandar header nenhum.
      expect(authForAddon(fundido.sources['snes']!, 'myrient'), isNull);
    });

    test('entre duas fontes do mesmo addon, a primeira manda', () {
      // Não sai da fusão, que dá a mesma auth a todas as urls de um console
      // num mesmo catálogo. A regra fica fixada porque `coverage` depende dela
      // para concordar com esta função.
      const lista = [
        ConsoleSource(addonId: 'a', url: 'https://um/', auth: {'token': 'primeiro'}),
        ConsoleSource(addonId: 'a', url: 'https://dois/', auth: {'token': 'segundo'}),
      ];

      expect(authForAddon(lista, 'a'), {'token': 'primeiro'});
    });
  });

  group('coverage', () {
    test('lista os consoles de cada addon', () {
      final fundido = mergeCatalogs([
        _catalogo('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/']),
          'md': _console('md', const ['https://myrient/md/']),
        }),
        _catalogo('ultranx', {'switch': _console('switch', const ['https://ultranx/'])}),
      ]);

      expect(fundido.coverage()['myrient']!.consoles, ['snes', 'md']);
      expect(fundido.coverage()['ultranx']!.consoles, ['switch']);
    });

    test('console servido por dois addons conta para os dois', () {
      final fundido = mergeCatalogs([
        _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalogo('fulano', {'snes': _console('snes', const ['https://fulano/snes/'])}),
      ]);

      expect(fundido.coverage()['myrient']!.consoles, ['snes']);
      expect(fundido.coverage()['fulano']!.consoles, ['snes']);
    });

    test('duas urls do mesmo addon no mesmo console contam um console só', () {
      // A linha da seção 9 diz "25 consoles", não "25 urls". Um espelho a mais
      // não deixa a fonte maior.
      final fundido = mergeCatalogs([
        _catalogo('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/', 'https://espelho/snes/']),
        }),
      ]);

      expect(fundido.coverage()['myrient']!.consoles, ['snes']);
    });

    test('authConsoles traz só os consoles que pedem conta', () {
      final fundido = mergeCatalogs([
        _catalogo('ultranx', {
          'switch': _console('switch', const ['https://ultranx/switch/'], auth: const {'requires_token': true}),
          'wiiu': _console('wiiu', const ['https://ultranx/wiiu/']),
        }),
      ]);

      final cobertura = fundido.coverage()['ultranx']!;

      expect(cobertura.consoles, ['switch', 'wiiu']);
      expect(cobertura.authConsoles, ['switch']);
    });

    test('addon sem conta em console nenhum tem authConsoles vazio', () {
      // É este vazio que apaga o chip de conta da linha, e ele precisa ser
      // lista vazia e não `null`: a tela pergunta `isNotEmpty`.
      final fundido = mergeCatalogs([
        _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      ]);

      expect(fundido.coverage()['myrient']!.authConsoles, isEmpty);
    });

    test('addon que não serve nenhum console não aparece no mapa', () {
      // O caso do addon recém instalado cujo catálogo ainda não foi lido, e o
      // do addon cuja url morreu. Quem desenha a linha trata ausente como
      // zero, e é por isso que a tela da Task 23 usa
      // `?? (consoles: const <String>[], authConsoles: const <String>[])` em
      // vez de `!`.
      final fundido = mergeCatalogs([
        _catalogo('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalogo('vazio', const {}),
      ]);

      expect(fundido.coverage().containsKey('vazio'), isFalse);
    });
  });
}
