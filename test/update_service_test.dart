import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/update_service.dart';

Map<String, dynamic> releaseJson({String tag = 'v0.3.0', List<Map<String, dynamic>> assets = const []}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/hiitsgabe/retro_toolbox/releases/tag/$tag',
      'body': '## Retro Toolbox $tag\n\n### New Features\n- One\n- Two\n\n---\n\n### Downloads\n| a | b |',
      'assets': assets,
    };

void main() {
  group('compareVersions', () {
    test('orders numerically, ignoring v, build and pre-release', () {
      expect(isNewerVersion('v0.2.10', '0.2.9'), isTrue);
      expect(isNewerVersion('v0.3.0', '0.2.8'), isTrue);
      expect(isNewerVersion('v1.0', '0.9.9'), isTrue);
      expect(isNewerVersion('v0.2.8', '0.2.8'), isFalse);
      expect(isNewerVersion('v0.2.8', '0.2.8+28'), isFalse);
      expect(isNewerVersion('v0.2.7', '0.2.8'), isFalse);
      expect(isNewerVersion('v0.2.8.0', '0.2.8'), isFalse);
      expect(compareVersions('1.2.3-beta', '1.2.3'), 0);
    });
  });

  group('updateAssetName', () {
    test('handheld wins over everything', () {
      expect(updateAssetName(handheld: true, os: 'linux', abi: Abi.linuxArm64), 'retro_toolbox_handheld_arm64.zip');
    });
    test('android picks by ABI', () {
      expect(updateAssetName(handheld: false, os: 'android', abi: Abi.androidArm64), 'retro_toolbox_arm64.apk');
      expect(updateAssetName(handheld: false, os: 'android', abi: Abi.androidX64), 'retro_toolbox_arm64.apk');
      expect(updateAssetName(handheld: false, os: 'android', abi: Abi.androidArm), 'retro_toolbox_arm32.apk');
      expect(updateAssetName(handheld: false, os: 'android', abi: Abi.androidIA32), 'retro_toolbox_universal.apk');
    });
    test('desktop gets the release page', () {
      expect(updateAssetName(handheld: false, os: 'macos', abi: Abi.macosArm64), isNull);
      expect(updateAssetName(handheld: false, os: 'windows', abi: Abi.windowsX64), isNull);
      expect(updateAssetName(handheld: false, os: 'linux', abi: Abi.linuxX64), isNull);
    });
  });

  test('ReleaseInfo.fromJson reads version, assets and digests', () {
    final r = ReleaseInfo.fromJson(releaseJson(assets: [
      {'name': 'retro_toolbox_arm64.apk', 'browser_download_url': 'https://x/a.apk', 'size': 10, 'digest': 'sha256:ABCD'},
      {'name': 'retro_toolbox.aab', 'browser_download_url': 'https://x/b.aab', 'size': 20, 'digest': null},
    ]));
    expect(r.version, '0.3.0');
    expect(r.htmlUrl, endsWith('/tag/v0.3.0'));
    expect(r.asset('retro_toolbox_arm64.apk')!.sha256, 'abcd');
    expect(r.asset('retro_toolbox_arm64.apk')!.size, 10);
    expect(r.asset('retro_toolbox.aab')!.sha256, isNull);
    expect(r.asset('missing'), isNull);
  });

  test('releaseNotesExcerpt keeps the changes, drops title and downloads', () {
    expect(releaseNotesExcerpt(releaseJson()['body'] as String), 'New Features\n• One\n• Two');
    expect(releaseNotesExcerpt('- a\n- b\n- c', maxLines: 2), '• a\n• b');
  });

  group('files', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('rt_update_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('verifyDownload accepts a matching file and rejects size or checksum mismatches', () async {
      final bytes = utf8.encode('hello update');
      final f = File(p.join(tmp.path, 'a'))..writeAsBytesSync(bytes);
      final good = sha256.convert(bytes).toString();
      ReleaseAsset asset({int? size, String? sum}) =>
          ReleaseAsset(name: 'a', url: '', size: size ?? bytes.length, sha256: sum);

      await verifyDownload(f, asset(sum: good));
      await verifyDownload(f, asset()); // no digest: size only
      await expectLater(verifyDownload(f, asset(sum: '0' * 64)), throwsA(isA<UpdateException>()));
      await expectLater(verifyDownload(f, asset(size: 1, sum: good)), throwsA(isA<UpdateException>()));
    });

    test('stageHandheldUpdate lays out .update/ with READY last', () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('ports/Retro Toolbox.sh', utf8.encode('#!/bin/bash\n')))
        ..add(ArchiveFile.bytes('ports/retrotoolbox/flutter-pi', utf8.encode('bin')))
        ..add(ArchiveFile.bytes('ports/retrotoolbox/data/flutter_assets/app.so', utf8.encode('so')));
      final zip = File(p.join(tmp.path, 'u.zip'))..writeAsBytesSync(ZipEncoder().encode(archive));
      final port = Directory(p.join(tmp.path, 'port'))..createSync();
      Directory(p.join(port.path, '.update', 'stale')).createSync(recursive: true);

      await stageHandheldUpdate(zip, port);

      final up = p.join(port.path, '.update');
      expect(File(p.join(up, 'READY')).existsSync(), isTrue);
      expect(File(p.join(up, 'Retro Toolbox.sh')).readAsStringSync(), '#!/bin/bash\n');
      expect(File(p.join(up, 'retrotoolbox', 'flutter-pi')).readAsStringSync(), 'bin');
      expect(File(p.join(up, 'retrotoolbox', 'data', 'flutter_assets', 'app.so')).existsSync(), isTrue);
      expect(Directory(up).listSync().map((e) => p.basename(e.path)).toSet(), {'READY', 'Retro Toolbox.sh', 'retrotoolbox'});
    });

    test('stageHandheldUpdate rejects a zip without the port tree and leaves nothing behind', () async {
      final archive = Archive()..add(ArchiveFile.bytes('other/file', utf8.encode('x')));
      final zip = File(p.join(tmp.path, 'u.zip'))..writeAsBytesSync(ZipEncoder().encode(archive));
      final port = Directory(p.join(tmp.path, 'port'))..createSync();

      await expectLater(stageHandheldUpdate(zip, port), throwsA(isA<UpdateException>()));
      expect(Directory(p.join(port.path, '.update')).existsSync(), isFalse);
    });
  });

  group('network', () {
    late HttpServer server;
    late Directory cache;
    var status = 200;
    Object body = '';
    String? userAgent;

    setUp(() async {
      cache = Directory.systemTemp.createTempSync('rt_update_cache_');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        userAgent = req.headers.value(HttpHeaders.userAgentHeader);
        req.response.statusCode = status;
        body is List<int> ? req.response.add(body as List<int>) : req.response.write(body);
        req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      cache.deleteSync(recursive: true);
    });

    UpdateService service() => UpdateService(
          releaseUrl: 'http://127.0.0.1:${server.port}/latest',
          cacheDir: () async => cache,
          portRoot: cache.path,
        );

    test('fetchLatest parses the release and sends a User-Agent', () async {
      status = 200;
      body = jsonEncode(releaseJson());
      final r = await service().fetchLatest();
      expect(r.version, '0.3.0');
      expect(userAgent, isNotEmpty);
    });

    test('fetchLatest maps rate limit, missing releases and offline', () async {
      status = 403;
      body = '{}';
      await expectLater(service().fetchLatest(), throwsA(predicate((e) => '$e'.contains('rate limit'))));
      status = 404;
      await expectLater(service().fetchLatest(), throwsA(predicate((e) => '$e'.contains('No releases'))));
      final offline = UpdateService(releaseUrl: 'http://127.0.0.1:1/latest', cacheDir: () async => cache);
      await expectLater(offline.fetchLatest(), throwsA(predicate((e) => e is UpdateException && '$e'.contains("Can't reach"))));
    });

    test('download reports progress and verifies; a bad checksum deletes the file', () async {
      final bytes = List<int>.generate(100000, (i) => i % 251);
      status = 200;
      body = bytes;
      final url = 'http://127.0.0.1:${server.port}/asset';
      final progress = <double>[];
      final ok = await service().download(
        ReleaseAsset(name: 'u.apk', url: url, size: bytes.length, sha256: sha256.convert(bytes).toString()),
        progress.add,
      );
      expect(ok.lengthSync(), bytes.length);
      expect(progress.last, 1.0);

      await expectLater(
        service().download(ReleaseAsset(name: 'bad.apk', url: url, size: bytes.length, sha256: '0' * 64), (_) {}),
        throwsA(predicate((e) => '$e'.contains('checksum'))),
      );
      expect(File(p.join(cache.path, 'bad.apk')).existsSync(), isFalse);
    });
  });
}
