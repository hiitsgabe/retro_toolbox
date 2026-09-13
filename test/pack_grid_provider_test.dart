import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';

const _target = PackTarget('snes', 'Super Nintendo');

PackGame _pg(String id, String dumpName) =>
    PackGame(id: id, title: dumpName, dumps: [PackDump(name: dumpName)]);

MetadataPack _pack() => MetadataPack(
      pack: 'snes',
      system: 'Super Nintendo',
      built: '2026-01-01',
      games: [
        _pg('snes/crystal-vanguard', 'Crystal Vanguard (USA)'),
        _pg('snes/super-vectron', 'Super Vectron (USA)'),
      ],
    );

Game _game(String filename, {String sourceId = kBuiltinAddonId}) => Game(
      title: filename,
      url: 'https://example.org/snes/$filename',
      size: 2048,
      consoleId: 'snes',
      sourceId: sourceId,
    );

ProviderContainer _container({
  PackTarget? target = _target,
  Future<MetadataPack?>? pack,
  List<Game> games = const [],
  String search = '',
}) {
  final container = ProviderContainer(overrides: [
    packTargetProvider.overrideWithValue(target),
    if (target != null)
      metadataPackProvider(target).overrideWith((ref) => pack ?? Future.value(_pack())),
    catalogGamesProvider.overrideWithValue(games),
    gridSearchQueryProvider.overrideWithValue(search),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Waits for the pack and matcher to resolve; without it the synchronous
/// providers still see `AsyncLoading`, a legitimate state tested separately.
Future<void> _ready(ProviderContainer container) async {
  await container.read(metadataPackProvider(_target).future);
  await container.read(packMatcherProvider(_target).future);
}

void main() {
  test('no selected console means source mode and an empty grid', () {
    final container = _container(target: null);

    expect(container.read(gridModeProvider), GridMode.source);
    expect(container.read(packGridEntriesProvider), isEmpty);
    expect(container.read(sourceIndexProvider), isNull);
  });

  test('while the pack loads the mode is source', () {
    // No await: this is the first-frame state of every session.
    final container = _container(pack: Future.delayed(const Duration(seconds: 1), _pack));

    expect(container.read(gridModeProvider), GridMode.source);
  });

  test('a console without a pack stays in source mode', () async {
    final container = _container(pack: Future.value(null));
    await container.read(metadataPackProvider(_target).future);

    expect(container.read(gridModeProvider), GridMode.source);
    expect(container.read(packGridEntriesProvider), isEmpty);
  });

  test('a pack fetch error falls to source mode, not an error screen', () async {
    final container = _container(pack: Future.error(Exception('no network')));
    await expectLater(container.read(metadataPackProvider(_target).future), throwsException);

    expect(container.read(gridModeProvider), GridMode.source);
  });

  test('with a pack the mode is pack and the grid holds every pack game', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    expect(container.read(gridModeProvider), GridMode.pack);
    final entries = container.read(packGridEntriesProvider);
    expect(entries.map((e) => e.game.id), ['snes/crystal-vanguard', 'snes/super-vectron']);
    expect(entries.map((e) => e.hasSource), [true, false]);
  });

  test('the matched source carries the size and the built-in source id', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    final source = container.read(packGridEntriesProvider).first.sources.single;
    expect(source.filename, 'Crystal Vanguard (USA).zip');
    expect(source.size, 2048);
    expect(source.sourceId, kBuiltinAddonId);
    expect(source.url, 'https://example.org/snes/Crystal Vanguard (USA).zip');
  });

  test('each source carries the addon id of the game that produced it', () async {
    final container = _container(games: [
      _game('Crystal Vanguard (USA).zip', sourceId: 'myrient'),
      _game('Super Vectron (USA).zip', sourceId: 'someones-archive'),
    ]);
    await _ready(container);

    // A map, not a list: what is asserted is that each source kept its own
    // game's id, independent of grid order.
    expect(
      {for (final e in container.read(packGridEntriesProvider)) e.game.id: e.sources.single.sourceId},
      {'snes/crystal-vanguard': 'myrient', 'snes/super-vectron': 'someones-archive'},
    );
  });

  test('the header search filters the pack grid', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')], search: 'vectron');
    await _ready(container);

    expect(container.read(packGridEntriesProvider).single.game.id, 'snes/super-vectron');
  });

  test('the resolver finds the catalog game by filename', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    final resolver = container.read(gameResolverProvider);
    final found = resolver(const MatchedSource(
      filename: 'Crystal Vanguard (USA).zip',
      sourceId: 'listing',
      confidence: MatchConfidence.likely,
      size: 2048,
    ));

    expect(found?.filename, 'Crystal Vanguard (USA).zip');
  });

  test('the resolver returns null for a source not in the catalog', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    final resolver = container.read(gameResolverProvider);
    final found = resolver(const MatchedSource(
      filename: 'A Game That Left The Listing.zip',
      sourceId: 'listing',
      confidence: MatchConfidence.likely,
      size: 10,
    ));

    expect(found, isNull);
  });

  test('the header search does not shrink the list the batch reads', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')], search: 'vectron');
    await _ready(container);

    expect(container.read(packGridEntriesProvider).map((e) => e.game.id), ['snes/super-vectron']);
    expect(
      container.read(allPackEntriesProvider).map((e) => e.game.id),
      ['snes/crystal-vanguard', 'snes/super-vectron'],
    );
  });

  test('the batch list is sorted by title, not by pack order', () async {
    final container = _container(
      pack: Future.value(MetadataPack(
        pack: 'snes',
        system: 'Super Nintendo',
        built: '2026-01-01',
        games: [
          _pg('snes/super-vectron', 'Super Vectron (USA)'),
          _pg('snes/crystal-vanguard', 'Crystal Vanguard (USA)'),
        ],
      )),
    );
    await _ready(container);

    expect(
      container.read(allPackEntriesProvider).map((e) => e.game.id),
      ['snes/crystal-vanguard', 'snes/super-vectron'],
    );
  });
}
