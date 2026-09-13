import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/providers/owned_games_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

import 'support/favorites_stub.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: [PackDump(name: '$title (USA)')]);

PackGridEntry _entry(String id, String title, {bool withSource = true}) => PackGridEntry(
      game: _pg(id, title),
      sources: withSource
          ? [MatchedSource(filename: '$title (USA).zip', sourceId: 'listing', confidence: MatchConfidence.likely, size: 1024)]
          : const [],
    );

/// A real index, because the empty-state banner reads `matchedGameCount` and a
/// fake index would prove nothing.
SourceIndex _index({required bool matchesSomething}) {
  final matcher = PackMatcher(MetadataPack(
    pack: 'snes',
    system: 'Super Nintendo',
    built: '2026-01-01',
    games: [_pg('snes/crystal-vanguard', 'Crystal Vanguard')],
  ));
  return SourceIndex.build(matcher, [
    if (matchesSomething)
      (filename: 'Crystal Vanguard (USA).zip', sourceId: 'listing', size: 1024, url: null),
  ]);
}

Widget _host(
  List<PackGridEntry> entries, {
  SourceIndex? index,
  void Function(PackGridEntry)? onOpenGame,
  Set<String>? downloaded,
  bool scanning = false,
}) {
  return ProviderScope(
    overrides: [
      // The catalogProvider here is the real one, and its constructor listens
      // to favoritesProvider, which hits disk; without the stub the long-press
      // case throws MissingPluginException after already passing.
      withoutFavoritesDisk,
      packGridEntriesProvider.overrideWithValue(entries),
      sourceIndexProvider.overrideWithValue(index ?? _index(matchesSomething: true)),
      ownedGameIdsProvider.overrideWith(
        // A Completer nobody completes stands in for a scan in progress; a
        // Future.delayed would leave a pending timer and fail the test at the end.
        (ref) => scanning ? Completer<Set<String>>().future : Future.value(downloaded ?? const <String>{}),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: PackGrid(onOpenGame: onOpenGame ?? (_) {})),
    ),
  );
}

void main() {
  testWidgets('draws one tile per entry', (tester) async {
    await tester.pumpWidget(_host([
      _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
      _entry('snes/super-vectron', 'Super Vectron'),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.text('Crystal Vanguard'), findsOneWidget);
  });

  testWidgets('a sourceless game stays in the grid, badged', (tester) async {
    await tester.pumpWidget(_host([
      _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
      _entry('snes/emberfall', 'Emberfall', withSource: false),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('an empty index shows the no-coverage banner', (tester) async {
    await tester.pumpWidget(_host(
      [_entry('snes/crystal-vanguard', 'Crystal Vanguard', withSource: false)],
      index: _index(matchesSomething: false),
    ));

    expect(find.text('No source covers this console'), findsOneWidget);
    // The banner is grid state, not tile state: the tiles are still there.
    expect(find.byType(PackGridItem), findsOneWidget);
  });

  testWidgets('an index covering something shows no banner', (tester) async {
    await tester.pumpWidget(_host([_entry('snes/crystal-vanguard', 'Crystal Vanguard')]));

    expect(find.text('No source covers this console'), findsNothing);
  });

  testWidgets('a search with no results shows the search empty, not the coverage one', (tester) async {
    await tester.pumpWidget(_host(const []));

    expect(find.text('No game with that name'), findsOneWidget);
    expect(find.text('No source covers this console'), findsNothing);
  });

  testWidgets('a short tap returns the tapped entry', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_host(
      [_entry('snes/crystal-vanguard', 'Crystal Vanguard'), _entry('snes/super-vectron', 'Super Vectron')],
      onOpenGame: (entry) => opened.add(entry.game.id),
    ));

    await tester.tap(find.text('Super Vectron'));
    await tester.pump();

    expect(opened, ['snes/super-vectron']);
  });

  testWidgets('a long press selects, and then the checkbox appears on every tile', (tester) async {
    await tester.pumpWidget(_host([
      _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
      _entry('snes/super-vectron', 'Super Vectron'),
    ]));

    expect(find.byType(Checkbox), findsNothing);

    await tester.longPress(find.text('Crystal Vanguard'));
    await tester.pump();

    // Two checkboxes, one checked: checkbox visibility is global, its value is
    // per tile.
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).where((c) => c.value == true).length,
      1,
    );
  });

  testWidgets('a game already on disk reaches the tile as owned', (tester) async {
    await tester.pumpWidget(_host(
      [
        _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
        _entry('snes/super-vectron', 'Super Vectron'),
      ],
      downloaded: {'snes/crystal-vanguard'},
    ));
    await tester.pump();

    final tiles = tester.widgetList<PackGridItem>(find.byType(PackGridItem)).toList();
    expect(tiles.firstWhere((t) => t.title == 'Crystal Vanguard').isOwned, isTrue);
    expect(tiles.firstWhere((t) => t.title == 'Super Vectron').isOwned, isFalse);
  });

  testWidgets('while the scan is unfinished nothing is marked owned', (tester) async {
    await tester.pumpWidget(_host(
      [_entry('snes/crystal-vanguard', 'Crystal Vanguard')],
      downloaded: {'snes/crystal-vanguard'},
      scanning: true,
    ));
    await tester.pump();

    // No border while the scan runs: a wrong border is worse than none, and the
    // answer does not exist yet.
    expect(tester.widget<PackGridItem>(find.byType(PackGridItem)).isOwned, isFalse);
  });
}
