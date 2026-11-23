import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_target.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/services/m3u_service.dart';

Game game(String file, {String console = 'psx'}) => Game(title: p.basenameWithoutExtension(file), url: 'https://example.com/$console/${Uri.encodeComponent(file)}', size: 1, consoleId: console);

PresetSystem system(List<String> extensions) => PresetSystem(slug: 'psx', extensions: extensions);

void main() {
  late Directory tmp;
  late String dir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-target-');
    dir = tmp.path;
  });
  tearDown(() => tmp.delete(recursive: true));

  String touch(String rel, [String body = '']) {
    final f = File(p.join(dir, rel))..createSync(recursive: true);
    f.writeAsStringSync(body);
    return f.path;
  }

  OwnedGame owned(String file, List<String> paths) => OwnedGame(game: game(file), dir: dir, paths: paths);

  test('a single file launches itself', () {
    final chd = touch('Crash.chd');
    final t = resolveLaunchTarget(owned('Crash.chd', [chd]), system(['chd']));
    expect(t.path, chd);
    expect(t.multiFile, isFalse);
  });

  test('an extracted folder launches its cue, not the bin beside it', () {
    final bin = touch('Spyro/Spyro (Track 1).bin');
    final cue = touch('Spyro/Spyro.cue');
    final t = resolveLaunchTarget(owned('Spyro.zip', [bin, cue]), system(['cue', 'bin']));
    expect(t.path, cue);
    expect(t.multiFile, isTrue);
  });

  test('a cue/bin pair at the root launches the cue', () {
    final bin = touch('Tekken.bin');
    final cue = touch('Tekken.cue');
    final t = resolveLaunchTarget(owned('Tekken.zip', [bin, cue]), system(['bin', 'cue', 'chd']));
    expect(t.path, cue);
  });

  test("a disc of a set with an m3u launches the m3u, with the m3u's discs", () {
    final d1 = touch('FF7 (Disc 1).chd');
    final d2 = touch('FF7 (Disc 2).chd');
    final m3u = touch('FF7.m3u', 'FF7 (Disc 1).chd\nFF7 (Disc 2).chd\n');
    final t = resolveLaunchTarget(owned('FF7 (Disc 2).chd', [d2]), system(['chd', 'm3u']));
    expect(t.path, m3u);
    expect(t.discs, [d1, d2]);
    expect(t.multiFile, isTrue);
  });

  test('an rvz two-disc set plus its m3u launches the m3u', () {
    touch('Tales (Disc 1).rvz');
    final d2 = touch('Tales (Disc 2).rvz');
    final m3u = touch('Tales.m3u', 'Tales (Disc 1).rvz\nTales (Disc 2).rvz\n');
    expect(M3uService.detectDiscSets(['Tales (Disc 1).rvz', 'Tales (Disc 2).rvz']), isEmpty, reason: 'the M3U screen keeps its own list');
    final t = resolveLaunchTarget(owned('Tales (Disc 2).rvz', [d2]), system(['rvz', 'm3u']));
    expect(t.path, m3u);
  });

  test('an m3u the preset does not open falls back to the disc', () {
    final d1 = touch('FF7 (Disc 1).chd');
    touch('FF7 (Disc 2).chd');
    touch('FF7.m3u', 'FF7 (Disc 1).chd\nFF7 (Disc 2).chd\n');
    final t = resolveLaunchTarget(owned('FF7 (Disc 1).chd', [d1]), system(['chd']));
    expect(t.path, d1);
  });

  test("a game beside another set's m3u launches itself, not that set", () {
    final crash = touch('Crash.chd');
    touch('FF7 (Disc 1).chd');
    touch('FF7 (Disc 2).chd');
    touch('FF7.m3u', 'FF7 (Disc 1).chd\nFF7 (Disc 2).chd\n');
    final t = resolveLaunchTarget(owned('Crash.chd', [crash]), system(['chd', 'm3u']));
    expect(t.path, crash);
  });

  test('a folder of discs and no m3u launches disc 1, whatever order the folder lists them in', () {
    final d2 = touch('FF7/FF7 (Disc 2).cue');
    final b2 = touch('FF7/FF7 (Disc 2).bin');
    final d1 = touch('FF7/FF7 (Disc 1).cue');
    final b1 = touch('FF7/FF7 (Disc 1).bin');
    final t = resolveLaunchTarget(owned('FF7.zip', [d2, b2, d1, b1]), system(['cue', 'bin']));
    expect(t.path, d1);
  });

  test('a set of discs keeps the place of its first listed disc among the files of its rank', () {
    final d2 = touch('FF7/FF7 (Disc 2).cue');
    final extras = touch('FF7/Extras.cue');
    final d1 = touch('FF7/FF7 (Disc 1).cue');
    final t = resolveLaunchTarget(owned('FF7.zip', [d2, extras, d1]), system(['cue']));
    expect(t.path, d1);
  });

  test('a zip the emulator does not take, with no extracted copy, is unsupported', () {
    final zip = touch('Ridge Racer.zip');
    final t = resolveLaunchTarget(owned('Ridge Racer.zip', [zip]), system(['chd', 'cue']));
    expect(t.supported, isFalse);
    expect(t.unsupportedExtension, 'zip');
  });

  test('a game with no files is unsupported with no extension', () {
    final t = resolveLaunchTarget(owned('Gone.chd', const []), system(['chd']));
    expect(t.supported, isFalse);
    expect(t.unsupportedExtension, isNull);
  });

  test('a system with no extensions opens any file, the best ranked one first', () {
    final bin = touch('Spyro/Spyro.bin');
    final cue = touch('Spyro/Spyro.cue');
    expect(resolveLaunchTarget(owned('Spyro.zip', [bin, cue]), system(const [])).path, cue);
    final zip = touch('Ridge Racer.zip');
    expect(resolveLaunchTarget(owned('Ridge Racer.zip', [zip]), system(const [])).path, zip);
  });

  group('OwnedGame.fromPresence', () {
    LibrarySnapshot snap(Map<String, List<String>> related) =>
        LibrarySnapshot(libraryDir: dir, exactFiles: const {}, baseNames: const {}, relatedFiles: related, timestamp: DateTime(2026));

    test('a file presence is the file in the dir', () {
      final o = OwnedGame.fromPresence(game('Crash.chd'), dir, LibraryPresence.file, snap(const {}))!;
      expect(o.paths, [p.join(dir, 'Crash.chd')]);
    });

    // The snapshot keeps the directory's listing order, which differs between devices.
    test("an extracted presence is the folder's files, sorted by path", () {
      final cue = p.join(dir, 'Spyro', 'Spyro.cue'), bin = p.join(dir, 'Spyro', 'Spyro.bin');
      final o = OwnedGame.fromPresence(game('Spyro.zip'), dir, LibraryPresence.extracted, snap({'Spyro': [cue, bin]}))!;
      expect(o.paths, [bin, cue]);
    });

    test('a kept archive comes after its extracted files, which are sorted by path', () {
      final cue = p.join(dir, 'Spyro', 'Spyro.cue'), bin = p.join(dir, 'Spyro', 'Spyro.bin');
      final o = OwnedGame.fromPresence(game('Spyro.zip'), dir, LibraryPresence.fileAndExtracted, snap({'Spyro': [cue, bin]}))!;
      expect(o.paths, [bin, cue, p.join(dir, 'Spyro.zip')]);
    });

    test('no presence is not owned', () {
      expect(OwnedGame.fromPresence(game('Crash.chd'), dir, LibraryPresence.none, snap(const {})), isNull);
    });
  });
}
