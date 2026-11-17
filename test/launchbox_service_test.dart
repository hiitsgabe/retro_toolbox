import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_matcher.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_models.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_service.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_store.dart';

const snes = 'Super Nintendo Entertainment System';

const lbGames = [
  LaunchboxGame(
    id: 1,
    name: 'Super Metroid',
    alternateNames: ['Metroid 3'],
    releaseDate: 19940319,
    overview: 'Samus returns.',
    maxPlayers: 1,
    rating: 4.5,
    ratingCount: 80,
    genres: ['Action', 'Platform'],
    images: [LaunchboxImage(LaunchboxImageType.boxFront, 'metroid-a.jpg', 'North America')],
  ),
  LaunchboxGame(id: 2, name: 'Pilotwings', releaseDate: 19910821, maxPlayers: 2, cooperative: true, rating: 3.25, ratingCount: 12, genres: ['Flight Simulator']),
  LaunchboxGame(id: 3, name: 'Unrated Thing', rating: 0, ratingCount: 0),
  LaunchboxGame(id: 4, name: 'Twin Name', ratingCount: 2),
  LaunchboxGame(id: 5, name: 'Twin Name', ratingCount: 9),
];

Game game(String file, {GameDetails? details}) =>
    Game(title: file, url: 'https://host.example/snes/${Uri.encodeComponent(file)}', size: 1, consoleId: 'snes-usa', details: details);

void main() {
  late Directory tmp;
  late LaunchboxStore store;
  late int matcherCalls;
  late LaunchboxService service;
  const console = Console(id: 'snes-usa', name: 'SNES', urls: [], platform: 'snes');

  Future<List<int?>> countingMatcher(List<String> titles, List<LaunchboxGame> games) {
    matcherCalls++;
    return matchLaunchboxIds(titles, games);
  }

  Future<void> writeManifest(String? etag, {DateTime? importedAt}) =>
      store.writeManifest(LaunchboxManifest(etag: etag, importedAt: importedAt ?? DateTime.utc(2026, 11, 16), platforms: {snes}));

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lb_service_');
    store = LaunchboxStore(Directory('${tmp.path}/launchbox'));
    matcherCalls = 0;
    service = LaunchboxService(supportDir: () async => tmp, matcher: countingMatcher);
    await store.writePlatform(snes, lbGames);
    await writeManifest('"etag-1"');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('the store lives under <support>/launchbox', () async {
    expect((await service.store()).root.path, '${tmp.path}/launchbox');
    expect((await service.manifest())?.etag, '"etag-1"');
  });

  test('enrich fills the LaunchBox fields and keeps a known release date', () async {
    final games = [
      game('Super Metroid (Japan, USA) (En,Ja).sfc', details: const GameDetails(boxart: 'https://art/metroid.png')),
      game('Pilotwings (USA).zip', details: const GameDetails(releaseDate: 19901221)),
      game('Unrated Thing (USA).zip'),
      game('Nothing Like It (USA).zip'),
    ];
    final out = await service.enrich(console, games);

    final metroid = out[0].details!;
    expect(
      (metroid.launchboxId, metroid.launchboxPlatform, metroid.rating, metroid.ratingCount, metroid.maxPlayers, metroid.cooperative),
      (1, snes, 4.5, 80, 1, false),
    );
    expect(metroid.genres, ['Action', 'Platform']);
    expect(metroid.releaseDate, 19940319);
    expect(metroid.boxart, 'https://art/metroid.png');

    final pilotwings = out[1].details!;
    expect((pilotwings.launchboxId, pilotwings.rating, pilotwings.ratingCount, pilotwings.maxPlayers, pilotwings.cooperative), (2, 3.25, 12, 2, true));
    expect(pilotwings.genres, ['Flight Simulator']);
    expect(pilotwings.releaseDate, 19901221);

    final unrated = out[2].details!;
    expect((unrated.launchboxId, unrated.rating, unrated.ratingCount), (3, null, null));

    expect(out[3], same(games[3]));
  });

  test('a console whose platform was not imported, or that has none, is left untouched', () async {
    final games = [game('Super Metroid (USA).sfc')];
    const n64 = Console(id: 'n64', name: 'N64', urls: [], platform: 'n64');
    const unknown = Console(id: 'odd', name: 'Odd Box', urls: [], platform: 'zz-none');
    expect(await service.enrich(n64, games), same(games));
    expect(await service.enrich(unknown, games), same(games));

    // A file the manifest does not list is a leftover of an older import.
    await store.writePlatform('Nintendo 64', [const LaunchboxGame(id: 1, name: 'Super Metroid')]);
    expect(await service.enrich(n64, games), same(games));
    expect(matcherCalls, 0);
  });

  test('matches are cached per console and reused until the import changes', () async {
    final games = [game('Super Metroid (USA).sfc'), game('Pilotwings (USA).zip')];
    await service.enrich(console, games);
    expect(matcherCalls, 1);

    final cache = File('${tmp.path}/launchbox/match_snes_usa.json');
    expect(jsonDecode(cache.readAsStringSync()), {
      'version': '"etag-1"',
      'platform': snes,
      'ids': {'Super Metroid (USA).sfc': 1, 'Pilotwings (USA).zip': 2},
    });

    // A fresh service has no memory of the first run: the file alone answers.
    final again = LaunchboxService(supportDir: () async => tmp, matcher: countingMatcher);
    final out = await again.enrich(console, games.reversed.toList());
    expect(matcherCalls, 1);
    expect([for (final g in out) g.details?.launchboxId], [2, 1]);

    await again.enrich(console, [...games, game('Unrated Thing (USA).zip')]);
    expect(matcherCalls, 2, reason: 'a title the cache lacks matches everything again');

    await writeManifest('"etag-2"');
    await again.enrich(console, games);
    expect(matcherCalls, 3, reason: 'a new import matches again');
    expect(jsonDecode(cache.readAsStringSync())['version'], '"etag-2"');
  });

  test('without an ETag the import date tells imports apart', () async {
    final games = [game('Super Metroid (USA).sfc')];
    await writeManifest(null, importedAt: DateTime.utc(2026, 11, 16));
    await service.enrich(console, games);
    await service.enrich(console, games);
    expect(matcherCalls, 1);

    await writeManifest(null, importedAt: DateTime.utc(2026, 11, 17));
    await service.enrich(console, games);
    expect(matcherCalls, 2, reason: 'a re-import without an ETag matches again');
  });

  test('the default matcher, in its isolate, sees alternate names and votes', () async {
    final games = [game('Super Metroid (USA).sfc'), game('Metroid 3 (Japan).sfc'), game('Twin Name (USA).zip'), game('Pilotwings (USA).zip')];
    final out = await LaunchboxService(supportDir: () async => tmp).enrich(console, games);
    expect([for (final g in out) g.details?.launchboxId], [1, 1, 5, 2]);
  });

  test('a corrupt platform file leaves the games unchanged', () async {
    await store.platformFile(snes).writeAsBytes(utf8.encode('not gzip at all'));
    final games = [game('Super Metroid (USA).sfc')];
    expect(await service.enrich(console, games), same(games));
  });

  test('lookup returns the full record, null for an unknown id', () async {
    final metroid = (await service.lookup(snes, 1))!;
    expect(metroid.overview, 'Samus returns.');
    expect([for (final i in metroid.images) (i.type, i.url, i.region)], [
      (LaunchboxImageType.boxFront, 'https://images.launchbox-app.com/metroid-a.jpg', 'North America'),
    ]);
    expect(await service.lookup(snes, 999), isNull);
    expect(await service.lookup('Nintendo 64', 1), isNull);
  });

  test('a platform that was not on disk is read again on the next call', () async {
    expect(await service.lookup('Sega Genesis', 1), isNull);
    await store.writePlatform('Sega Genesis', [const LaunchboxGame(id: 1, name: 'Sonic the Hedgehog')]);
    expect((await service.lookup('Sega Genesis', 1))?.name, 'Sonic the Hedgehog');
  });

  test('invalidate drops the platform held in memory', () async {
    expect((await service.lookup(snes, 2))?.name, 'Pilotwings');
    await store.writePlatform(snes, [const LaunchboxGame(id: 2, name: 'Pilotwings Renamed')]);
    expect((await service.lookup(snes, 2))?.name, 'Pilotwings');
    service.invalidate();
    expect((await service.lookup(snes, 2))?.name, 'Pilotwings Renamed');
  });

  test('only the last two platforms stay in memory', () async {
    for (final p in ['Nintendo 64', 'Sega Genesis']) {
      await store.writePlatform(p, [LaunchboxGame(id: 1, name: p)]);
    }
    Future<String?> name(String p) async => (await service.lookup(p, 1))?.name;

    expect(await name(snes), 'Super Metroid');
    expect(await name('Nintendo 64'), 'Nintendo 64');
    await store.writePlatform(snes, [const LaunchboxGame(id: 1, name: 'Changed')]);
    expect(await name(snes), 'Super Metroid', reason: 'still one of the last two');

    // Genesis pushes out Nintendo 64, the oldest since snes was just used.
    await store.writePlatform('Nintendo 64', [const LaunchboxGame(id: 1, name: 'N64 Changed')]);
    expect(await name('Sega Genesis'), 'Sega Genesis');
    expect(await name(snes), 'Super Metroid');
    expect(await name('Nintendo 64'), 'N64 Changed');
  });

  group('GameDetails JSON', () {
    test('a round trip keeps every LaunchBox field', () {
      const d = GameDetails(
        boxart: 'https://art/a.png',
        releaseDate: 19940319,
        launchboxId: 7,
        launchboxPlatform: snes,
        rating: 4.25,
        ratingCount: 31,
        genres: ['Action', 'Platform'],
        maxPlayers: 2,
        cooperative: true,
      );
      final back = GameDetails.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(
        (back.boxart, back.releaseDate, back.launchboxId, back.launchboxPlatform, back.rating, back.ratingCount, back.maxPlayers, back.cooperative),
        ('https://art/a.png', 19940319, 7, snes, 4.25, 31, 2, true),
      );
      expect(back.genres, ['Action', 'Platform']);
    });

    test('unset fields stay out of the JSON and old JSON still parses', () {
      expect(const GameDetails(boxart: 'b').toJson(), {'boxart': 'b'});
      final old = GameDetails.fromJson({'boxart': 'b', 'releaseDate': 19990000});
      expect(
        (old.launchboxId, old.launchboxPlatform, old.rating, old.ratingCount, old.maxPlayers, old.cooperative),
        (null, null, null, null, null, null),
      );
      expect(old.genres, isEmpty);
    });

    test('a whole-number rating read back from JSON is still a double', () {
      expect(GameDetails.fromJson({'rating': 4}).rating, 4.0);
    });
  });
}
