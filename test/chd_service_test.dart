import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/chd_service.dart';

void main() {
  test('modeForInput: .chd extracts, everything else compresses', () {
    expect(ChdService.modeForInput('game.chd'), ChdMode.extract);
    expect(ChdService.modeForInput('game.cue'), ChdMode.compress);
    expect(ChdService.modeForInput('game.ISO'), ChdMode.compress);
  });

  test('planFor: picks the right chdman subcommand per extension', () {
    expect(ChdService.planFor('g.cue')?.command, 'createcd');
    expect(ChdService.planFor('g.gdi')?.command, 'createcd');
    expect(ChdService.planFor('g.iso')?.command, 'createdvd');
    expect(ChdService.planFor('g.chd')?.command, 'extractcd');
    expect(ChdService.planFor('g.chd')?.outExt, '.cue');
    expect(ChdService.planFor('g.cue')?.outExt, '.chd');
    expect(ChdService.planFor('g.txt'), isNull);
  });

  test('extractPlanFromChdInfo picks cd vs dvd from info metadata', () {
    final cd = "Metadata: Tag='CHT2' Index=0\n  TRACK:1 TYPE:MODE1_RAW";
    final dvd = "Metadata: Tag='DVD ' Index=0 Length=1 bytes";
    expect(ChdService.extractPlanFromChdInfo(cd).command, 'extractcd');
    expect(ChdService.extractPlanFromChdInfo(cd).outExt, '.cue');
    expect(ChdService.extractPlanFromChdInfo(dvd).command, 'extractdvd');
    expect(ChdService.extractPlanFromChdInfo(dvd).outExt, '.iso');
  });

  test('parseProgress reads chdman percentage lines', () {
    expect(ChdService.parseProgress('Compressing, 0.0% complete...'), 0.0);
    expect(ChdService.parseProgress('Compressing, 42.3% complete...'), closeTo(0.423, 1e-9));
    expect(ChdService.parseProgress('Extracting, 100.0% complete'), 1.0);
    expect(ChdService.parseProgress('Output CHD:   game.chd'), isNull);
  });

  group('consumedFiles', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rt_chd'));
    tearDown(() => dir.deleteSync(recursive: true));

    String touch(String name, [String body = 'x']) {
      final f = File(p.join(dir.path, name))..writeAsStringSync(body);
      return f.path;
    }

    test('reads quoted cue tracks', () {
      final t1 = touch('game (Track 1).bin');
      final t2 = touch('game (Track 2).bin');
      final cue = touch('game.cue', 'FILE "game (Track 1).bin" BINARY\n  TRACK 01 MODE2/2352\nFILE "game (Track 2).bin" BINARY\n');
      expect(ChdService.consumedFiles(cue).toSet(), {cue, t1, t2});
    });

    test('skips missing tracks', () {
      final cue = touch('game.cue', 'FILE "gone.bin" BINARY\n');
      expect(ChdService.consumedFiles(cue), [cue]);
    });

    test('reads gdi tracks', () {
      final t1 = touch('track01.bin');
      final t2 = touch('track 02.raw');
      final gdi = touch('disc.gdi', '2\n1 0 4 2352 track01.bin 0\n2 600 0 2352 "track 02.raw" 0\n');
      expect(ChdService.consumedFiles(gdi).toSet(), {gdi, t1, t2});
    });

    test('iso is itself', () {
      final iso = touch('game.iso');
      expect(ChdService.consumedFiles(iso), [iso]);
    });
  });
}
