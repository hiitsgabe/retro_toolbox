import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/jksv_folder_source.dart';
import 'package:retro_toolbox/services/jksv_meta.dart';
import 'package:retro_toolbox/services/jksv_source.dart';
import 'package:retro_toolbox/services/webdav_server_service.dart';

Future<HttpClientResponse> _req(String method, Uri url, {List<int>? body}) async {
  final client = HttpClient();
  final r = await client.openUrl(method, url);
  if (method == 'PROPFIND') r.headers.set('Depth', '1');
  if (body != null) r.add(body);
  final res = await r.close();
  return res;
}

/// Answers every read after a real delay, so a server that did not await the
/// source would serve an empty listing or no bytes.
class _DelayedSource implements JksvSource {
  final Map<String, List<int>> zips;
  final Set<String> broken;
  _DelayedSource(this.zips, {this.broken = const {}});

  Future<void> _wait() => Future.delayed(const Duration(milliseconds: 30));

  @override
  Future<List<String>> titleIds() async {
    await _wait();
    return [...zips.keys, ...broken];
  }

  @override
  String displayName(String titleId) => 'Game $titleId';

  @override
  Future<List<int>> backupZip(String titleId) async {
    await _wait();
    final zip = zips[titleId];
    if (zip == null) throw StateError('no save for $titleId');
    return zip;
  }

  @override
  Future<void> applyIncoming(String titleId, List<int> jksvZip, {required String timestamp}) => throw UnimplementedError();
}

void main() {
  group('folder source', _folderSourceTests);
  group('async source', _asyncSourceTests);
}

void _asyncSourceTests() {
  late WebDavServerService server;
  const id = '0100ABCD00001000';
  final zip = ZipEncoder().encode(Archive()..addFile(ArchiveFile('slot00', 3, 'abc'.codeUnits)));

  setUp(() async {
    server = WebDavServerService();
    await server.start(port: 0, source: _DelayedSource({id: zip}, broken: {'0100EEEE00002000'}));
  });

  tearDown(() => server.stop());

  Uri base(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('PROPFIND / waits for the title list', () async {
    final res = await _req('PROPFIND', base('/'));
    expect(res.statusCode, 207);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('<d:href>/Game%20$id</d:href>'));
  });

  test('PROPFIND /<title> reports the awaited zip length', () async {
    final res = await _req('PROPFIND', base('/Game%20$id'));
    expect(res.statusCode, 207);
    final body = await res.transform(utf8.decoder).join();
    expect(body, contains('<d:getcontentlength>${zip.length}</d:getcontentlength>'));
  });

  test('GET returns the awaited zip bytes', () async {
    final res = await _req('GET', base('/Game%20$id/Game%20$id.zip'));
    expect(res.statusCode, 200);
    expect(await res.fold<List<int>>([], (a, b) => a..addAll(b)), zip);
  });

  test('a title whose backup fails answers 404', () async {
    final get = await _req('GET', base('/Game%200100EEEE00002000/Game%200100EEEE00002000.zip'));
    expect(get.statusCode, 404);
    await get.drain<void>();
    final find = await _req('PROPFIND', base('/Game%200100EEEE00002000'));
    expect(find.statusCode, 404);
    await find.drain<void>();
  });
}

void _folderSourceTests() {
  late Directory root;
  late WebDavServerService server;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('webdav_test');
    final export = Archive()..addFile(ArchiveFile('010043600B6A6000/slot00', 8, 'savedata'.codeUnits));
    File(p.join(root.path, 'My Game.zip')).writeAsBytesSync(ZipEncoder().encode(export));
    server = WebDavServerService();
    await server.start(port: 0, source: FolderJksvSource(root: root, nameFor: (_) => 'My Game'));
  });

  tearDown(() async {
    await server.stop();
    root.deleteSync(recursive: true);
  });

  Uri base(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

  test('PROPFIND / lists a collection per title', () async {
    final res = await _req('PROPFIND', base('/'));
    expect(res.statusCode, 207);
    final body = await res.transform(utf8.decoder).join();
    expect(body.contains('My%20Game'), isTrue);
    expect(body.contains('<d:collection/>'), isTrue);
  });

  test('PROPFIND /<title> lists the backup zip with a length', () async {
    final res = await _req('PROPFIND', base('/My%20Game'));
    expect(res.statusCode, 207);
    final body = await res.transform(utf8.decoder).join();
    expect(body.contains('.zip'), isTrue);
    expect(body.contains('<d:getcontentlength>'), isTrue);
  });

  test('GET returns a zip with raw save at root plus meta', () async {
    final res = await _req('GET', base('/My%20Game/My%20Game.zip'));
    expect(res.statusCode, 200);
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.map((e) => e.name).toSet();
    expect(names.contains('slot00'), isTrue);
    expect(names.contains(JksvMeta.fileName), isTrue);
  });

  test('PUT stages an incoming save by title id from its meta', () async {
    final incoming = Archive()
      ..addFile(ArchiveFile('slot00', 3, 'NEW'.codeUnits))
      ..addFile(ArchiveFile(JksvMeta.fileName, JksvMeta.size, JksvMeta.encode(applicationId: 0x0100AAAA00001000)));
    final res = await _req('PUT', base('/Whatever/backup.zip'), body: ZipEncoder().encode(incoming));
    expect(res.statusCode, 201);
    expect(server.incoming.value.single.titleId, '0100AAAA00001000');
  });
}
