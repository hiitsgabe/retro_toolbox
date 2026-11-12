import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';

void main() {
  late Directory tmp;
  late FolderBackend hub;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('hub');
    hub = FolderBackend(Directory(p.join(tmp.path, 'Retro Toolbox Saves')));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('write creates parents, read returns the bytes, list shows files and folders', () async {
    await hub.write('units/stardew-valley/Farm_1/a.json', utf8.encode('{}'));
    await hub.write('hub.json', utf8.encode('{"format":1}'));
    expect(utf8.decode(await hub.read('hub.json')), '{"format":1}');
    final top = await hub.list('');
    expect(top.map((e) => '${e.name}:${e.isDir}'), ['hub.json:false', 'units:true']);
    final unit = await hub.list('units/stardew-valley/Farm_1');
    expect(unit.single.name, 'a.json');
    expect(unit.single.size, 2);
  });

  test('a missing folder lists as empty; delete of a missing file is fine', () async {
    expect(await hub.list('units/nothing'), isEmpty);
    await hub.delete('units/nothing/x.json');
  });

  test('write replaces atomically and leaves no temp file; dot files are hidden', () async {
    await hub.write('devices/thor.json', utf8.encode('1'));
    await hub.write('devices/thor.json', utf8.encode('2'));
    File(p.join(hub.root.path, 'devices', '.stfolder')).writeAsStringSync('');
    expect(utf8.decode(await hub.read('devices/thor.json')), '2');
    expect((await hub.list('devices')).map((e) => e.name), ['thor.json']);
    expect(Directory(p.join(hub.root.path, 'devices')).listSync().map((e) => p.basename(e.path)).where((n) => n.startsWith('.rt-tmp')), isEmpty);
  });

  test('unsafe paths are refused', () async {
    expect(() => hub.write('../escape.json', [1]), throwsArgumentError);
    expect(() => hub.read('/etc/passwd'), throwsArgumentError);
  });

  test('id names the folder', () {
    expect(hub.id, 'folder:${p.normalize(hub.root.path)}');
  });
}
