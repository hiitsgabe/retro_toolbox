import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/local_history.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';

void main() {
  late Directory tmp;
  late String game;
  late LocalHistory history;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('history');
    game = p.join(tmp.path, 'Android/data/com.chucklefish.stardewvalley/files/Saves');
    File(p.join(game, 'Farm_1/Farm_1'))
      ..createSync(recursive: true)
      ..writeAsStringSync('v1');
    File(p.join(game, 'Farm_1/SaveGameInfo')).writeAsStringSync('info');
    final sync = p.join(tmp.path, 'RetroToolbox/SaveSync');
    final fs = ShellGameFs(ProcessShell(), PathGuard([p.join(tmp.path, 'Android/data/com.chucklefish.stardewvalley'), sync]));
    history = LocalHistory(p.join(sync, 'history'), fs, keep: 2);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('snapshot copies the unit files into a new entry', () async {
    final entry = await history.newEntry('stardew-valley', 'Farm_1', 'before-g1', now: DateTime.utc(2026, 11, 10, 22, 41, 7));
    expect(p.basename(entry), '20261110T224107Z-before-g1');
    await history.snapshot(entry, game, ['Farm_1/Farm_1', 'Farm_1/SaveGameInfo']);
    expect(File(p.join(entry, 'Farm_1/Farm_1')).readAsStringSync(), 'v1');
    expect(File(p.join(entry, 'Farm_1/SaveGameInfo')).readAsStringSync(), 'info');
  });

  test('two entries in the same second get distinct folders', () async {
    final t = DateTime.utc(2026, 11, 10);
    final a = await history.newEntry('stardew-valley', 'Farm_1', 'x', now: t);
    final b = await history.newEntry('stardew-valley', 'Farm_1', 'x', now: t);
    expect(a, isNot(b));
  });

  test('entries are newest first and trim keeps the newest N', () async {
    for (var i = 0; i < 4; i++) {
      await history.newEntry('stardew-valley', 'Farm_1', 'e$i', now: DateTime.utc(2026, 11, 10, i));
    }
    await history.trim('stardew-valley', 'Farm_1');
    expect(await history.entries('stardew-valley', 'Farm_1'), ['20261110T030000Z-e3', '20261110T020000Z-e2']);
    expect(await history.entries('stardew-valley', 'nothing'), isEmpty);
  });

  test('trim spares the entry it is told to, even when a clock that ran ahead makes it look oldest', () async {
    for (var i = 0; i < 2; i++) {
      await history.newEntry('stardew-valley', 'Farm_1', 'e$i', now: DateTime.utc(2030, 1, 1, i));
    }
    final mine = await history.newEntry('stardew-valley', 'Farm_1', 'before-g', now: DateTime.utc(2026, 11, 11));
    await history.trim('stardew-valley', 'Farm_1', except: mine);
    expect(await history.entries('stardew-valley', 'Farm_1'), ['20300101T010000Z-e1', '20300101T000000Z-e0', p.basename(mine)]);
  });
}
