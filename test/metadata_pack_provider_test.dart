import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

const indexJson =
    '{"built":"2026-09-10","packs":[{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","games":1,"aliases":["super_nintendo"]}]}';
const packJson =
    '{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System","built":"2026-09-10","games":[{"id":"snes/crystal-vanguard","title":"Crystal Vanguard","dumps":[]}]}';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('packs_provider_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  ProviderContainer containerWith(PackFetch fetch) {
    final service = MetadataPackService(cacheDir: tmp, fetch: fetch);
    return ProviderContainer(overrides: [
      metadataPackServiceProvider.overrideWith((ref) async => service),
    ]);
  }

  test('packIndexProvider delivers the downloaded index', () async {
    final container = containerWith((uri) async => utf8.encode(indexJson));
    addTearDown(container.dispose);
    final index = await container.read(packIndexProvider.future);
    expect(index!.packs.single.pack, 'snes');
  });

  test('metadataPackProvider resolves by alias and downloads the pack', () async {
    final container = containerWith((uri) async {
      if (uri.path.endsWith('index.json')) return utf8.encode(indexJson);
      return gzip.encode(utf8.encode(packJson));
    });
    addTearDown(container.dispose);
    final pack = await container.read(
        metadataPackProvider(const PackTarget('super_nintendo', 'Super Nintendo'))
            .future);
    expect(pack!.games.single.title, 'Crystal Vanguard');
  });

  test('a console absent from the index returns null without fetching a pack', () async {
    final requests = <Uri>[];
    final container = containerWith((uri) async {
      requests.add(uri);
      return utf8.encode(indexJson);
    });
    addTearDown(container.dispose);
    final pack = await container.read(
        metadataPackProvider(const PackTarget('nintendo_switch', 'Nintendo Switch'))
            .future);
    expect(pack, isNull);
    expect(requests.every((u) => u.path.endsWith('index.json')), isTrue);
  });
}
