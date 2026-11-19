import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_addon_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/catalog_service.dart';

// The Switch catalog keys: the resource_id prefix tells a DLC from a mod.
const dlcRegex = r'\{"name"\s*:\s*"(?P<name>(?:[^"\\]|\\.)+)"\s*,\s*"size"\s*:\s*(?P<size>\d+)\s*,\s*"resource_id"\s*:\s*"(?P<id>dlc-[^"]+)"';
const modRegex = r'\{"name"\s*:\s*"(?P<name>(?:[^"\\]|\\.)+)"\s*,\s*"size"\s*:\s*(?P<size>\d+)\s*,\s*"resource_id"\s*:\s*"(?P<id>mod-[^"]+)"';
const addonUrl = 'https://api.ultranx.ru/games/download/<game_id>/<id>';

const _listing = 'https://api.example.com/games/?limit=1000&offset=0';

Map<String, dynamic> _switchJson({bool addons = true}) {
  final list = jsonDecode(File('test/fixtures/updates/consoles.json').readAsStringSync()) as List;
  final json = Map<String, dynamic>.from(list.firstWhere((c) => c['id'] == 'switch') as Map);
  if (addons) {
    json.addAll({'dlc_regex': dlcRegex, 'dlc_download_url': addonUrl, 'mod_regex': modRegex, 'mod_download_url': addonUrl});
  }
  return json;
}

final _feed = File('test/fixtures/updates/switch1_addons_feed.json').readAsStringSync();

List<Map<String, dynamic>> _maps(Map<String, dynamic> consoleJson) => parseRegexListing(_feed, Console.fromJson(consoleJson).toJson(), _listing);

List<Game> _games() => [for (final e in _maps(_switchJson())) Game.fromJson(e)];

Game _byId(List<Game> games, String titleId) => games.singleWhere((g) => g.url.contains('/$titleId/'));

/// One synthetic game `AAA` whose block is [feedTail], read with [extra] keys.
Game _gameOf(String feedTail, Map<String, dynamic> extra) {
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
      ...extra,
    }).toJson(),
    'https://h.example.com/list/',
  );
  return Game.fromJson(out.single);
}

void main() {
  test('the fixture page lists 3 games, and the Castlevania DLC with its own name, size and link', () {
    final games = _games();
    expect(games, hasLength(3));
    final castlevania = _byId(games, '0100BA4026E94000');
    expect([for (final d in castlevania.dlcs) (d.kind, d.label, d.size, d.url, d.fileName)], [
      (
        AddonKind.dlc,
        'Castlevania Belmonts Curse [DLC Bonus Contents Pack] [0100BA4026E95001][v0]',
        20982,
        'https://api.ultranx.ru/games/download/0100BA4026E94000/dlc-2357857854:0b78eb3a65f7993781118682e1eaf95a213f0f85781a5117b6d15ba3b9fb0576',
        'Castlevania Belmonts Curse [DLC Bonus Contents Pack] [0100BA4026E95001][v0].nsz',
      ),
    ]);
    expect(castlevania.mods, isEmpty);
  });

  test('the Marsupilami mod keeps its feed name and links by the game id', () {
    final marsupilami = _byId(_games(), '01006AC025AAC000');
    expect([for (final m in marsupilami.mods) (m.kind, m.label, m.size, m.fileName)], [
      (AddonKind.mod, 'Rus Lang Mod (03.09.2026, by most2820)', 192113, 'Rus Lang Mod (03.09.2026, by most2820).msp'),
    ]);
    expect(marsupilami.mods.single.url, endsWith('/01006AC025AAC000/mod-2357857854:4ab4b2ba19f2b6ec4cd42ed5f023e2a5480bb990fae86abdfd7f3784edc78411'));
    expect(marsupilami.dlcs, isEmpty);
  });

  test('a game with only an update keeps it and has no DLC or mods', () {
    final disney = _byId(_games(), '0100F98025BC0000');
    expect(disney.dlcs, isEmpty);
    expect(disney.mods, isEmpty);
    expect([for (final u in disney.updates) (u.kind, u.label, u.size)], [(AddonKind.update, 'v262144', 394460793)]);
  });

  test('each addon lands only on the game whose block holds it', () {
    final games = _games();
    expect({
      for (final g in games) g.url.split('/')[5]: (g.dlcs.length, g.mods.length)
    }, {
      '0100F98025BC0000': (0, 0),
      '0100BA4026E94000': (1, 0),
      '01006AC025AAC000': (0, 1),
    });
  });

  test('<game_id> in update_download_url is the game id, <id> the update id', () {
    final g = _gameOf('<u id="BBB" v="v1"/>', {
      'update_regex': r'<u(?: id="(?P<id>\w+)")? v="(?P<label>[^"]*)"/>',
      'update_download_url': 'https://h.example.com/<game_id>/<id>',
    });
    expect([for (final u in g.updates) u.url], ['https://h.example.com/AAA/BBB']);

    // A game listed by href has no id to put there, so its addon has no link.
    final byHref = parseRegexListing(
      '<g href="/f/G.nsz">G</g><u id="BBB" v="v1"/>',
      Console.fromJson({
        'id': 'x',
        'name': 'X',
        'url': 'https://h.example.com/list/',
        'ignore_extension_filtering': true,
        'regex': r'<g href="(?P<href>[^"]+)">(?P<text>[^<]+)</g>',
        'update_regex': r'<u(?: id="(?P<id>\w+)")? v="(?P<label>[^"]*)"/>',
        'update_download_url': 'https://h.example.com/<game_id>/<id>',
      }).toJson(),
      'https://h.example.com/list/',
    );
    expect(byHref.single.containsKey('updates'), isFalse);
  });

  test('a name the file system cannot hold is made safe; JSON escapes are decoded first', () {
    final g = _gameOf(
      r'{"name":"A/B: C.nsz","size":1,"resource_id":"dlc-1"}'
      r'{"name":"Say \"Hi\" \u00e9.nsz","size":2,"resource_id":"dlc-2"}',
      {'dlc_regex': dlcRegex, 'dlc_download_url': addonUrl},
    );
    expect([for (final d in g.dlcs) (d.fileName, d.label, d.url)], [
      ('A_B_ C.nsz', 'A/B: C', 'https://api.ultranx.ru/games/download/AAA/dlc-1'),
      ('Say _Hi_ é.nsz', 'Say "Hi" é', 'https://api.ultranx.ru/games/download/AAA/dlc-2'),
    ]);
  });

  test('an addon without a name is called after the game and its label, or its kind', () {
    final g = _gameOf('<d id="1" l="Pack"/><d id="2" l=""/>', {
      'dlc_regex': r'<d id="(?P<id>\w+)" l="(?P<label>[^"]*)"/>',
      'dlc_download_url': 'https://h.example.com/<game_id>/<id>',
    });
    expect([for (final d in g.dlcs) (d.fileName, d.url)], [
      ('G [Pack].nsz', 'https://h.example.com/AAA/1'),
      ('G [dlc].nsz', 'https://h.example.com/AAA/2'),
    ]);
  });

  test('an addon keeps its kind through JSON; one saved without a kind is an update', () {
    for (final kind in AddonKind.values) {
      final a = GameAddon(kind: kind, label: 'L', size: 3, url: 'https://h/1/x', fileName: 'G [L].nsz');
      final back = GameAddon.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
      expect((back.kind, back.label, back.size, back.url, back.fileName), (kind, 'L', 3, 'https://h/1/x', 'G [L].nsz'));
    }
    expect(GameAddon.fromJson({'label': 'v1', 'size': 1, 'url': 'https://h/u', 'fileName': 'G [v1].nsz'}).kind, AddonKind.update);
  });

  test('a game keeps its DLC and mods through JSON and copyWith; toGame marks the kind', () {
    const dlc = GameAddon(kind: AddonKind.dlc, label: 'D', size: 1, url: 'https://h/1/d', fileName: 'D.nsz');
    const mod = GameAddon(kind: AddonKind.mod, label: 'M', size: 2, url: 'https://h/1/m', fileName: 'M.msp');
    const game = Game(title: 'G.nsz', url: 'https://h/1/base', size: 1, consoleId: 'switch', dlcs: [dlc], mods: [mod]);
    final back = Game.fromJson(jsonDecode(jsonEncode(game.toJson())) as Map<String, dynamic>);
    expect([for (final a in [...back.dlcs, ...back.mods]) (a.kind, a.fileName)], [
      (AddonKind.dlc, 'D.nsz'),
      (AddonKind.mod, 'M.msp')
    ]);
    final copy = game.copyWith(size: 9);
    expect(copy.dlcs, [dlc]);
    expect(copy.mods, [mod]);
    final plain = const Game(title: 'G.nsz', url: 'https://h/1/base', size: 1, consoleId: 'switch').toJson();
    expect((plain.containsKey('dlcs'), plain.containsKey('mods'), plain.containsKey('addonKind')), (false, false, false));

    expect(game.addonKind, isNull);
    expect(game.isUpdate, isFalse);
    for (final kind in AddonKind.values) {
      final asGame = GameAddon(kind: kind, label: 'L', size: 1, url: 'https://h/1/x', fileName: 'X.nsz').toGame(game);
      final restored = Game.fromJson(jsonDecode(jsonEncode(asGame.toJson())) as Map<String, dynamic>);
      expect((asGame.addonKind, asGame.isUpdate, restored.addonKind, asGame.copyWith(size: 2).addonKind), (kind, kind == AddonKind.update, kind, kind));
    }
  });

  test('a console keeps the DLC and mod keys through JSON, and writes none it lacks', () {
    final back = Console.fromJson(Console.fromJson(_switchJson()).toJson());
    expect((back.dlcRegex, back.dlcDownloadUrl, back.modRegex, back.modDownloadUrl), (dlcRegex, addonUrl, modRegex, addonUrl));
    final plain = Console.fromJson(_switchJson(addons: false)).toJson();
    expect(plain.keys.where((k) => k.startsWith('dlc_') || k.startsWith('mod_')), isEmpty);
  });

  test('a console without the DLC and mod keys parses exactly as before', () {
    final before = _maps(_switchJson(addons: false));
    expect(before.where((m) => m.containsKey('dlcs') || m.containsKey('mods')), isEmpty);
    final withAddons = [
      for (final m in _maps(_switchJson()))
        Map<String, dynamic>.from(m)
          ..remove('dlcs')
          ..remove('mods')
    ];
    expect(jsonEncode(withAddons), jsonEncode(before));
  });
}
