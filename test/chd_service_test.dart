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

    test('never reaches outside the cue folder', () {
      final outside = File(p.join(dir.parent.path, 'rt_outside_${dir.hashCode}.bin'))..writeAsStringSync('x');
      addTearDown(() => outside.deleteSync());
      final cue = touch('game.cue', 'FILE "../${p.basename(outside.path)}" BINARY\nFILE "${outside.path}" BINARY\n');
      expect(ChdService.consumedFiles(cue), [cue]);
    });

    test('within limits tracks to the given files', () {
      final mine = touch('game.bin');
      final other = touch('other.bin');
      final cue = touch('game.cue', 'FILE "game.bin" BINARY\nFILE "other.bin" BINARY\n');
      expect(ChdService.consumedFiles(cue, within: {cue, mine}).toSet(), {cue, mine});
      expect(File(other).existsSync(), true);
    });

    test('iso is itself', () {
      final iso = touch('game.iso');
      expect(ChdService.consumedFiles(iso), [iso]);
    });
  });

  // Real chdman runs: the macOS binary bundled in assets.
  final chdman = p.absolute('assets/chdman/macos/chdman');
  final noChdman = Platform.isMacOS && File(chdman).existsSync() ? null : 'needs the bundled macOS chdman';

  group('CHD round trip for patching', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('chd_patch_'));
    tearDown(() => root.deleteSync(recursive: true));

    /// A two-track disc set ("Game (Track 1).bin" data, Track 2 audio) and its .cue in [dir].
    String disc(String dir, String base) {
      Directory(dir).createSync(recursive: true);
      File(p.join(dir, '$base (Track 1).bin')).writeAsBytesSync(List.filled(2352 * 300, 7));
      File(p.join(dir, '$base (Track 2).bin')).writeAsBytesSync(List.filled(2352 * 150, 0));
      final cue = File(p.join(dir, '$base.cue'))
        ..writeAsStringSync('FILE "$base (Track 1).bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n'
            'FILE "$base (Track 2).bin" BINARY\n  TRACK 02 AUDIO\n    INDEX 00 00:00:00\n    INDEX 01 00:02:00\n');
      return cue.path;
    }

    Future<String> chdOf(String cue) => ChdService()
        .convert(inputPath: cue, outputDir: p.dirname(cue), chdmanPath: chdman, onProgress: (_) {});

    test('unpacks a CD image to a .cue with one bin per track, as a dump has', () async {
      final chd = await chdOf(disc(p.join(root.path, 'src'), 'Game'));
      final cue = await ChdService.unpackForReading(chd, cacheRoot: p.join(root.path, 'cache'), chdmanPath: chdman);
      expect(p.basename(cue), 'Game.cue');
      final bins = Directory(p.dirname(cue)).listSync().map((e) => p.basename(e.path)).where((n) => n.endsWith('.bin')).toList()..sort();
      expect(bins, ['Game (Track 1).bin', 'Game (Track 2).bin']);
      expect(File(p.join(p.dirname(cue), 'Game (Track 1).bin')).readAsBytesSync().first, 7);
    }, skip: noChdman);

    test('reuses the unpacked copy of the same CHD, and keeps only the latest game', () async {
      final cache = p.join(root.path, 'cache');
      final a = await chdOf(disc(p.join(root.path, 'a'), 'Alpha'));
      final b = await chdOf(disc(p.join(root.path, 'b'), 'Beta'));
      final first = await ChdService.unpackForReading(a, cacheRoot: cache, chdmanPath: chdman);
      final stamp = File(first).lastModifiedSync();
      expect(await ChdService.unpackForReading(a, cacheRoot: cache, chdmanPath: chdman), first);
      expect(File(first).lastModifiedSync(), stamp);
      await ChdService.unpackForReading(b, cacheRoot: cache, chdmanPath: chdman);
      expect(File(first).existsSync(), isFalse);
    }, skip: noChdman);

    test('the same CHD asked twice at once unpacks once', () async {
      final chd = await chdOf(disc(p.join(root.path, 'src'), 'Game'));
      final cache = p.join(root.path, 'cache');
      final both = await Future.wait([
        ChdService.unpackForReading(chd, cacheRoot: cache, chdmanPath: chdman),
        ChdService.unpackForReading(chd, cacheRoot: cache, chdmanPath: chdman),
      ]);
      expect(both[0], both[1]);
      expect(File(both[0]).existsSync(), isTrue);
    }, skip: noChdman);

    test('repacks a patched set into one .chd beside it and removes the set', () async {
      final out = p.join(root.path, 'out');
      disc(out, 'League 2026 - Game');
      final chd = await ChdService.repackPatched(p.join(out, 'League 2026 - Game (Track 1).bin'), chdmanPath: chdman);
      expect(p.basename(chd), 'League 2026 - Game.chd');
      expect(Directory(out).listSync().map((e) => p.basename(e.path)).toList(), ['League 2026 - Game.chd']);
    }, skip: noChdman);

    test('repacks a patched .iso', () async {
      final out = Directory(p.join(root.path, 'out'))..createSync();
      File(p.join(out.path, 'League 2026 - Game.iso')).writeAsBytesSync(List.filled(2048 * 64, 1));
      final chd = await ChdService.repackPatched(p.join(out.path, 'League 2026 - Game.iso'), chdmanPath: chdman);
      expect(p.basename(chd), 'League 2026 - Game.chd');
      expect(File(p.join(out.path, 'League 2026 - Game.iso')).existsSync(), isFalse);
    }, skip: noChdman);
  });
}
