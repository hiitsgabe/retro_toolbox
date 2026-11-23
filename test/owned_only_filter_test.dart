import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/game_details_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/filtering_service.dart';
import 'package:retro_toolbox/services/launcher/owned_library.dart';
import 'package:retro_toolbox/utils/title_metadata_parser.dart';

import 'game_groups_support.dart';

Game _local(String title, {GameDetails? details}) => Game(
      title: title,
      url: localGameUrl('psx', '$title.chd'),
      size: 1,
      consoleId: 'psx',
      metadata: TitleMetadataParser.parseRomTitle(title),
      details: details,
    );

/// The titles [games] lists under [filter], grouped by version as the
/// catalog does by default, with [owned] on disk.
List<String> _titles(List<Game> games, CatalogFilter filter, {Set<Game> owned = const {}, String text = '', Set<String>? favorites}) => [
      for (final g in FilteringService.filterAndPaginate(FilterInput(
        games: games,
        filterText: text,
        filter: filter,
        limit: 1000,
        favoriteGameIds: favorites,
        inLibraryStatus: {for (final g in games) g.gameId: owned.contains(g) ? GameStatus.downloaded : GameStatus.ready},
        groupVersions: true,
      )).games)
        g.title,
    ];

void main() {
  const owned = CatalogFilter(ownedOnly: true);

  test('the owned view keeps an owned EU file and an older revision the default filter and grouping hide', () {
    final usa = psxGame('Tekken 3 (USA) (Rev 1)'), old = psxGame('Tekken 3 (USA)'), eu = psxGame('Tekken 3 (Europe, Australia)');
    final games = [usa, old, eu];
    expect(_titles(games, const CatalogFilter(), owned: {old, eu}), ['Tekken 3 (USA) (Rev 1).zip'], reason: 'one entry per game without it');
    expect(_titles(games, owned, owned: {old, eu}), unorderedEquals(['Tekken 3 (Europe, Australia).zip', 'Tekken 3 (USA).zip']));
  });

  test('the owned view drops what is not on disk and keeps every loose game', () {
    final crash = psxGame('Crash Bandicoot (USA)'), spyro = psxGame('Spyro the Dragon (USA)');
    final loose = _local('Vagrant Story (Japan) (Beta)');
    expect(_titles([crash, spyro, loose], owned, owned: {spyro}), ['Spyro the Dragon (USA).zip', 'Vagrant Story (Japan) (Beta)']);
  });

  test('the owned view keeps the search, favourites, the LaunchBox filters and the sort', () {
    final a = psxGame('Ape Escape (Europe)', size: 5), b = psxGame('Bust A Groove (Europe)', size: 9);
    final rated = _local('Crash Team Racing (Europe)', details: const GameDetails(genres: ['Racing'], maxPlayers: 4, rating: 4.5, ratingCount: 10));
    final games = [a, b, rated];
    final mine = {a, b};
    expect(_titles(games, owned, owned: mine, text: 'groove'), ['Bust A Groove (Europe).zip']);
    expect(_titles(games, owned.copyWith(showFavoritesOnly: true), owned: mine, favorites: {a.gameId}), ['Ape Escape (Europe).zip']);
    expect(_titles(games, owned.copyWith(genres: {'Racing'}), owned: mine), ['Crash Team Racing (Europe)']);
    expect(_titles(games, owned.copyWith(players: {'2+'}), owned: mine), ['Crash Team Racing (Europe)']);
    expect(_titles(games, owned.copyWith(minRating: 4), owned: mine), ['Crash Team Racing (Europe)']);
    expect(_titles(games, owned.copyWith(sort: CatalogSort.sizeDesc), owned: mine), ['Bust A Groove (Europe).zip', 'Ape Escape (Europe).zip', 'Crash Team Racing (Europe)']);
  });

  test('the in-library filter counts a loose game as on disk too', () {
    final crash = psxGame('Crash Bandicoot (USA)');
    final loose = _local('Spyro the Dragon (USA)');
    expect(_titles([crash, loose], const CatalogFilter(showInLibraryOnly: true)), ['Spyro the Dragon (USA)']);
  });

  test('the owned view is not one of the filters the Filters badge counts', () {
    expect(owned.changesFromDefault, 0);
    expect(const CatalogFilter().copyWith(ownedOnly: true).ownedOnly, isTrue);
    expect(owned.copyWith(regions: {'Japan'}).ownedOnly, isTrue);
  });
}
