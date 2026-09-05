import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/services/m3u_service.dart';

void main() {
  test('detectDiscSets groups multi-disc titles and orders by disc number', () {
    final sets = M3uService.detectDiscSets([
      'Final Fantasy VII (USA) (Disc 2).chd',
      'Final Fantasy VII (USA) (Disc 1).chd',
      'Final Fantasy VII (USA) (Disc 3).chd',
      'Tetris.chd',
    ]);
    expect(sets.length, 1);
    expect(sets.first.base, 'Final Fantasy VII (USA)');
    expect(sets.first.discs, [
      'Final Fantasy VII (USA) (Disc 1).chd',
      'Final Fantasy VII (USA) (Disc 2).chd',
      'Final Fantasy VII (USA) (Disc 3).chd',
    ]);
  });

  test('detectDiscSets accepts Disk/CD spellings, case-insensitive', () {
    final sets = M3uService.detectDiscSets([
      'Game (DISK 1).cue',
      'Game (disk 2).cue',
    ]);
    expect(sets.length, 1);
    expect(sets.first.discs.length, 2);
  });

  test('detectDiscSets ignores singletons and non-disc media', () {
    final sets = M3uService.detectDiscSets([
      'Solo Game (Disc 1).chd',
      'Raw (Disc 1).bin',
      'Raw (Disc 2).bin',
    ]);
    expect(sets, isEmpty);
  });

  test('scan + writeM3u writes an ordered playlist of basenames', () {
    final dir = Directory.systemTemp.createTempSync('m3u_test');
    addTearDown(() => dir.existsSync() ? dir.deleteSync(recursive: true) : null);
    for (final n in [2, 1]) {
      File(p.join(dir.path, 'Cool Game (Disc $n).chd')).writeAsStringSync('x');
    }
    final service = M3uService();
    final sets = service.scanDiscSets(dir);
    expect(sets.length, 1);

    service.writeM3u(dir, sets.first);
    final m3u = File(p.join(dir.path, 'Cool Game.m3u'));
    expect(m3u.existsSync(), true);
    expect(m3u.readAsLinesSync(), ['Cool Game (Disc 1).chd', 'Cool Game (Disc 2).chd']);
  });
}
