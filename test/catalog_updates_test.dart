import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/storage_usage.dart';

Map<String, dynamic> _consoleJson(String id) {
  final list = jsonDecode(File('test/fixtures/updates/consoles.json').readAsStringSync()) as List;
  return Map<String, dynamic>.from(list.firstWhere((c) => c['id'] == id) as Map);
}

/// The fixture feed read the way the app reads a regex catalog: through the
/// console's own JSON (Console.toJson), as the isolate gets it.
List<Game> _parse(Map<String, dynamic> consoleJson, String feed) => [
      for (final e in parseRegexListing(
        File('test/fixtures/updates/$feed').readAsStringSync(),
        Console.fromJson(consoleJson).toJson(),
        'https://api.example.com/games/?limit=1000&offset=0',
      ))
        Game.fromJson(e),
    ];

Game _named(List<Game> games, String prefix) => games.singleWhere((g) => g.title.startsWith(prefix));

int _gb(double n) => (n * 1024 * 1024 * 1024).round();

/// One synthetic game `AAA` whose block holds the update entries in [feedTail].
List<GameAddon> _updatesOf(String feedTail, {String? updateDownloadUrl}) {
  final out = parseRegexListing(
    '<g id="AAA">G</g>$feedTail',
    Console.fromJson({
      'id': 'x',
      'name': 'X',
      'url': 'https://h.example.com/list/',
      'original_format': ['.nsz'],
      'ignore_extension_filtering': true,
      'regex': r'<g id="(?P<id>\w+)">(?P<text>[^<]+)</g>',
      'download_url': 'https://h.example.com/<id>/base',
      'update_regex': r'<u(?: id="(?P<id>\w+)")?(?: href="(?P<url>[^"]+)")? v="(?P<label>[^"]*)"/>',
      if (updateDownloadUrl != null) 'update_download_url': updateDownloadUrl,
    }).toJson(),
    'https://h.example.com/list/',
  );
  return Game.fromJson(out.single).updates;
}

void main() {
  test('a console keeps its update keys through JSON; without them it has no updates', () {
    final c = Console.fromJson({
      'id': 'x',
      'name': 'X',
      'url': 'https://h/',
      'update_regex': 'r',
      'update_download_url': 'https://h/<id>/update',
      'update_format': '.nsp',
    });
    final back = Console.fromJson(c.toJson());
    expect(back.updateRegex, 'r');
    expect(back.updateDownloadUrl, 'https://h/<id>/update');
    expect(back.updateFormat, '.nsp');
    expect(back.hasUpdates, isTrue);
    const plain = Console(id: 'y', name: 'Y', urls: []);
    expect(plain.hasUpdates, isFalse);
    expect(plain.toJson().containsKey('update_regex'), isFalse);
  });

  test('a game keeps its updates through JSON, and saves none when it has none', () {
    const update = GameAddon(label: 'v1', size: 5, url: 'https://h/1/update', fileName: 'G [v1].nsz');
    const game = Game(title: 'G.nsz', url: 'https://h/1/base', size: 1, consoleId: 'switch', updates: [update]);
    final back = Game.fromJson(jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>);
    expect([for (final u in back.updates) (u.label, u.size, u.url, u.fileName)], [('v1', 5, 'https://h/1/update', 'G [v1].nsz')]);
    expect(const Game(title: 'G.nsz', url: 'https://h/1/base', size: 1, consoleId: 'switch').toJson().containsKey('updates'), isFalse);
  });

  test('Switch 1: the update of each game that has one, linked by the game id', () {
    final games = _parse(_consoleJson('switch'), 'switch1_feed.json');
    expect(games, hasLength(3));
    final castlevania = _named(games, 'Castlevania');
    expect([for (final u in castlevania.updates) (u.label, u.size, u.url, u.fileName)], [
      ('v65536', 2722082635, 'https://api.example.com/games/download/0100BA4026E94000/update', "Castlevania: Belmont's Curse [v65536].nsz"),
    ]);
    expect([for (final u in _named(games, 'Disney').updates) u.label], ['v262144']);
    expect(_named(games, 'SpongeBob').updates, isEmpty); // has_update false
  });

  test('Switch 2: every entry of downloads.updates, none of base or dlc', () {
    final games = _parse(_consoleJson('switch2'), 'switch2_feed.json');
    expect(games, hasLength(3));
    final cyberpunk = _named(games, 'Cyberpunk');
    expect([for (final u in cyberpunk.updates) (u.label, u.size, u.url, u.fileName)], [
      ('2.2.1 [393216]', _gb(64.90), 'https://files.example.com/n02wk209icxk', 'Cyberpunk 2077: Ultimate Edition [2.2.1 [393216]].nup'),
    ]);
    expect([for (final u in _named(games, 'Donkey Kong').updates) (u.label, u.url)], [
      ('3.1.0 [458752]', 'https://files.example.com/p948laeaebm1'),
      ('3.2.0', 'https://files.example.com/6qzmhzje41l4'),
    ]);
    expect(_named(games, 'Civilization').updates, isEmpty);
  });

  test('a console without update_regex lists the same games with no updates', () {
    final json = _consoleJson('switch')..remove('update_regex');
    final games = _parse(json, 'switch1_feed.json');
    expect(games, hasLength(3));
    expect(games.every((g) => g.updates.isEmpty), isTrue);
  });

  test('the catalog cache is v4, so saved catalogs are read again with their DLC and mods', () {
    expect(const Console(id: 'switch', name: 'Nintendo Switch', urls: []).cacheFile, 'catalog_v4_switch.json');
  });

  test('an update with its own id fills update_download_url with it, not the game id', () {
    expect([for (final u in _updatesOf('<u id="BBB" v="v1"/>', updateDownloadUrl: 'https://h.example.com/<id>/update')) u.url],
        ['https://h.example.com/BBB/update']);
  });

  test('a match with a url ignores update_download_url', () {
    expect(
        [for (final u in _updatesOf('<u href="https://f.example.com/zz" v="v1"/>', updateDownloadUrl: 'https://h.example.com/<id>/update')) u.url],
        ['https://f.example.com/zz']);
  });

  test('a relative update url resolves against the listing url', () {
    expect([for (final u in _updatesOf('<u href="../u/zz" v="v1"/>')) u.url], ['https://h.example.com/u/zz']);
  });

  test('an update without a label is named [update]', () {
    expect([for (final u in _updatesOf('<u href="https://f.example.com/zz" v=""/>')) u.fileName], ['G [update].nsz']);
  });

  test('copyWith keeps the updates (the catalog adds details after parsing)', () {
    const u = GameAddon(label: 'v1', size: 5, url: 'https://h/1/update', fileName: 'G [v1].nsz');
    const g = Game(title: 'G.nsz', url: 'https://h/1/base', size: 1, consoleId: 'switch', updates: [u]);
    expect(g.copyWith(details: const GameDetails(popularity: 3)).updates, [u]);
  });

  test('Storage counts the v3 game lists', () {
    final tmp = Directory.systemTemp.createTempSync('rt_storage_v3');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, const Console(id: 'switch', name: 'S', urls: []).cacheFile)).writeAsBytesSync(List.filled(700, 1));
    expect(measureStorage(cacheDir: tmp.path, supportDir: tmp.path).catalog, 700);
  });
}
