import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';

import 'save_sync_backend_contract.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('hub'));
  tearDown(() => tmp.deleteSync(recursive: true));

  FolderBackend make() => FolderBackend(Directory(p.join(tmp.path, 'Retro Toolbox Saves')));

  group('contract', () => backendContract(() async => make()));

  test('a replace leaves no temp file, and a sync app\'s dot folder stays hidden', () async {
    final hub = make();
    await hub.write('devices/thor.json', [1]);
    await hub.write('devices/thor.json', [2]);
    File(p.join(hub.root.path, 'devices', '.stfolder')).writeAsStringSync('');
    expect((await hub.list('devices')).map((e) => e.name), ['thor.json']);
    expect(Directory(p.join(hub.root.path, 'devices')).listSync().map((e) => p.basename(e.path)).where((n) => n.startsWith('.rt-tmp')), isEmpty);
  });

  test('id names the folder', () {
    final hub = make();
    expect(hub.id, 'folder:${p.normalize(hub.root.path)}');
  });
}
