import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/utils/console_auth.dart';
import 'package:roms_downloader/utils/network.dart';

void main() {
  group('buildConsoleAuthHeaders', () {
    test('o token que está no catálogo é ignorado', () {
      // A falha da seção 6.3, literal. O catálogo é o arquivo que o usuário
      // manda para outra pessoa; nada o cifra e nada avisa que tem segredo
      // dentro. Depois desta Task ele pode até conter o campo, que não
      // autentica ninguém.
      final headers = buildConsoleAuthHeaders({'token': 'tok-do-arquivo'});

      expect(headers, isEmpty);
    });

    test('o token de quem chama monta Bearer', () {
      final headers = buildConsoleAuthHeaders({}, tokenOverride: 'tok-do-cofre');

      expect(headers, {'Authorization': 'Bearer tok-do-cofre'});
    });

    test('com cookies, monta Cookie com o nome do catálogo', () {
      final headers = buildConsoleAuthHeaders(
        {'cookies': true, 'cookie_name': 'ultranx_session'},
        tokenOverride: 'tok-do-cofre',
      );

      expect(headers, {'Cookie': 'ultranx_session=tok-do-cofre'});
    });

    test('sem cookie_name, o nome padrão é auth_token', () {
      final headers = buildConsoleAuthHeaders({'cookies': true}, tokenOverride: 'tok-do-cofre');

      expect(headers, {'Cookie': 'auth_token=tok-do-cofre'});
    });

    test('ia_s3 não monta header nem com token de quem chama', () {
      // O Internet Archive assina de outro jeito, e um Bearer aqui quebraria
      // o download em vez de autenticar.
      final headers = buildConsoleAuthHeaders({'type': 'ia_s3'}, tokenOverride: 'tok-do-cofre');

      expect(headers, isEmpty);
    });

    test('console sem auth não monta header', () {
      expect(buildConsoleAuthHeaders(null, tokenOverride: 'tok-do-cofre'), isEmpty);
    });
  });

  group('consoleHasToken', () {
    test('o token do catálogo não conta como conectado', () {
      // Este é o caso que o spec não lista. Sem ele, a tela do Tinfoil e o
      // assistente mostram "conectado" lendo um campo que a Task inteira
      // acabou de tirar do caminho de autenticação.
      const settings = AppSettings();

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });

    test('o token das settings conta', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: 'tok-do-cofre')});

      expect(consoleHasToken(settings, 'ultranx'), isTrue);
    });

    test('token vazio não conta', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: '')});

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });
  });
}
