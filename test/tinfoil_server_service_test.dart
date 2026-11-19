import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';

Console makeConsole(String id, List<String>? formats) => Console(id: id, name: id, urls: const [], originalFormat: formats);

const _update = GameAddon(label: 'v262144', size: 20, url: 'https://h.example/download/0100F98025BC0000/update', fileName: 'Toy Story [v262144].nsz');
const _dlc = GameAddon(
  kind: AddonKind.dlc,
  label: 'Toy Story [DLC Pack: Extra] [0100F98025BC1001][v0]',
  size: 30,
  url: 'https://h.example/download/0100F98025BC0000/dlc-1',
  fileName: 'Toy Story [DLC Pack: Extra] [0100F98025BC1001][v0].nsz',
);
const _toyStory =
    Game(title: 'Toy Story.nsz', url: 'https://h.example/download/0100F98025BC0000/base', size: 10, consoleId: 'x', updates: [_update], dlcs: [_dlc]);

void main() {
  test('isSwitchConsole matches nsp/nsz/xci formats only', () {
    expect(TinfoilServerService.isSwitchConsole(makeConsole('sw', ['.nsp', '.nsz'])), isTrue);
    expect(TinfoilServerService.isSwitchConsole(makeConsole('xci', ['.xci'])), isTrue);
    expect(TinfoilServerService.isSwitchConsole(makeConsole('n64', ['.z64'])), isFalse);
    expect(TinfoilServerService.isSwitchConsole(makeConsole('none', null)), isFalse);
  });

  test('buildIndex produces tinfoil file list and route map', () {
    final sw = makeConsole('switch', ['.nsz']);
    final games = [
      const Game(title: 'Alpha Title.nsz', url: 'https://host.example/a.nsz', size: 123, consoleId: 'switch'),
      const Game(title: 'Beta: Title.nsz', url: 'https://host.example/b.nsz', size: 456, consoleId: 'switch'),
    ];
    final (index, routes) = TinfoilServerService.buildIndex({sw: games}, '192.168.1.5:8000');

    final files = index['files'] as List;
    expect(files.length, 2);
    expect(files[0]['url'], 'http://192.168.1.5:8000/dl/switch/0/Alpha%20Title.nsz');
    expect(files[0]['size'], 123);
    expect(index['success'], contains('2'));

    expect(routes['switch/0']!.game.title, 'Alpha Title.nsz');
    // Filename is sanitized for the URL path but keeps a readable title.
    expect(routes['switch/1']!.fileName, 'Beta_ Title.nsz');
  });

  test('filename embeds the title ID from the URL for Tinfoil metadata', () {
    final sw = makeConsole('switch', ['.nsz']);
    final games = [
      const Game(title: 'Sample Game.nsz', url: 'https://host.example/download/0100000000ABC000/base', size: 1, consoleId: 'switch'),
    ];
    final (_, routes) = TinfoilServerService.buildIndex({sw: games}, 'h:8000');
    expect(routes['switch/0']!.fileName, 'Sample Game [0100000000ABC000].nsz');
  });

  test('each update and DLC follows its game, named so Tinfoil reads its title id', () {
    final (index, routes) = TinfoilServerService.buildIndex({makeConsole('x', ['.nsz']): [_toyStory]}, 'h:8000');
    expect(routes.keys, ['x/0', 'x/0u0', 'x/0d0']);
    expect([for (final e in routes.values) e.fileName], [
      'Toy Story [0100F98025BC0000].nsz',
      // The update id is the base id ending in 800.
      'Toy Story [0100F98025BC0800][v262144].nsz',
      'Toy Story [DLC Pack_ Extra] [0100F98025BC1001][v0].nsz',
    ]);
    expect([for (final e in routes.values) e.game.url], [_toyStory.url, _update.url, _dlc.url]);
    expect([for (final f in index['files'] as List) (f['url'], f['size'])], [
      ('http://h:8000/dl/x/0/Toy%20Story%20%5B0100F98025BC0000%5D.nsz', 10),
      ('http://h:8000/dl/x/0u0/Toy%20Story%20%5B0100F98025BC0800%5D%5Bv262144%5D.nsz', 20),
      ('http://h:8000/dl/x/0d0/Toy%20Story%20%5BDLC%20Pack_%20Extra%5D%20%5B0100F98025BC1001%5D%5Bv0%5D.nsz', 30),
    ]);
    expect(index['success'], 'Retro Toolbox: 1 games, 1 updates, 1 DLC, 0 ready for fast install');
  });

  test("an update's extension is its own, not the game's", () {
    final game = _toyStory.copyWith(updates: [const GameAddon(label: 'v1', size: 1, url: 'https://h.example/u', fileName: 'Toy Story [v1].nsp')], dlcs: []);
    final (_, routes) = TinfoilServerService.buildIndex({makeConsole('x', ['.nsz']): [game]}, 'h:8000');
    expect(routes['x/0u0']!.fileName, 'Toy Story [0100F98025BC0800][v1].nsp');
  });

  test('a game without a title id lists its DLC but not its update', () {
    const game = Game(title: 'No Id.nsz', url: 'https://h.example/f/No%20Id.nsz', size: 10, consoleId: 'x', updates: [_update], dlcs: [_dlc]);
    final (index, routes) = TinfoilServerService.buildIndex({makeConsole('x', ['.nsz']): [game]}, 'h:8000');
    expect(routes.keys, ['x/0', 'x/0d0']);
    expect(index['success'], 'Retro Toolbox: 1 games, 0 updates, 1 DLC, 0 ready for fast install');
  });

  test('an update and a DLC in the updates folder are served from disk and listed under Fast install', () {
    final dir = Directory.systemTemp.createTempSync('tinfoil_addons');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Downloaded under its Game.filename, then decompressed to .nsp.
    final local = File('${dir.path}/Toy Story [v262144].nsp')..writeAsBytesSync(List.filled(7, 1));
    // The DLC is saved under its Game.filename too, which drops the colon.
    final localDlc = File('${dir.path}/Toy Story [DLC Pack Extra] [0100F98025BC1001][v0].nsz')..writeAsBytesSync([1, 2]);
    final console = makeConsole('x', ['.nsz']);
    Map<String, String> addonFiles(Console c) => TinfoilServerService.localSwitchFiles(dir.path);

    final (index, routes) = TinfoilServerService.buildIndex({console: [_toyStory]}, 'h:8000', addonFiles: addonFiles);
    final update = routes['x/0u0']!;
    expect(update.localPath, local.path);
    expect(update.fileName, 'Toy Story [0100F98025BC0800][v262144].nsp');
    expect(routes['x/0d0']!.localPath, localDlc.path);
    expect(routes['x/0']!.localPath, isNull);
    expect([for (final f in index['files'] as List) f['size']], [10, 7, 2]);
    expect(index['success'], 'Retro Toolbox: 1 games, 1 updates, 1 DLC, 2 ready for fast install');

    final (fast, _) = TinfoilServerService.buildIndex({console: [_toyStory]}, 'h:8000', addonFiles: addonFiles, folder: TinfoilServerService.fastInstallFolder);
    expect([for (final f in fast['files'] as List) (f['url'], f['size'])], [
      ('http://h:8000/dl/x/0u0/Toy%20Story%20%5B0100F98025BC0800%5D%5Bv262144%5D.nsp', 7),
      ('http://h:8000/dl/x/0d0/Toy%20Story%20%5BDLC%20Pack_%20Extra%5D%20%5B0100F98025BC1001%5D%5Bv0%5D.nsz', 2),
    ]);
    expect(fast['success'], 'Retro Toolbox: 2 ready for fast install');
  });
}
