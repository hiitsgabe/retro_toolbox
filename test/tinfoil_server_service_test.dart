import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';

Console makeConsole(String id, List<String>? formats) => Console(id: id, name: id, urls: const [], fileFormat: formats);

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
}
