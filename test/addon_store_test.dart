import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('addon_store_test');
  addTearDown(() => root.delete(recursive: true));
  return AddonStore(await SharedPreferences.getInstance(), root);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migration', () {
    test('with no key, the list is just the built-in', () async {
      final store = await _store();
      final list = store.load();
      expect(list.map((a) => a.id), [kBuiltinAddonId]);
      expect(list.single.name, isNotEmpty);
    });

    test('reading does NOT write: the key stays absent after load', () async {
      final store = await _store();
      store.load();
      expect((await SharedPreferences.getInstance()).getString(AddonStore.prefsKey), isNull);
    });

    test('the built-in inherits the url saved in catalogSourceUrl', () async {
      final store = await _store({
        'app_settings': jsonEncode({'catalogSourceUrl': 'https://example.com/catalog.json'}),
      });
      expect(store.load().single.url, 'https://example.com/catalog.json');
    });

    test('unreadable app_settings does not break the migration', () async {
      final store = await _store({'app_settings': 'this is not json'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
      expect(store.load().single.url, isNull);
    });

    test('app_settings without catalogSourceUrl gives a built-in with no url', () async {
      final store = await _store({'app_settings': jsonEncode({'downloadDir': '/tmp'})});
      expect(store.load().single.url, isNull);
    });

    test('a corrupt list falls into migration instead of throwing', () async {
      final store = await _store({AddonStore.prefsKey: '{not a list}'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
    });

    test('an item with no id is dropped and the rest of the list enters', () async {
      final store = await _store({
        AddonStore.prefsKey: jsonEncode([
          {'name': 'no id'},
          {'id': 'ultranx', 'name': 'UltraNX'},
        ]),
      });
      expect(store.load().map((a) => a.id), ['ultranx']);
    });
  });

  group('list', () {
    test('save and load close the cycle preserving order', () async {
      final store = await _store();
      await store.save(const [
        Addon(id: 'b', name: 'B'),
        Addon(id: kBuiltinAddonId, name: 'Built-in'),
        Addon(id: 'a', name: 'A', url: 'https://a/'),
      ]);
      final back = store.load();
      expect(back.map((x) => x.id), ['b', kBuiltinAddonId, 'a']);
      expect(back.last.url, 'https://a/');
    });

    test('saving an empty list is legitimate and does not return to migration', () async {
      final store = await _store();
      await store.save(const []);
      expect(store.load(), isEmpty);
    });
  });

  group('catalog on disk', () {
    test('the built-in lives in the usual consoles.json', () async {
      final store = await _store();
      expect(store.catalogFile(kBuiltinAddonId).path, endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}consoles.json'));
    });

    test('an installed addon lives in config/addons/<id>.json', () async {
      final store = await _store();
      expect(store.catalogFile('ultranx').path,
          endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}addons${Platform.pathSeparator}ultranx.json'));
    });

    test('writeCatalog creates the directory and readCatalog reads it back', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[{"name":"SNES"}]');
      expect(await store.readCatalog('ultranx'), '[{"name":"SNES"}]');
    });

    test('readCatalog of an addon with no file returns null', () async {
      final store = await _store();
      expect(await store.readCatalog('ultranx'), isNull);
    });

    test('deleteCatalog deletes, and deleting what is absent does not throw', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[]');
      await store.deleteCatalog('ultranx');
      expect(await store.readCatalog('ultranx'), isNull);
      await store.deleteCatalog('ultranx');
    });
  });
}
