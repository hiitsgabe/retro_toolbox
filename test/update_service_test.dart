import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

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
      expect(isNewerVersion('V0.3.0', '0.2.8'), isTrue);
      expect(isNewerVersion('v1.2.3', '1.2.3-rc1'), isTrue);
      expect(isNewerVersion('v1.2.3-rc1', '1.2.2'), isTrue);
      expect(isNewerVersion('v1.2.3-rc1', '1.2.3'), isFalse);
    });
    test('malformed tags are not versions', () {
      expect(isValidVersion('0.2.8'), isTrue);
      expect(isValidVersion('v1.2.3-rc.1+5'), isTrue);
      for (final bad in ['', 'latest', 'v1..2', '1.2.x', 'v', 'release-1.2']) {
        expect(isValidVersion(bad), isFalse, reason: bad);
      }
    });
  });

  group('updateAssetName', () {
    test('handheld wins over everything', () {
      expect(updateAssetName(handheld: true, os: 'linux', abi: Abi.linuxArm64), 'retro_toolbox_handheld_arm64.zip');
    });
    test('android picks by ABI', () {
      expect(updateAssetName(handheld: false, os: 'android', abi: Abi.androidArm64), 'retro_toolbox_arm64.apk');
      expect(updateAssetName(handheld: false, os: 'android', abi: Abi.androidX64), 'retro_toolbox_universal.apk');
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
      {
        'name': 'retro_toolbox_arm64.apk',
        'browser_download_url': 'https://x/a.apk',
        'size': 10,
        'digest': 'sha256:ABCD'
      },
      {'name': 'retro_toolbox.aab', 'browser_download_url': 'https://x/b.aab', 'size': 20, 'digest': null},
    ]));
    expect(r.version, '0.3.0');
    expect(r.htmlUrl, endsWith('/tag/v0.3.0'));
    expect(r.asset('retro_toolbox_arm64.apk')!.sha256, 'abcd');
    expect(r.asset('retro_toolbox_arm64.apk')!.size, 10);
    expect(r.asset('retro_toolbox.aab')!.sha256, isNull);
    expect(r.asset('missing'), isNull);
    expect(ReleaseInfo.fromJson({...releaseJson(), 'html_url': 'https://evil.example/x'}).htmlUrl, releasesPageUrl);
  });

  test('isTrustedUpdateUrl allows only https GitHub hosts', () {
    for (final ok in [
      'https://api.github.com/repos/x',
      'https://github.com/a/b/releases/download/v1/f.zip',
      'https://objects.githubusercontent.com/x',
      'https://release-assets.githubusercontent.com/x',
    ]) {
      expect(isTrustedUpdateUrl(Uri.parse(ok)), isTrue, reason: ok);
    }
    for (final bad in [
      'http://github.com/x',
      'https://github.com.evil.example/x',
      'https://evilgithubusercontent.com/x',
      'https://example.com/x',
      'file:///etc/passwd',
    ]) {
      expect(isTrustedUpdateUrl(Uri.parse(bad)), isFalse, reason: bad);
    }
  });

  test('releaseNotesExcerpt keeps the changes, drops title and downloads', () {
    expect(releaseNotesExcerpt(releaseJson()['body'] as String), 'New Features\n• One\n• Two');
    expect(releaseNotesExcerpt('- a\n- b\n- c', maxLines: 2), '• a\n• b');
  });

  test('handheldEntryTarget maps the port tree and rejects everything else', () {
    expect(handheldEntryTarget('ports/', mode: 0x41ed), isNull);
    expect(handheldEntryTarget('ports/retrotoolbox/', mode: 0x41ed), isNull);
    expect(handheldEntryTarget('ports/Retro Toolbox.sh', mode: 0x81ed), 'Retro Toolbox.sh');
    expect(handheldEntryTarget('ports/retrotoolbox/lib/libapp.so', mode: 0), 'retrotoolbox/lib/libapp.so');
    expect(handheldEntryTarget('ports/retrotoolbox/bin/', mode: 0x41ed), 'retrotoolbox/bin');
    for (final bad in [
      '../evil',
      '/abs/evil',
      'ports/retrotoolbox/../../evil',
      'ports/./retrotoolbox/x',
      'ports//retrotoolbox/x',
      r'ports\retrotoolbox\x',
      'other/x',
      'ports/other.sh',
      'ports/retrotoolboxx/x',
      'x',
    ]) {
      expect(() => handheldEntryTarget(bad, mode: 0x81a4), throwsA(isA<UpdateException>()), reason: bad);
    }
    expect(() => handheldEntryTarget('ports/retrotoolbox/l', mode: 0xa1ff, symlink: true),
        throwsA(isA<UpdateException>()));
    expect(() => handheldEntryTarget('ports/retrotoolbox/l', mode: 0xa1ff), throwsA(isA<UpdateException>()));
    expect(() => handheldEntryTarget('ports/retrotoolbox/fifo', mode: 0x11a4), throwsA(isA<UpdateException>()));
  });

  group('files', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('rt_update_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('verifyDownload accepts a matching file and rejects size, checksum or no checksum', () async {
      final bytes = utf8.encode('hello update');
      final f = File(p.join(tmp.path, 'a'))..writeAsBytesSync(bytes);
      final good = sha256.convert(bytes).toString();
      ReleaseAsset asset({int? size, String? sum}) =>
          ReleaseAsset(name: 'a', url: '', size: size ?? bytes.length, sha256: sum);

      await verifyDownload(f, asset(sum: good));
      await expectLater(verifyDownload(f, asset()), throwsA(predicate((e) => '$e' == cantVerifyMessage)));
      await expectLater(verifyDownload(f, asset(sum: '0' * 64)), throwsA(isA<UpdateException>()));
      await expectLater(verifyDownload(f, asset(size: 1, sum: good)), throwsA(isA<UpdateException>()));
    });

    test('stageHandheldUpdate lays out .update/ with READY last and explicit modes', () async {
      final archive = Archive()
        ..add(ArchiveFile.directory('ports/'))
        ..add(ArchiveFile.directory('ports/retrotoolbox/'))
        ..add(ArchiveFile.bytes('ports/Retro Toolbox.sh', utf8.encode('#!/bin/bash\n')))
        ..add(ArchiveFile.bytes('ports/retrotoolbox/flutter-pi', utf8.encode('bin'))..mode = 0x8fff)
        ..add(ArchiveFile.bytes('ports/retrotoolbox/bin/xdg-user-dir', utf8.encode('sh')))
        ..add(ArchiveFile.bytes('ports/retrotoolbox/data/flutter_assets/app.so', utf8.encode('so'))..mode = 0x8fff);
      final zip = File(p.join(tmp.path, 'u.zip'))..writeAsBytesSync(_unixZip(archive));
      final port = Directory(p.join(tmp.path, 'port'))..createSync();
      Directory(p.join(port.path, '.update', 'stale')).createSync(recursive: true);

      await stageHandheldUpdate(zip, port);

      final up = p.join(port.path, '.update');
      expect(File(p.join(up, 'READY')).existsSync(), isTrue);
      expect(File(p.join(up, 'Retro Toolbox.sh')).readAsStringSync(), '#!/bin/bash\n');
      expect(File(p.join(up, 'retrotoolbox', 'flutter-pi')).readAsStringSync(), 'bin');
      expect(File(p.join(up, 'retrotoolbox', 'data', 'flutter_assets', 'app.so')).existsSync(), isTrue);
      expect(Directory(up).listSync().map((e) => p.basename(e.path)).toSet(),
          {'READY', 'Retro Toolbox.sh', 'retrotoolbox'});
      if (!Platform.isWindows) {
        int mode(String rel) => File(p.join(up, rel)).statSync().mode & 0xfff;
        expect(mode('retrotoolbox/flutter-pi'), 0x1ed, reason: 'setuid etc. from the zip must not survive');
        expect(mode('retrotoolbox/bin/xdg-user-dir'), 0x1ed);
        expect(mode('Retro Toolbox.sh'), 0x1ed);
        expect(mode('retrotoolbox/data/flutter_assets/app.so'), 0x1a4);
      }
    });

    final hostile = <String, Archive Function()>{
      'a ../ entry': () => _port()..add(ArchiveFile.bytes('ports/retrotoolbox/../../escaped', [1])),
      'a leading ../ entry': () => _port()..add(ArchiveFile.bytes('../escaped', [1])),
      'an absolute path': () => _port()..add(ArchiveFile.bytes('/tmp/rt_update_escaped', [1])),
      'an entry outside ports/': () => _port()..add(ArchiveFile.bytes('escaped', [1])),
      'a relative symlink chain': () => _port()
        ..add(_link('ports/retrotoolbox/a', '..'))
        ..add(_link('ports/retrotoolbox/a/b', '..'))
        ..add(_link('ports/retrotoolbox/a/b/c', '..'))
        ..add(ArchiveFile.bytes('ports/retrotoolbox/a/b/c/escaped', [1])),
    };
    for (final MapEntry(key: what, value: build) in hostile.entries) {
      test('stageHandheldUpdate rejects a package with $what and writes nothing', () async {
        final zip = File(p.join(tmp.path, 'u.zip'))..writeAsBytesSync(_unixZip(build()));
        final port = Directory(p.join(tmp.path, 'deep', 'er', 'port'))..createSync(recursive: true);

        await expectLater(stageHandheldUpdate(zip, port), throwsA(isA<UpdateException>()));
        expect(Directory(p.join(port.path, '.update')).existsSync(), isFalse);
        final written = tmp.listSync(recursive: true).map((e) => p.basename(e.path));
        expect(written.where((n) => n.contains('escaped')), isEmpty);
        expect(File('/tmp/rt_update_escaped').existsSync(), isFalse);
      });
    }
  });

  group('failed install note', () {
    late Directory port;
    setUp(() => port = Directory.systemTemp.createTempSync('rt_note'));
    tearDown(() => port.deleteSync(recursive: true));

    test('failedInstallReason reads the first line of .update/FAILED, else null', () async {
      final service = UpdateService(portRoot: port.path);
      expect(service.failedInstallReason(), isNull);
      Directory('${port.path}/.update').createSync();
      expect(service.failedInstallReason(), isNull);
      File('${port.path}/.update/FAILED').writeAsStringSync('copy failed: rm xkb\nmore');
      expect(service.failedInstallReason(), 'copy failed: rm xkb');
      File('${port.path}/.update/FAILED').writeAsStringSync('\n');
      expect(service.failedInstallReason(), 'unknown reason');
    });

    test('discardStaged removes .update and UPDATE_FAILED.txt, nothing else', () async {
      Directory('${port.path}/.update/retrotoolbox').createSync(recursive: true);
      File('${port.path}/UPDATE_FAILED.txt').writeAsStringSync('x');
      File('${port.path}/flutter-pi').writeAsStringSync('bin');
      final service = UpdateService(portRoot: port.path);
      await service.discardStaged();
      await service.discardStaged(); // already gone: fine
      expect(Directory('${port.path}/.update').existsSync(), isFalse);
      expect(File('${port.path}/UPDATE_FAILED.txt').existsSync(), isFalse);
      expect(File('${port.path}/flutter-pi').existsSync(), isTrue);
    });

    test('only copy failures are called partial', () {
      expect(installFailedMessage('staged files incomplete'),
          "The last update couldn't be installed: staged files incomplete.");
      for (final r in ['copy failed', 'copy failed: rm app', 'launcher copy failed']) {
        expect(installFailedMessage(r), allOf(contains('reinstalled partially'), contains('release zip')));
      }
    });
  });

  group('network', () {
    late HttpServer server;
    late Directory cache;
    var status = 200;
    Object body = '';
    Map<String, String> headers = {};
    String? userAgent;

    setUp(() async {
      cache = Directory.systemTemp.createTempSync('rt_update_cache_');
      headers = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) {
        userAgent = req.headers.value(HttpHeaders.userAgentHeader);
        req.response.statusCode = status;
        headers.forEach(req.response.headers.set);
        body is List<int> ? req.response.add(body as List<int>) : req.response.write(body);
        req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      cache.deleteSync(recursive: true);
    });

    UpdateService service({int free = 1 << 40}) => UpdateService(
          releaseUrl: 'http://127.0.0.1:${server.port}/latest',
          cacheDir: () async => cache,
          portRoot: cache.path,
          isTrusted: (u) => u.host == '127.0.0.1',
          freeSpace: (_) async => free,
        );

    test('fetchLatest parses the release and sends a User-Agent', () async {
      status = 200;
      body = jsonEncode(releaseJson());
      final r = await service().fetchLatest();
      expect(r.version, '0.3.0');
      expect(userAgent, isNotEmpty);
    });

    test('fetchLatest maps rate limit, other 403s, missing releases and offline', () async {
      status = 403;
      body = '{}';
      headers = {'x-ratelimit-remaining': '0'};
      await expectLater(service().fetchLatest(), throwsA(predicate((e) => '$e'.contains('rate limit'))));
      headers = {};
      await expectLater(service().fetchLatest(), throwsA(predicate((e) => '$e'.contains('HTTP 403'))));
      status = 404;
      await expectLater(service().fetchLatest(), throwsA(predicate((e) => '$e'.contains('No releases'))));
      final offline =
          UpdateService(releaseUrl: 'http://127.0.0.1:1/latest', cacheDir: () async => cache, isTrusted: (_) => true);
      await expectLater(
          offline.fetchLatest(), throwsA(predicate((e) => e is UpdateException && '$e'.contains("Can't reach"))));
    });

    test('plain http and redirects off GitHub are refused before any request', () async {
      await expectLater(UpdateService(releaseUrl: 'http://127.0.0.1:${server.port}/latest').fetchLatest(),
          throwsA(predicate((e) => '$e'.contains('Refusing'))));
      userAgent = null;
      status = 302;
      headers = {'location': 'http://evil.invalid/payload'};
      await expectLater(service().fetchLatest(), throwsA(predicate((e) => '$e'.contains('Refusing'))));
      expect(userAgent, isNotNull, reason: 'the first hop was requested');
    });

    test('download reports progress and verifies; a bad checksum deletes the file, a missing one is refused', () async {
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
      expect(p.basename(ok.parent.path), 'updates');
      expect(progress.last, 1.0);

      await expectLater(
        service().download(ReleaseAsset(name: 'bad.apk', url: url, size: bytes.length, sha256: '0' * 64), (_) {}),
        throwsA(predicate((e) => '$e'.contains('checksum'))),
      );
      expect(File(p.join(cache.path, 'updates', 'bad.apk')).existsSync(), isFalse);
      await expectLater(
        service().download(ReleaseAsset(name: 'none.apk', url: url, size: bytes.length), (_) {}),
        throwsA(predicate((e) => '$e' == cantVerifyMessage)),
      );
    });

    test('ensureSpace proceeds when the free space is unknown, but still blocks on a real 0', () async {
      const asset = ReleaseAsset(name: 'a', url: '', size: 100, sha256: 'x');
      UpdateService unknown() => UpdateService(cacheDir: () async => cache, portRoot: cache.path, freeSpace: (_) async => null);
      await unknown().ensureSpace(asset, handheld: true);
      await unknown().ensureSpace(asset, handheld: false);
      await expectLater(service(free: 0).ensureSpace(asset, handheld: true), throwsA(isA<UpdateException>()));
    });

    test('ensureSpace wants 4x on the handheld and 2x on Android', () async {
      const asset = ReleaseAsset(name: 'a', url: '', size: 100, sha256: 'x');
      await service(free: 400).ensureSpace(asset, handheld: true);
      await expectLater(service(free: 399).ensureSpace(asset, handheld: true),
          throwsA(predicate((e) => '$e'.startsWith('Not enough free space'))));
      await service(free: 200).ensureSpace(asset, handheld: false);
      await expectLater(service(free: 199).ensureSpace(asset, handheld: false), throwsA(isA<UpdateException>()));
    });
  });
}

Archive _port() => Archive()
  ..add(ArchiveFile.bytes('ports/Retro Toolbox.sh', utf8.encode('#!/bin/bash\n')))
  ..add(ArchiveFile.bytes('ports/retrotoolbox/flutter-pi', utf8.encode('bin')));

ArchiveFile _link(String name, String target) => ArchiveFile.bytes(name, utf8.encode(target))..mode = 0xa1ff;

/// ZipEncoder marks every entry as made on MS-DOS, which hides unix modes
/// (and so symlinks) from the decoder; mark them as made on unix instead.
List<int> _unixZip(Archive archive) {
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  for (var i = 0; i + 5 < bytes.length; i++) {
    if (bytes[i] == 0x50 && bytes[i + 1] == 0x4b && bytes[i + 2] == 0x01 && bytes[i + 3] == 0x02) bytes[i + 5] = 3;
  }
  return bytes;
}
