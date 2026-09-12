import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';

typedef _Espiao = ({String url, List<Map<String, String?>> vistos});

/// Um servidor local que grava os cabeçalhos que recebeu e responde [corpo].
Future<_Espiao> _servidor(String corpo, {int status = 200}) async {
  final servidor = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => servidor.close(force: true));
  final vistos = <Map<String, String?>>[];
  servidor.listen((req) async {
    vistos.add({
      'authorization': req.headers.value('authorization'),
      'cookie': req.headers.value('cookie'),
    });
    req.response.statusCode = status;
    req.response.write(corpo);
    await req.response.close();
  });
  return (url: 'http://${servidor.address.address}:${servidor.port}/', vistos: vistos);
}

String _listagem(List<String> nomes) => jsonEncode([
      for (final nome in nomes) {'name': nome, 'size': 1024},
    ]);

Future<AddonStore> _store(List<Addon> addons, Map<String, String> catalogos) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('catalog_addons_test');
  addTearDown(() => raiz.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), raiz);
  await store.save(addons);
  for (final entrada in catalogos.entries) {
    await store.writeCatalog(entrada.key, entrada.value);
  }
  return store;
}

String _catalogo(String nomeDoConsole, String url, {Map<String, dynamic>? auth}) => jsonEncode([
      {'name': nomeDoConsole, 'url': url, 'file_format': ['.zip'], if (auth != null) 'auth': auth},
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('buildCatalog', () {
    test('dois addons com arquivo entram os dois, na ordem da lista', () async {
      final store = await _store(
        const [Addon(id: 'um', name: 'Um'), Addon(id: 'dois', name: 'Dois')],
        {
          'um': _catalogo('SNES', 'https://um/'),
          'dois': _catalogo('SNES', 'https://dois/'),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles['snes']!.urls, ['https://um/', 'https://dois/']);
      expect(merged.sources['snes']!.map((f) => f.addonId), ['um', 'dois']);
    });

    test('addon sem arquivo não entra e não derruba os outros', () async {
      final store = await _store(
        const [Addon(id: 'fantasma', name: 'Fantasma'), Addon(id: 'um', name: 'Um')],
        {'um': _catalogo('SNES', 'https://um/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']!.single.addonId, 'um');
    });

    test('catálogo ilegível de um addon não derruba os outros', () async {
      final store = await _store(
        const [Addon(id: 'quebrado', name: 'Quebrado'), Addon(id: 'um', name: 'Um')],
        {'quebrado': 'isto não é json', 'um': _catalogo('SNES', 'https://um/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles.keys, ['snes']);
      expect(merged.sources['snes']!.single.addonId, 'um');
    });

    test('a auth de cada fonte é a do addon que declarou o console', () async {
      final store = await _store(
        const [Addon(id: 'um', name: 'Um'), Addon(id: 'dois', name: 'Dois')],
        {
          'um': _catalogo('SNES', 'https://um/', auth: {'auth_message': 'cole o token'}),
          'dois': _catalogo('SNES', 'https://dois/', auth: {'cookies': true}),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']![0].auth!['auth_message'], 'cole o token');
      expect(merged.sources['snes']![1].auth!['cookies'], true);
    });

    test('lista de addons vazia dá catálogo vazio', () async {
      final store = await _store(const [], const {});
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.isEmpty, isTrue);
    });
  });

  group('fetchSources', () {
    const console = Console(id: 'snes', name: 'SNES', urls: [], fileFormat: ['.zip']);

    // Este grupo fala com um servidor de verdade em loopback, e o
    // `TestWidgetsFlutterBinding` do `main` instala um `HttpOverrides` que
    // devolve 400 em toda requisição. O binding não é opcional: o grupo de cima
    // usa `SharedPreferences.setMockInitialValues`, que sem ele não existe. A
    // saída é suspender o override só aqui. É por isso que
    // `tinfoil_server_proxy_test.dart` faz HTTP real sem nada disso: aquele
    // arquivo não chama binding nenhum.
    final overridesDoBinding = HttpOverrides.current;
    setUp(() => HttpOverrides.global = null);
    tearDown(() => HttpOverrides.global = overridesDoBinding);

    test('cada fonte é buscada com a auth do SEU addon', () async {
      final a = await _servidor(_listagem(['A (USA).zip']));
      final b = await _servidor(_listagem(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(
        client,
        console,
        [
          ConsoleSource(addonId: 'um', url: a.url, auth: const {'auth_message': 'cole'}),
          ConsoleSource(addonId: 'dois', url: b.url, auth: const {'cookies': true, 'cookie_name': 'sessao'}),
        ],
        tokens: const {'um': 'tok-um', 'dois': 'tok-dois'},
      );

      expect(a.vistos.single['authorization'], 'Bearer tok-um');
      expect(a.vistos.single['cookie'], isNull);
      expect(b.vistos.single['cookie'], 'sessao=tok-dois');
      expect(b.vistos.single['authorization'], isNull);
    });

    test('os jogos voltam marcados com o addon que os serviu', () async {
      final a = await _servidor(_listagem(['A (USA).zip']));
      final b = await _servidor(_listagem(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final jogos = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'um', url: a.url),
        ConsoleSource(addonId: 'dois', url: b.url),
      ]);

      final porTitulo = {for (final jogo in jogos) jogo.title: jogo.sourceId};
      expect(porTitulo, {'A (USA).zip': 'um', 'B (USA).zip': 'dois'});
    });

    test('sem token para o addon, nenhum cabeçalho de auth é mandado', () async {
      final a = await _servidor(_listagem(['A (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'um', url: a.url, auth: const {'auth_message': 'cole'}),
      ]);

      expect(a.vistos.single['authorization'], isNull);
    });

    test('uma fonte que falha não impede a outra de entregar', () async {
      final ruim = await _servidor('erro', status: 500);
      final boa = await _servidor(_listagem(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final jogos = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'ruim', url: ruim.url),
        ConsoleSource(addonId: 'boa', url: boa.url),
      ]);

      expect(jogos.map((j) => j.title), ['B (USA).zip']);
      expect(jogos.single.sourceId, 'boa');
    });

    test('todas as fontes falhando propaga o erro', () async {
      final ruim = await _servidor('erro', status: 500);
      final client = HttpClient();
      addTearDown(client.close);

      expect(
        () => CatalogService().fetchSources(client, console, [ConsoleSource(addonId: 'ruim', url: ruim.url)]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
