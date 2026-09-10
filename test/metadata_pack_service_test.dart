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

  List<int> gz(String s) => gzip.encode(utf8.encode(s));

  test('packUri e indexUri apontam para a release de tag fixa', () {
    final svc = service();
    expect(svc.packUri('snes').toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/snes.json.gz');
    expect(svc.indexUri().toString(),
        'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs/index.json');
  });

  test('download descompacta, grava no cache e devolve o pacote', () async {
    final pedidos = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        pedidos.add(uri);
        return gz(packJson);
      },
    );
    final pack = await svc.download('snes');
    expect(pack.games.single.title, 'Chrono Trigger');
    expect(pedidos.single.path, endsWith('/packs/snes.json.gz'));
    expect(await File(p.join(tmp.path, 'snes.json')).exists(), isTrue);
  });

  test('load usa o cache e não chama a rede', () async {
    var chamadas = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        chamadas++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes');
    expect(pack!.games.single.title, 'Chrono Trigger');
    expect(chamadas, 0);
  });

  test('load com forceRefresh vai na rede mesmo tendo cache', () async {
    var chamadas = 0;
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        chamadas++;
        return gz(packJson);
      },
    );
    await svc.writeCache('snes', packJson);
    await svc.load('snes', forceRefresh: true);
    expect(chamadas, 1);
  });

  test('load cai de volta no cache quando a rede falha', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('sem rede'),
    );
    await svc.writeCache('snes', packJson);
    final pack = await svc.load('snes', forceRefresh: true);
    expect(pack!.games.single.title, 'Chrono Trigger');
  });

  test('load devolve null quando não tem rede nem cache', () async {
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async => throw const SocketException('sem rede'),
    );
    expect(await svc.load('snes'), isNull);
  });

  test('loadIndex baixa o index.json sem gzip e cacheia', () async {
    const indexJson =
        '{"built":"2026-09-10","packs":[{"pack":"snes","system":"S","games":1,"aliases":["snes"]}]}';
    final pedidos = <Uri>[];
    final svc = MetadataPackService(
      cacheDir: tmp,
      fetch: (uri) async {
        pedidos.add(uri);
        return utf8.encode(indexJson);
      },
    );
    final index = await svc.loadIndex(forceRefresh: true);
    expect(index!.packs.single.pack, 'snes');
    expect(pedidos.single.path, endsWith('/packs/index.json'));
    expect((await svc.readCachedIndex())!.built, '2026-09-10');
  });
}
