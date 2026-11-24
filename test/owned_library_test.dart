import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/services/launcher/games_on_disk.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/services/launcher/owned_library.dart';

// A cue/bin console whose handler writes .chd, a zip console that unpacks to
// .sfc, and a console sharing the PlayStation's .chd.
const _psx = Console(id: 'psx', name: 'PlayStation', urls: [], gameFilesFormat: ['.cue', '.bin'], additionalHandler: GameHandler.chdCompress);
const _snes = Console(id: 'snes', name: 'Super Nintendo', urls: [], originalFormat: ['.zip'], gameFilesFormat: ['.sfc', '.smc']);
const _ps2 = Console(id: 'ps2', name: 'PlayStation 2', urls: [], gameFilesFormat: ['.iso', '.chd']);

Game _catalog(String name, {String console = 'psx'}) => Game(title: name, url: 'https://example.com/${Uri.encodeComponent(name)}', size: 1, consoleId: console);

void main() {
  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('rt-owned-lib-'));
  tearDown(() => tmp.delete(recursive: true));

  void touch(String rel, [String text = 'x']) => File(p.join(tmp.path, rel))
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  Future<OwnedLibrary> scan(Console console,
      {List<Game> catalog = const [], List<Console> sharing = const [], String? dir, bool folders = true, Set<String> skip = const {}}) async {
    final d = dir ?? tmp.path;
    final snapshot = await LibrarySnapshotNotifier(d).current();
    return OwnedLibrary.scan((consoleId: console.id, dir: d, formats: ownFormats(console, [console, ...sharing]), snapshot: snapshot, catalog: catalog, folders: folders, skip: skip));
  }

  List<String> titles(OwnedLibrary lib) => [for (final g in lib.games) g.title];
  List<String> files(OwnedLibrary lib, String title) => lib.paths[lib.games.singleWhere((g) => g.title == title).gameId]!;
  String abs(String rel) => p.join(tmp.path, rel);

  test('loose files are the ones no present catalog game claims', () async {
    touch('Crash (USA).chd');
    touch('Spyro (USA).chd');
    touch('notes.txt');
    final lib = await scan(_psx, catalog: [_catalog('Crash (USA).chd'), _catalog('Tekken 3 (USA).chd')]);
    expect(titles(lib), ['Spyro (USA)']);
    expect(files(lib, 'Spyro (USA)'), [abs('Spyro (USA).chd')]);
  });

  test('a loose game is a local:// game on disk: title, size, parsed metadata', () async {
    touch('Spyro (Europe) (Rev 1).chd', 'abcd');
    final game = (await scan(_psx)).games.single;
    expect(game.url, 'local://psx/Spyro%20(Europe)%20(Rev%201).chd');
    expect(game.isLocal, isTrue);
    expect(game.consoleId, 'psx');
    expect(game.filename, 'Spyro (Europe) (Rev 1).chd');
    expect(game.size, 4);
    expect(game.metadata?.regions, ['Europe']);
    expect(game.metadata?.revision, '1');
  });

  test('a folder with a game one level down is one game, by its folder name, with its files', () async {
    touch('Vagrant Story/Vagrant Story.cue');
    touch('Vagrant Story/Vagrant Story.bin');
    touch('Vagrant Story/readme.txt');
    touch('Empty/readme.txt');
    final lib = await scan(_psx);
    expect(titles(lib), ['Vagrant Story']);
    expect(lib.games.single.filename, 'Vagrant Story');
    expect(files(lib, 'Vagrant Story'), [abs('Vagrant Story/Vagrant Story.bin'), abs('Vagrant Story/Vagrant Story.cue'), abs('Vagrant Story/readme.txt')]);
  });

  test('with folders off a folder is no game, and a skipped folder never is one', () async {
    touch('Vagrant Story/Vagrant Story.cue');
    touch('updates/Patch.cue');
    touch('Crash.chd');
    expect(titles(await scan(_psx)), ['Crash', 'Vagrant Story', 'updates']);
    expect(titles(await scan(_psx, skip: {p.join(tmp.path, 'updates')})), ['Crash', 'Vagrant Story']);
    expect(titles(await scan(_psx, folders: false)), ['Crash']);
  });

  test('a cue and the tracks it names are one game, named by the cue', () async {
    touch('Rayman (USA).cue', 'FILE "Rayman (USA) (Track 1).bin" BINARY\n  TRACK 01 MODE2/2352\nFILE "Rayman (USA) (Track 2).bin" BINARY\n');
    touch('Rayman (USA) (Track 1).bin');
    touch('Rayman (USA) (Track 2).bin');
    final lib = await scan(_psx);
    expect(titles(lib), ['Rayman (USA)']);
    expect(lib.games.single.filename, 'Rayman (USA).cue');
    expect(files(lib, 'Rayman (USA)'), [abs('Rayman (USA) (Track 1).bin'), abs('Rayman (USA) (Track 2).bin'), abs('Rayman (USA).cue')]);
  });

  test('the discs of a set, and its m3u, are one game named by the set', () async {
    touch('Final Fantasy VII (USA) (Disc 1).chd');
    touch('Final Fantasy VII (USA) (Disc 2).chd');
    touch('Final Fantasy VII (USA).m3u', 'Final Fantasy VII (USA) (Disc 1).chd\nFinal Fantasy VII (USA) (Disc 2).chd\n');
    final lib = await scan(_psx);
    expect(titles(lib), ['Final Fantasy VII (USA)']);
    expect(lib.games.single.filename, 'Final Fantasy VII (USA) (Disc 1).chd', reason: 'the first disc names it, so adding an m3u keeps the id');
    expect(files(lib, 'Final Fantasy VII (USA)'), [
      abs('Final Fantasy VII (USA) (Disc 1).chd'),
      abs('Final Fantasy VII (USA) (Disc 2).chd'),
      abs('Final Fantasy VII (USA).m3u'),
    ]);
  });

  test('an archive and the folder it was extracted to are one game', () async {
    touch('Chrono Trigger (USA).zip');
    touch('Chrono Trigger (USA)/Chrono Trigger (USA).sfc');
    final lib = await scan(_snes);
    expect(titles(lib), ['Chrono Trigger (USA)']);
    expect(files(lib, 'Chrono Trigger (USA)'), [abs('Chrono Trigger (USA).zip'), abs('Chrono Trigger (USA)/Chrono Trigger (USA).sfc')]);
  });

  test('an entry with any file a catalog game has is that game', () async {
    touch('Game (USA).cue', 'FILE "Game (USA) (Track 2).bin" BINARY\n');
    touch('Game (USA) (Track 2).bin');
    touch('Game (USA).bin');
    final lib = await scan(_psx, catalog: [_catalog('Game (USA).zip')]);
    expect(lib.games, isEmpty, reason: 'the zip was extracted at the root: its cue and bin are related to it, and the track joins the cue');
  });

  test('a folder a catalog game was extracted to, its archive deleted, is that game', () async {
    touch('Vagrant Story (USA)/Vagrant Story (USA).cue');
    touch('Vagrant Story (USA)/Vagrant Story (USA).bin');
    touch('Spyro (USA)/Spyro (USA).cue');
    expect(titles(await scan(_psx, catalog: [_catalog('Vagrant Story (USA).zip')])), ['Spyro (USA)']);
  });

  test('a dir with only .chd files counts for a cue/bin console that converts to CHD', () async {
    touch('Crash (USA).chd');
    expect(titles(await scan(_psx)), ['Crash (USA)']);
  });

  test('a loose .zip in a zip console is a game', () async {
    touch('Chrono Trigger (USA).zip');
    expect(titles(await scan(_snes)), ['Chrono Trigger (USA)']);
  });

  test('in a shared dir, a file whose extension two of the consoles use is no one\'s', () async {
    touch('Crash (USA).chd');
    touch('Crash (USA).cue');
    touch('God of War (USA).iso');
    expect(titles(await scan(_psx, sharing: [_ps2])), ['Crash (USA)']);
    expect(files(await scan(_psx, sharing: [_ps2]), 'Crash (USA)'), [abs('Crash (USA).cue')]);
    expect(titles(await scan(_ps2, sharing: [_psx])), ['God of War (USA)']);
  });

  test('the gameId is the same on a second scan', () async {
    touch('Spyro (USA).chd');
    touch('Vagrant Story/Vagrant Story.cue');
    final first = await scan(_psx);
    File(abs('Other (USA).chd')).writeAsStringSync('x');
    final second = await scan(_psx);
    expect([for (final g in second.games) if (g.title != 'Other (USA)') g.gameId], [for (final g in first.games) g.gameId]);
  });

  test('a name sanitizeForFat changes keeps its real path in the side map', () async {
    touch('Metroid Prime 4: Beyond.chd');
    final lib = await scan(_psx);
    final game = lib.games.single;
    expect(game.filename, 'Metroid Prime 4 Beyond.chd');
    expect(lib.paths[game.gameId], [abs('Metroid Prime 4: Beyond.chd')]);
    expect(OwnedGame.fromLoose(game, tmp.path, lib.paths)?.paths, [abs('Metroid Prime 4: Beyond.chd')]);
  });

  test('a file whose real name sanitizeForFat turns into a catalog game\'s is that catalog game, launched from its real path', () async {
    touch('Metroid Prime 4: Beyond.chd');
    final metroid = _catalog('Metroid Prime 4 Beyond.chd');
    final snapshot = await LibrarySnapshotNotifier(tmp.path).current();
    final lib = await scan(_psx, catalog: [metroid]);
    expect(lib.games, isEmpty, reason: 'no second game of the same id');
    final presence = snapshot.statusFor(metroid.filename);
    expect(presence, LibraryPresence.file);
    expect(OwnedGame.fromPresence(metroid, tmp.path, presence, snapshot)?.paths, [abs('Metroid Prime 4: Beyond.chd')]);
    expect(await hasGamesOnDisk(tmp.path, ownFormats(_psx, [_psx])), isTrue, reason: 'the console list and the owned view agree');
  });

  test('a loose game whose id a catalog game the snapshot does not know yet has is listed, and launches from its real path', () async {
    touch('Metroid Prime 4: Beyond.chd');
    final metroid = _catalog('Metroid Prime 4 Beyond.chd');
    // A snapshot taken before the file came.
    final stale = LibrarySnapshot(libraryDir: tmp.path, exactFiles: const {}, baseNames: const {}, relatedFiles: const {}, timestamp: DateTime(2026));
    final lib = await OwnedLibrary.scan((consoleId: 'psx', dir: tmp.path, formats: ownFormats(_psx, [_psx]), snapshot: stale, catalog: [metroid], folders: true, skip: const {}));
    final game = lib.games.single;
    expect(game.gameId, metroid.gameId);
    expect(OwnedGame.fromLoose(game, tmp.path, lib.paths)?.paths, [abs('Metroid Prime 4: Beyond.chd')]);
  });

  test('with the catalog game\'s own file on disk too, that file is the game and the other name is no second one', () async {
    touch('Metroid Prime 4: Beyond.chd');
    touch('Metroid Prime 4 Beyond.chd');
    final metroid = _catalog('Metroid Prime 4 Beyond.chd');
    final snapshot = await LibrarySnapshotNotifier(tmp.path).current();
    expect((await scan(_psx, catalog: [metroid])).games, isEmpty);
    expect(OwnedGame.fromPresence(metroid, tmp.path, snapshot.statusFor(metroid.filename), snapshot)?.paths, [abs('Metroid Prime 4 Beyond.chd')]);
  });

  test('a dir that cannot be listed is unreadable; one that does not exist is empty', () async {
    final locked = Directory(abs('locked'))..createSync();
    Process.runSync('chmod', ['000', locked.path]);
    addTearDown(() => Process.runSync('chmod', ['755', locked.path]));
    expect((await scan(_psx, dir: locked.path)).unreadable, isTrue);
    final missing = await scan(_psx, dir: abs('missing'));
    expect(missing.unreadable, isFalse);
    expect(missing.games, isEmpty);
  });

  test('hasGamesOnDisk holds exactly when OwnedLibrary finds a game, on the same dirs', () async {
    final cases = <String, List<String>>{
      'empty': [],
      'root file': ['Crash (USA).chd'],
      'folder game': ['Vagrant Story/Vagrant Story.cue'],
      'other formats only': ['notes.txt', 'Docs/readme.txt'],
      'too deep': ['A/B/Game.chd'],
      'shared extension only': ['God of War (USA).iso'],
    };
    for (final c in cases.entries) {
      final dir = Directory(abs(c.key))..createSync();
      for (final f in c.value) {
        File(p.join(dir.path, f)).createSync(recursive: true);
      }
      final formats = ownFormats(_psx, [_psx, _ps2]);
      final owned = await scan(_psx, sharing: [_ps2], dir: dir.path);
      expect(owned.games.isNotEmpty, await hasGamesOnDisk(dir.path, formats), reason: c.key);
    }
  });
}
