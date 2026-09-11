import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store([Map<String, Object> valores = const {}]) async {
  SharedPreferences.setMockInitialValues(valores);
  SharedPreferences.resetStatic();
  final raiz = await Directory.systemTemp.createTemp('addon_store_test');
  addTearDown(() => raiz.delete(recursive: true));
  return AddonStore(await SharedPreferences.getInstance(), raiz);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migração', () {
    test('sem a chave, a lista é só o embutido', () async {
      final store = await _store();
      final lista = store.load();
      expect(lista.map((a) => a.id), [kBuiltinAddonId]);
      expect(lista.single.name, isNotEmpty);
    });

    test('ler NÃO grava: a chave continua ausente depois do load', () async {
      final store = await _store();
      store.load();
      expect((await SharedPreferences.getInstance()).getString(AddonStore.prefsKey), isNull);
    });

    test('o embutido herda a url que o usuário tinha salvo em catalogSourceUrl', () async {
      final store = await _store({
        'app_settings': jsonEncode({'catalogSourceUrl': 'https://exemplo.com/catalogo.json'}),
      });
      expect(store.load().single.url, 'https://exemplo.com/catalogo.json');
    });

    test('app_settings ilegível não derruba a migração', () async {
      final store = await _store({'app_settings': 'isto não é json'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
      expect(store.load().single.url, isNull);
    });

    test('app_settings sem catalogSourceUrl dá embutido sem url', () async {
      final store = await _store({'app_settings': jsonEncode({'downloadDir': '/tmp'})});
      expect(store.load().single.url, isNull);
    });

    test('lista corrompida cai na migração em vez de lançar', () async {
      final store = await _store({AddonStore.prefsKey: '{não é uma lista}'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
    });

    test('item sem id é ignorado, e o resto da lista entra', () async {
      final store = await _store({
        AddonStore.prefsKey: jsonEncode([
          {'nome': 'sem id'},
          {'id': 'ultranx', 'name': 'UltraNX'},
        ]),
      });
      expect(store.load().map((a) => a.id), ['ultranx']);
    });
  });

  group('lista', () {
    test('save e load fecham o ciclo preservando a ordem', () async {
      final store = await _store();
      await store.save(const [
        Addon(id: 'b', name: 'B'),
        Addon(id: kBuiltinAddonId, name: 'Embutido'),
        Addon(id: 'a', name: 'A', url: 'https://a/'),
      ]);
      final volta = store.load();
      expect(volta.map((x) => x.id), ['b', kBuiltinAddonId, 'a']);
      expect(volta.last.url, 'https://a/');
    });

    test('salvar lista vazia é legítimo e não volta para a migração', () async {
      final store = await _store();
      await store.save(const []);
      expect(store.load(), isEmpty);
    });
  });

  group('catálogo em disco', () {
    test('o embutido mora no consoles.json de sempre', () async {
      final store = await _store();
      expect(store.catalogFile(kBuiltinAddonId).path, endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}consoles.json'));
    });

    test('addon instalado mora em config/addons/<id>.json', () async {
      final store = await _store();
      expect(store.catalogFile('ultranx').path,
          endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}addons${Platform.pathSeparator}ultranx.json'));
    });

    test('writeCatalog cria o diretório e readCatalog lê de volta', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[{"name":"SNES"}]');
      expect(await store.readCatalog('ultranx'), '[{"name":"SNES"}]');
    });

    test('readCatalog de addon sem arquivo devolve null', () async {
      final store = await _store();
      expect(await store.readCatalog('ultranx'), isNull);
    });

    test('deleteCatalog apaga, e apagar o que não existe não lança', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[]');
      await store.deleteCatalog('ultranx');
      expect(await store.readCatalog('ultranx'), isNull);
      await store.deleteCatalog('ultranx');
    });
  });
}
