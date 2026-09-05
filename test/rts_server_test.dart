import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/rts_folder_model.dart';
import 'package:roms_downloader/services/rts_server_service.dart';

void main() {
  test('buildConsolesJson emits consumable console entries', () {
    final folders = [
      const RtsFolder(path: '/roms/snes', name: 'SNES', formats: ['.zip', '.chd'], boxartsUrl: 'https://box/', romsSubfolder: 'snes'),
    ];
    final decoded = jsonDecode(RtsServerService.buildConsolesJson(folders, '192.168.0.5:8090')) as List;
    expect(decoded.length, 1);
    final c = decoded.first as Map<String, dynamic>;
    expect(c['name'], 'SNES');
    expect(c['url'], 'http://192.168.0.5:8090/f/0/');
    expect(c['file_format'], ['.zip', '.chd']);
    expect(c['boxarts'], {'url': 'https://box/'});
    expect(c['roms_folder'], 'snes');
    expect(c['regex'], RtsServerService.listingRegex);
  });

  test('listing HTML round-trips through the baked-in regex', () {
    final files = [
      (name: 'Tom & Jerry (USA).zip', size: 1234567),
      (name: 'Zelda.chd', size: 42),
    ];
    final html = RtsServerService.buildListingHtml(files);
    final re = RegExp(RtsServerService.listingRegex, multiLine: true, dotAll: true);
    final matches = re.allMatches(html).toList();
    expect(matches.length, 2);

    // The consumer builds fullUrl = baseUrl + href and title = text group.
    for (var i = 0; i < files.length; i++) {
      final m = matches[i];
      expect(m.namedGroup('text'), files[i].name);
      expect(Uri.decodeComponent(m.namedGroup('href')!), files[i].name);
      expect(m.namedGroup('size')!.isNotEmpty, true);
    }
  });

  test('server serves consoles.json, listing, and file (with range)', () async {
    final dir = Directory.systemTemp.createTempSync('rts_serve');
    addTearDown(() => dir.existsSync() ? dir.deleteSync(recursive: true) : null);
    File(p.join(dir.path, 'Game.zip')).writeAsStringSync('HELLO-WORLD');

    final svc = RtsServerService();
    await svc.start(port: 0, folders: [RtsFolder(path: dir.path, name: 'Test', formats: const ['.zip'], romsSubfolder: 'test')]);
    addTearDown(svc.stop);
    final base = 'http://127.0.0.1:${svc.port}';
    final client = HttpClient();

    Future<String> get(String path, {String? range}) async {
      final r = await client.getUrl(Uri.parse('$base$path'));
      if (range != null) r.headers.set(HttpHeaders.rangeHeader, range);
      final resp = await r.close();
      return resp.transform(const SystemEncoding().decoder).join();
    }

    final consoles = jsonDecode(await get('/consoles.json')) as List;
    expect((consoles.first as Map)['url'], 'http://127.0.0.1:${svc.port}/f/0/');

    final listing = await get('/f/0/');
    expect(listing.contains('Game.zip'), true);

    expect(await get('/f/0/Game.zip'), 'HELLO-WORLD');
    expect(await get('/f/0/Game.zip', range: 'bytes=0-4'), 'HELLO'); // resume slice
    client.close();
  });

  test('listFiles filters by extension and sorts', () {
    final dir = Directory.systemTemp.createTempSync('rts_test');
    addTearDown(() => dir.existsSync() ? dir.deleteSync(recursive: true) : null);
    for (final n in ['b.zip', 'a.zip', 'note.txt', 'game.chd']) {
      File(p.join(dir.path, n)).writeAsStringSync('x');
    }
    final zips = RtsServerService.listFiles(dir, ['.zip']);
    expect(zips.map((f) => f.name), ['a.zip', 'b.zip']);
    final all = RtsServerService.listFiles(dir, const []);
    expect(all.length, 4);
  });
}
