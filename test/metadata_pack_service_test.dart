import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

const packJson = '''
{"pack":"snes","system":"Nintendo - Super Nintendo Entertainment System",
 "built":"2026-09-10","games":[{"id":"snes/chrono-trigger","title":"Chrono Trigger",
 "dumps":[{"name":"Chrono Trigger (USA)","crc":"2d206bf7"}]}]}
''';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('packs_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  MetadataPackService service() => MetadataPackService(
        cacheDir: tmp,
        fetch: (uri) async => throw StateError('rede proibida neste teste'),
      );

  test('readCached devolve null quando não tem nada em disco', () async {
    expect(await service().readCached('snes'), isNull);
  });

  test('writeCache grava e readCached lê de volta', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    final pack = await svc.readCached('snes');
    expect(pack, isNotNull);
    expect(pack!.games.single.title, 'Chrono Trigger');
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('writeCache cria o diretório se ele não existir', () async {
    final nested = Directory(p.join(tmp.path, 'a', 'b'));
    final svc = MetadataPackService(
        cacheDir: nested, fetch: (uri) async => throw StateError('nao'));
    await svc.writeCache('snes', packJson);
    expect(await File(p.join(nested.path, 'snes.json')).exists(), isTrue);
  });

  test('readCached devolve null e apaga o arquivo quando o JSON está corrompido',
      () async {
    final svc = service();
    final file = File(p.join(tmp.path, 'snes.json'));
    await file.create(recursive: true);
    await file.writeAsString('{ isso nao e json');
    expect(await svc.readCached('snes'), isNull);
    expect(await file.exists(), isFalse);
  });

  test('cachedPacks lista os ids que estão em disco', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.writeCache('nes', packJson);
    final ids = await svc.cachedPacks();
    expect(ids..sort(), ['nes', 'snes']);
  });

  test('evict apaga o pacote do disco', () async {
    final svc = service();
    await svc.writeCache('snes', packJson);
    await svc.evict('snes');
    expect(await svc.readCached('snes'), isNull);
    expect(await svc.cachedPacks(), isEmpty);
  });

  test('readCachedIndex e writeCacheIndex usam index.json', () async {
    final svc = service();
    const indexJson =
        '{"built":"2026-09-10","packs":[{"pack":"snes","system":"S","games":1,"aliases":[]}]}';
    expect(await svc.readCachedIndex(), isNull);
    await svc.writeCacheIndex(indexJson);
    final index = await svc.readCachedIndex();
    expect(index!.packs.single.pack, 'snes');
    expect(await svc.cachedPacks(), isEmpty);
  });
}
