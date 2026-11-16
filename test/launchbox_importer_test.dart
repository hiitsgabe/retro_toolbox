import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_importer.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_parser.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_store.dart';

const snes = 'Super Nintendo Entertainment System';
const genesis = 'Sega Genesis';

const fixture = '''<?xml version="1.0" standalone="yes"?>
<LaunchBox>
  <Game>
    <Name>Super Metroid</Name>
    <ReleaseDate>1994-03-19T00:00:00-08:00</ReleaseDate>
    <DatabaseID>1</DatabaseID>
    <Platform>Super Nintendo Entertainment System</Platform>
    <Genres>Action; Platform</Genres>
  </Game>
  <Game>
    <Name>Sonic the Hedgehog</Name>
    <ReleaseYear>1991</ReleaseYear>
    <DatabaseID>2</DatabaseID>
    <Platform>Sega Genesis</Platform>
  </Game>
  <GameAlternateName>
    <AlternateName>Metroid 3</AlternateName>
    <DatabaseID>1</DatabaseID>
  </GameAlternateName>
  <GameImage>
    <DatabaseID>2</DatabaseID>
    <FileName>sonic-box.jpg</FileName>
    <Type>Box - Front</Type>
    <Region>North America</Region>
  </GameImage>
</LaunchBox>
''';

/// The zip the server hands out. The incompressible padding entry makes the
/// download arrive in many chunks, so progress moves during it.
List<int> metadataZip() {
  final xml = utf8.encode(fixture);
  final rnd = Random(1);
  final padding = List<int>.generate(512 * 1024, (_) => rnd.nextInt(256));
  return ZipEncoder().encodeBytes(
    Archive()
      ..addFile(ArchiveFile('Metadata.xml', xml.length, xml))
      ..addFile(ArchiveFile('Padding.bin', padding.length, padding)),
  );
}

/// The fixture plus a few hundred KB of other games, stored uncompressed so
/// the parse reads it in many chunks and reports fractions on the way.
List<int> storedZip() {
  final filler = StringBuffer();
  for (var i = 100; i < 1100; i++) {
    filler.write('  <Game><Name>Filler $i</Name><DatabaseID>$i</DatabaseID><Platform>Sony Playstation</Platform>'
        '<Overview>${'Nothing to see here. ' * 20}</Overview></Game>\n');
  }
  final xml = utf8.encode(fixture.replaceFirst('</LaunchBox>', '$filler</LaunchBox>'));
  return ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.noCompress('Metadata.xml', xml.length, xml)));
}

class FakeLaunchbox {
  FakeLaunchbox(this.server);

  final HttpServer server;
  String etag = '"lb-1"';
  List<int> body = metadataZip();
  int status = HttpStatus.ok;

  /// The If-None-Match of every request, null when it had none.
  final ifNoneMatch = <String?>[];

  String get url => 'http://${server.address.host}:${server.port}/Metadata.zip';

  static Future<FakeLaunchbox> start() async {
    final fake = FakeLaunchbox(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    fake.server.listen((r) async {
      final sent = r.headers.value(HttpHeaders.ifNoneMatchHeader);
      fake.ifNoneMatch.add(sent);
      if (fake.status != HttpStatus.ok) {
        r.response.statusCode = fake.status;
      } else if (sent == fake.etag) {
        r.response.statusCode = HttpStatus.notModified;
      } else {
        r.response.headers.set(HttpHeaders.etagHeader, fake.etag);
        r.response.contentLength = fake.body.length;
        for (var i = 0; i < fake.body.length; i += 16 * 1024) {
          r.response.add(fake.body.sublist(i, min(i + 16 * 1024, fake.body.length)));
          await r.response.flush();
          // A pause between chunks, or the client gets the whole body as one.
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }
      await r.response.close();
    });
    return fake;
  }
}

void main() {
  late Directory tmp;
  late Directory cache;
  late LaunchboxStore store;
  late FakeLaunchbox fake;
  HttpOverrides? savedOverrides;

  setUp(() async {
    savedOverrides = HttpOverrides.current;
    HttpOverrides.global = null; // the test binding stubs HTTP with 400s; loopback only here
    tmp = Directory.systemTemp.createTempSync('lb_import_');
    cache = Directory('${tmp.path}/cache');
    store = LaunchboxStore(Directory('${tmp.path}/support/launchbox'));
    fake = await FakeLaunchbox.start();
  });
  tearDown(() async {
    await fake.server.close(force: true);
    HttpOverrides.global = savedOverrides;
    tmp.deleteSync(recursive: true);
  });

  LaunchboxImporter importer() => LaunchboxImporter(store: store, cacheDir: cache, url: fake.url);

  Future<LaunchboxImportResult> run(Set<String> platforms, [void Function(int done, int total)? onProgress]) =>
      importer().run(platforms, onProgress: onProgress ?? (_, __) {});

  List<String> cacheLeftovers() => cache.existsSync() ? [for (final f in cache.listSync()) f.path.split('/').last] : [];

  /// Every file in the store with its bytes and modification time.
  Map<String, String> snapshot() => {
    for (final f in store.root.listSync().whereType<File>())
      f.path.split('/').last: '${base64.encode(f.readAsBytesSync())} ${f.lastModifiedSync().microsecondsSinceEpoch}',
  };

  test('a first run imports every requested platform, then writes the manifest', () async {
    expect(await run({snes, genesis}), LaunchboxImportResult.updated);

    final expected = await parseLaunchboxXml(Stream.value(utf8.encode(fixture)), {snes, genesis});
    for (final platform in [snes, genesis]) {
      final games = LaunchboxStore.decodePlatform((await store.readPlatformBytes(platform))!);
      expect([for (final g in games) jsonEncode(g.toJson())], [for (final g in expected[platform]!) jsonEncode(g.toJson())]);
      expect(games, isNotEmpty);
    }
    final m = (await store.readManifest())!;
    expect(m.etag, '"lb-1"');
    expect(m.platforms, {snes, genesis});
    expect(fake.ifNoneMatch, [null]);
    expect(cacheLeftovers(), isEmpty);
  });

  test('a second run for the same platforms asks with If-None-Match and a 304 touches nothing', () async {
    await run({snes, genesis});
    final before = snapshot();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await run({snes, genesis}), LaunchboxImportResult.upToDate);
    expect(fake.ifNoneMatch, [null, '"lb-1"']);
    expect(snapshot(), before);
    expect(cacheLeftovers(), isEmpty);
  });

  test('asking for a platform the last import did not keep downloads again', () async {
    await run({snes});
    expect(await run({snes, genesis}), LaunchboxImportResult.updated);
    expect(fake.ifNoneMatch, [null, null]);
    expect((await store.readManifest())!.platforms, {snes, genesis});
    expect(LaunchboxStore.decodePlatform((await store.readPlatformBytes(genesis))!).map((g) => g.name), ['Sonic the Hedgehog']);
  });

  test('a 500 throws and leaves the previous import as it was', () async {
    await run({snes, genesis});
    final before = snapshot();
    fake.status = HttpStatus.internalServerError;

    await expectLater(
      run({snes, genesis}),
      throwsA(isA<HttpException>().having((e) => e.message, 'message', 'LaunchBox answered HTTP 500')),
    );
    expect(snapshot(), before);
    expect(cacheLeftovers(), isEmpty);
  });

  test('a body that is not a zip throws, keeps the previous import and leaves no zip', () async {
    await run({snes, genesis});
    final before = snapshot();
    fake
      ..etag = '"lb-2"'
      ..body = utf8.encode('<html>Service Unavailable</html>' * 100);

    await expectLater(run({snes, genesis}), throwsA(isA<FormatException>()));
    expect(fake.ifNoneMatch.last, '"lb-1"', reason: 'the server had a new ETag, so the body was really downloaded');
    expect(snapshot(), before);
    expect(cacheLeftovers(), isEmpty);
  });

  test('an onProgress that throws mid-download cancels and leaves no zip or .part', () async {
    var partSeen = false;
    int? cancelledAt;
    await expectLater(
      run({snes, genesis}, (done, total) {
        if (done <= 250) return;
        partSeen = File('${cache.path}/launchbox_Metadata.zip.part').existsSync();
        cancelledAt = done;
        throw const FileSystemException('cancelled');
      }),
      throwsA(isA<FileSystemException>().having((e) => e.message, 'message', 'cancelled')),
    );
    expect(cancelledAt, lessThan(500), reason: 'still downloading');
    expect(partSeen, isTrue);
    expect(cacheLeftovers(), isEmpty);
    expect(await store.readManifest(), isNull);
  });

  test('a cancel during the parse lands between the download and the end, and leaves no zip', () async {
    fake.body = storedZip();
    int? cancelledAt;
    await expectLater(
      run({snes, genesis}, (done, total) {
        if (done <= 500) return;
        cancelledAt = done;
        throw const FileSystemException('cancelled');
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(cancelledAt, inExclusiveRange(500, 1000));
    expect(cacheLeftovers(), isEmpty);
    expect(await store.readManifest(), isNull);
  });

  test('a cancel at 1000 throws and leaves the previous import as it was', () async {
    await run({snes, genesis});
    final before = snapshot();
    fake.etag = '"lb-2"';

    await expectLater(
      run({snes, genesis}, (done, total) {
        if (done == 1000) throw const FileSystemException('cancelled');
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(snapshot(), before);
    expect(cacheLeftovers(), isEmpty);
  });

  // The parse's last report comes before the isolate has encoded its result;
  // a cancel pressed while it encodes must still be seen before any write.
  test('a cancel pressed after the parse\'s last report still stops the writes', () async {
    await run({snes, genesis});
    final before = snapshot();
    fake.etag = '"lb-2"';

    var pressed = false;
    await expectLater(
      run({snes, genesis}, (done, total) {
        if (pressed) throw const FileSystemException('cancelled');
        if (done >= 990) pressed = true;
      }),
      throwsA(isA<FileSystemException>()),
    );
    expect(snapshot(), before);
  });

  test('progress only goes up, in permille, and ends at (1000, 1000)', () async {
    final progress = <(int, int)>[];
    await run({snes, genesis}, (done, total) => progress.add((done, total)));
    expect(progress.map((p) => p.$2).toSet(), {1000});
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i].$1, greaterThanOrEqualTo(progress[i - 1].$1), reason: '$progress');
    }
    expect(progress.any((p) => p.$1 > 0 && p.$1 < 500), isTrue, reason: 'the download reports as it goes: $progress');
    expect(progress.last, (1000, 1000));
  });
}
