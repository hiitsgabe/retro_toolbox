import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';

void main() {
  group('Addon.idFromUrl', () {
    test('http and https of the same catalog share an id, and surrounding space is ignored', () {
      const cleaned = 'https://example.com/catalog.json';
      expect(Addon.idFromUrl('http://example.com/catalog.json'), Addon.idFromUrl(cleaned));
      // The `trim` matters: without it `Uri.tryParse` finds no host in a
      // space-padded url and the id becomes `https_example_com_catalog_json`.
      expect(Addon.idFromUrl('  $cleaned  '), Addon.idFromUrl(cleaned));
      // The literal pins the format; comparing id to id survives any slug change.
      expect(Addon.idFromUrl(cleaned), 'example_com_catalog_json');
    });

    test('trailing slash, query and fragment do not change the id', () {
      final base = Addon.idFromUrl('https://example.com/catalog/');
      expect(Addon.idFromUrl('https://example.com/catalog'), base);
      expect(Addon.idFromUrl('https://example.com/catalog?v=2'), base);
      expect(Addon.idFromUrl('https://example.com/catalog#top'), base);
    });

    test('www. and uppercase do not change the id', () {
      expect(Addon.idFromUrl('https://WWW.Example.COM/Catalog'), Addon.idFromUrl('https://example.com/catalog'));
    });

    test('two catalogs on the same host get different ids, and the port is part of the host', () {
      expect(Addon.idFromUrl('https://example.com/snes.json'), isNot(Addon.idFromUrl('https://example.com/nes.json')));
      // Two LAN servers on the same IP but different ports are two addons. With
      // the port out of the id they would share a vault key and the second
      // install's token would erase the first's.
      expect(Addon.idFromUrl('http://192.168.0.10:8080/f/0/'), isNot(Addon.idFromUrl('http://192.168.0.10:8081/f/0/')));
      expect(Addon.idFromUrl('https://example.com:8080/c.json'), isNot(Addon.idFromUrl('https://example.com/c.json')));
    });

    test('the built-in id: no url maps to it, and only it answers isBuiltin', () {
      expect(Addon.idFromUrl('https://builtin/'), isNot(kBuiltinAddonId));
      expect(const Addon(id: kBuiltinAddonId, name: 'Listing').isBuiltin, isTrue);
      expect(const Addon(id: 'ultranx', name: 'UltraNX').isBuiltin, isFalse);
    });

    test('a hostless url falls back to a text-derived id, not empty', () {
      expect(Addon.idFromUrl('    '), isNotEmpty);
    });
  });

  group('Addon json', () {
    test('round trip preserves id, name and url', () {
      const addon = Addon(id: 'ultranx', name: 'UltraNX', url: 'https://ultranx.example/catalog.json');
      final back = Addon.fromJson(addon.toJson());
      expect(back.id, addon.id);
      expect(back.name, addon.name);
      expect(back.url, addon.url);
    });

    test('with no name in the json, the name becomes the id', () {
      expect(Addon.fromJson({'id': 'ultranx'}).name, 'ultranx');
    });
  });

  group('ordered list', () {
    const a = Addon(id: 'a', name: 'A');
    const b = Addon(id: 'b', name: 'B');
    const c = Addon(id: 'c', name: 'C');

    test('upsertAddon appends at the end when the id is new', () {
      expect(upsertAddon([a, b], c).map((x) => x.id), ['a', 'b', 'c']);
    });

    test('upsertAddon replaces WITHOUT changing position', () {
      final out = upsertAddon([a, b, c], const Addon(id: 'b', name: 'B new'));
      expect(out.map((x) => x.id), ['a', 'b', 'c']);
      expect(out[1].name, 'B new');
    });

    test('removeAddon drops the requested one and keeps the rest in order', () {
      expect(removeAddon([a, b, c], 'b').map((x) => x.id), ['a', 'c']);
    });

    test('removeAddon with an unknown id leaves the list unchanged', () {
      expect(removeAddon([a, b], 'z').map((x) => x.id), ['a', 'b']);
    });

    test('reorderAddons moving down applies the ReorderableListView discount', () {
      // Dragging "a" to the end: the widget passes newIndex = 3, counting the
      // slot "a" itself will vacate.
      expect(reorderAddons([a, b, c], 0, 3).map((x) => x.id), ['b', 'c', 'a']);
    });

    test('reorderAddons moving up applies no discount', () {
      expect(reorderAddons([a, b, c], 2, 0).map((x) => x.id), ['c', 'a', 'b']);
    });

    test('reorderAddons with an out-of-range source index returns the same list', () {
      expect(reorderAddons([a, b], 5, 0).map((x) => x.id), ['a', 'b']);
    });

    test('upsertAddon replaces at position 0, the built-in slot', () {
      final out = upsertAddon([a, b, c], const Addon(id: 'a', name: 'A new'));
      expect(out.map((x) => x.id), ['a', 'b', 'c']);
      expect(out.first.name, 'A new');
    });

    test('reorderAddons moving down into the middle discounts the vacated slot', () {
      const d = Addon(id: 'd', name: 'D');
      expect(reorderAddons([a, b, c, d], 0, 2).map((x) => x.id), ['b', 'a', 'c', 'd']);
    });
  });
}
