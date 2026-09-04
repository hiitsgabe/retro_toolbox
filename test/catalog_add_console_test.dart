import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/catalog_service.dart';

void main() {
  Map<String, dynamic> obj(String name) => {'id': 'x', 'name': name, 'url': 'u', 'added': true};

  test('appends to null/empty as a fresh array, id stripped', () {
    final out = CatalogService.appendConsoleToRaw(null, 'snes', obj('SNES'));
    final decoded = jsonDecode(out) as List;
    expect(decoded.length, 1);
    expect(decoded.first['name'], 'SNES');
    expect((decoded.first as Map).containsKey('id'), false);
  });

  test('appends to an existing array, preserving discovery entries', () {
    final start = jsonEncode([
      {'name': 'NES', 'url': 'a'},
      {'list_systems': true, 'url': 'disc'},
    ]);
    final out = CatalogService.appendConsoleToRaw(start, 'snes', obj('SNES'));
    final decoded = jsonDecode(out) as List;
    expect(decoded.length, 3);
    expect(decoded.any((e) => e['list_systems'] == true), true);
    expect(decoded.last['name'], 'SNES');
  });

  test('appends to a map-format catalog keyed by id', () {
    final start = jsonEncode({
      'nes': {'name': 'NES', 'url': 'a'},
    });
    final out = CatalogService.appendConsoleToRaw(start, 'snes', obj('SNES'));
    final decoded = jsonDecode(out) as Map;
    expect(decoded.keys, containsAll(['nes', 'snes']));
    expect((decoded['snes'] as Map).containsKey('id'), false);
  });

  test('rejects a duplicate id in an array', () {
    final start = jsonEncode([
      {'name': 'SNES', 'url': 'a'},
    ]);
    expect(
      () => CatalogService.appendConsoleToRaw(start, 'snes', obj('SNES')),
      throwsA(isA<StateError>()),
    );
  });

  test('rejects a duplicate id in a map', () {
    final start = jsonEncode({
      'snes': {'name': 'SNES'},
    });
    expect(
      () => CatalogService.appendConsoleToRaw(start, 'snes', obj('SNES')),
      throwsA(isA<StateError>()),
    );
  });

  test('parseIaItemId accepts bare ids and archive.org URLs', () {
    expect(CatalogService.parseIaItemId('my_item-1.0'), 'my_item-1.0');
    expect(CatalogService.parseIaItemId('https://archive.org/download/my_item/file.zip'), 'my_item');
    expect(CatalogService.parseIaItemId('https://archive.org/details/my_item'), 'my_item');
    expect(CatalogService.parseIaItemId('https://example.com/foo'), isNull);
    expect(CatalogService.parseIaItemId('  '), isNull);
  });
}
