import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';

import 'support/favorites_stub.dart';

const _target = PackTarget('snes', 'Super Nintendo');

PackGame _pg() => const PackGame(
      id: 'snes/crystal-vanguard',
      title: 'Crystal Vanguard',
      dumps: [PackDump(name: 'Crystal Vanguard (USA)')],
      synopsis: 'A boy, a fair and a time machine.',
      genre: 'RPG',
      publisher: 'Square',
      year: 1995,
    );

// No `cover` on purpose in every test: with a URL, `CachedNetworkImage` would
// hit the network inside the test.
PackGridEntry _entry({List<MatchedSource> sources = const []}) =>
    PackGridEntry(game: _pg(), sources: sources);

MatchedSource _source(
  String filename, {
  int size = 4 * 1024 * 1024,
  MatchConfidence confidence = MatchConfidence.likely,
  String sourceId = 'listing',
}) =>
    MatchedSource(
      filename: filename,
      sourceId: sourceId,
      confidence: confidence,
      size: size,
    );

Game _game(String filename) => Game(
      title: filename,
      url: 'https://example.org/snes/$filename',
      size: 4 * 1024 * 1024,
      consoleId: 'snes',
    );

// A top-level function, not a lambda variable, to satisfy
// `prefer_function_declarations_over_variables`.
Game? _resolveDefault(MatchedSource source) => _game(source.filename);

Widget _host(
  PackGridEntry entry, {
  void Function(SourcePick)? onDownload,
  VoidCallback? onBatchDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verification,
  List<String> priority = const [],
  Map<String, String> names = const {},
}) {
  return ProviderScope(
    overrides: [
      withoutFavoritesDisk,
      packTargetProvider.overrideWithValue(_target),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue(resolver ?? _resolveDefault),
      // Required, not convenience: without it the real provider reads
      // `addonProvider`, which opens `AddonStore` via `path_provider` and throws
      // `MissingPluginException` in a widget test with no platform.
      sourcePriorityProvider.overrideWithValue(priority),
      addonNamesProvider.overrideWithValue(names),
      sourceVerificationProvider.overrideWith((ref, request) {
        final state = verification?.call(request.filename) ?? SourceVerification.notVerified;
        // `verifying` is not a value the provider returns; it is `AsyncLoading`.
        // A never-completing `Completer` holds the screen there without leaving
        // a pending timer at the end of the test.
        if (state == SourceVerification.verifying) {
          return Completer<SourceVerification>().future;
        }
        return state;
      }),
    ],
    child: MaterialApp(
      home: GameDetailScreen(
        entry: entry,
        onDownload: onDownload ?? (_) {},
        onBatchDownload: onBatchDownload ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('the hero shows the title, the publisher and one chip per fact', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    expect(find.text('Crystal Vanguard'), findsWidgets);
    // The publisher is the byline; system, year and genre are chips.
    expect(find.text('Square'), findsOneWidget);
    expect(find.text('Super Nintendo'), findsOneWidget);
    expect(find.text('1995'), findsOneWidget);
    expect(find.text('RPG'), findsOneWidget);
  });

  testWidgets('a comma-separated genre becomes one chip per genre', (tester) async {
    await tester.pumpWidget(_host(PackGridEntry(
      game: const PackGame(
        id: 'snes/crystal-vanguard',
        title: 'Crystal Vanguard',
        dumps: [PackDump(name: 'Crystal Vanguard (USA)')],
        genre: 'Action,Shooter,Third-Person',
      ),
      sources: [_source('Crystal Vanguard (USA).zip')],
    )));

    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Shooter'), findsOneWidget);
    expect(find.text('Third-Person'), findsOneWidget);
    expect(find.text('Action,Shooter,Third-Person'), findsNothing);
  });

  testWidgets('shows the synopsis', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    expect(find.text('A boy, a fair and a time machine.'), findsOneWidget);
    expect(find.text('Read more'), findsOneWidget);
  });

  testWidgets('Read more opens the synopsis and turns into Show less', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    await tester.tap(find.text('Read more'));
    await tester.pumpAndSettle();

    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Read more'), findsNothing);
  });

  testWidgets('with no synopsis there is nothing to expand', (tester) async {
    await tester.pumpWidget(_host(PackGridEntry(
      game: const PackGame(
        id: 'snes/crystal-vanguard',
        title: 'Crystal Vanguard',
        dumps: [PackDump(name: 'Crystal Vanguard (USA)')],
      ),
      sources: [_source('Crystal Vanguard (USA).zip')],
    )));

    expect(find.text('Read more'), findsNothing);
  });

  testWidgets('with screenshots, the strip draws one image per shot', (tester) async {
    await tester.pumpWidget(_host(PackGridEntry(
      game: const PackGame(
        id: 'snes/crystal-vanguard',
        title: 'Crystal Vanguard',
        dumps: [PackDump(name: 'Crystal Vanguard (USA)')],
        screenshot: 'https://example.org/shot.png',
        titleScreen: 'https://example.org/title.png',
      ),
      sources: [_source('Crystal Vanguard (USA).zip')],
    )));

    final urls = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .map((image) => image.imageUrl)
        .toList();

    // The screenshot appears twice: once in the strip and once behind the hero
    // blur, because the backdrop reuses the first shot rather than the cover,
    // which is already a wide image.
    expect(urls, ['https://example.org/shot.png', 'https://example.org/shot.png', 'https://example.org/title.png']);
  });

  testWidgets('with no screenshot there is no strip and no backdrop', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('the highlight card carries file, size and reason', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    expect(find.text('Crystal Vanguard (USA).zip'), findsOneWidget);
    expect(find.text('4.0 MB · listing'), findsOneWidget);
    // The reason is required, not decorative.
    expect(find.text('chosen by your preferred region (USA)'), findsOneWidget);
  });

  testWidgets('the Download button returns the whole pick', (tester) async {
    final downloaded = <String>[];
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip')]),
      onDownload: (pick) => downloaded.add(pick.game.filename),
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pump();

    // The `Game` from the callback is the one the queue understands, not a synthetic.
    expect(downloaded, ['Crystal Vanguard (USA).zip']);
  });

  testWidgets('with no source the screen still opens without a highlight card', (tester) async {
    await tester.pumpWidget(_host(_entry()));

    // The game still exists and is still favoritable.
    expect(find.text('A boy, a fair and a time machine.'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
  });

  testWidgets('the heart toggles the favorite', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('the checkbox toggles selection by pack key', (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        withoutFavoritesDisk,
        packTargetProvider.overrideWithValue(_target),
        preferredRegionsProvider.overrideWithValue(const {'USA'}),
        gameResolverProvider.overrideWithValue((source) => _game(source.filename)),
        sourceVerificationProvider.overrideWith((ref, request) => SourceVerification.notVerified),
        sourcePriorityProvider.overrideWithValue(const []),
        addonNamesProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return GameDetailScreen(
            entry: _entry(sources:[_source('Crystal Vanguard (USA).zip')]),
            onDownload: (_) {},
            onBatchDownload: () {},
          );
        }),
      ),
    ));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(
      captured.read(catalogProvider).selectedGames,
      contains('pack:snes/crystal-vanguard'),
    );
  });

  testWidgets('with no source, the band says why there is nothing to download', (tester) async {
    await tester.pumpWidget(_host(_entry()));

    // The same string the batch sheet shows for the same game: it comes from
    // `source_pick_service.dart`, do not write a new one here.
    expect(find.text('no installed source has this game'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
  });

  testWidgets('when the source does not resolve, the band uses the other reason', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip')]),
      resolver: (_) => null,
    ));

    expect(find.text('the source left the listing before the queue started'), findsOneWidget);
  });

  testWidgets('with no pick, the unresolved source still appears in the list', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip')]),
      resolver: (_) => null,
    ));

    // Nothing was picked, so no source is "the other", and the label drops the
    // word. The list still opens: hiding what exists would make the band look
    // like a lie.
    expect(find.text('source'), findsOneWidget);
  });

  testWidgets('with a single source there is no other-sources list', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    // A guard against the list showing up empty, not an implementation lock.
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('with three sources, the counter says 2 other sources', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
      _source('Crystal Vanguard (Europe).zip'),
    ])));

    expect(find.text('2 other sources'), findsOneWidget);
  });

  testWidgets('with two sources, the counter is singular', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    // Guards against a naive counter emitting "1 other sources".
    expect(find.text('other source'), findsOneWidget);
  });

  testWidgets('the list starts collapsed', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    expect(find.text('other source'), findsOneWidget);
    expect(find.text('Crystal Vanguard (Japan).zip'), findsNothing);
  });

  testWidgets('expanded, each row carries file, size and addon', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[
      _source('Crystal Vanguard (Japan).zip', size: 20),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    await tester.tap(find.text('other source'));
    await tester.pumpAndSettle();

    expect(find.text('Crystal Vanguard (Japan).zip'), findsOneWidget);
    expect(find.text('20.0 B · listing'), findsOneWidget);
  });

  testWidgets('a guess row reads no differently from a likely one', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[
      _source('Crystal Vanguard (USA).zip'),
      _source('Crystal Vanguard (Japan).zip', size: 20, confidence: MatchConfidence.guess),
    ])));

    await tester.tap(find.text('other source'));
    await tester.pumpAndSettle();

    // How the matcher found the file is matcher jargon, and nobody can act on
    // it. Size and source are what stays.
    expect(find.text('20.0 B · listing'), findsOneWidget);
    expect(find.textContaining('match'), findsNothing);
  });

  testWidgets('two identical sources: the pick leaves the list only once', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[
      _source('Crystal Vanguard (USA).zip', size: 10),
      _source('Crystal Vanguard (USA).zip', size: 20),
    ])));

    await tester.tap(find.text('other source'));
    await tester.pumpAndSettle();

    // The 10-byte one won on the order tiebreak. Removing every same-named
    // source would drop the 20-byte one too and hide a real source.
    expect(find.text('10.0 B · listing'), findsOneWidget);
    expect(find.text('20.0 B · listing'), findsOneWidget);
  });

  testWidgets('while verifying, the button says Download anyway', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip')]),
      verification: (_) => SourceVerification.verifying,
    ));

    expect(find.widgetWithText(FilledButton, 'Download anyway'), findsOneWidget);
    expect(find.text('4.0 MB · listing · verifying'), findsOneWidget);
  });

  testWidgets('CRC ok swaps the reason for the CRC reason', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip')]),
      verification: (_) => SourceVerification.crcOk,
    ));

    expect(find.text('confirmed by CRC, this is exactly the dump'), findsOneWidget);
    expect(find.text('4.0 MB · listing · CRC ok'), findsOneWidget);
    // With certainty given, the button does not hesitate.
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
  });

  testWidgets('the discarded source leaves the highlight and the other rises', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.crcDiscarded
          : SourceVerification.crcOk,
    ));

    // By name, USA would win on preferred region. CRC overruled it and the
    // highlight switched file.
    expect(find.text('Crystal Vanguard (Japan).zip'), findsOneWidget);
    expect(find.text('other source, 1 discarded'), findsOneWidget);
  });

  testWidgets('the discarded row shows up flagged', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.crcDiscarded
          : SourceVerification.crcOk,
    ));

    await tester.tap(find.text('other source, 1 discarded'));
    await tester.pumpAndSettle();

    // The one verdict that survives on a row, because it is the one a person
    // would want explained: this file is not the dump it claims to be.
    expect(find.text('4.0 MB · listing · discarded by CRC'), findsOneWidget);
  });

  testWidgets('with one confirmed, a still-verifying source does not make the button hesitate', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.verifying
          : SourceVerification.crcOk,
    ));

    // The still-running read is of a source that already lost, so it can no
    // longer change the highlight.
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
    expect(find.text('confirmed by CRC, this is exactly the dump'), findsOneWidget);
  });

  testWidgets('none verifiable: no alert, just the list', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (_) => SourceVerification.impossible,
    ));

    // No warning card. "We could not check any of these" is the normal case for
    // a pack with no CRC, and a banner on the normal case is noise.
    expect(find.textContaining('not sure'), findsNothing);
    // Nothing highlighted means no name-based pick reason.
    expect(find.text('chosen by your preferred region (USA)'), findsNothing);
    // What replaces it is the list, already open.
    expect(find.text('2 sources'), findsOneWidget);
  });

  testWidgets('in that state the list opens and each row has its own Download', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (_) => SourceVerification.impossible,
    ));

    // No tap: the list is born open.
    expect(find.text('Crystal Vanguard (USA).zip'), findsOneWidget);
    expect(find.text('Crystal Vanguard (Japan).zip'), findsOneWidget);
    // Two buttons, no third: there is no highlight card.
    expect(find.widgetWithText(FilledButton, 'Download'), findsNWidgets(2));
  });

  testWidgets('the row Download returns that source, flagged uncertain', (tester) async {
    final downloaded = <SourcePick>[];
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      onDownload: downloaded.add,
      verification: (_) => SourceVerification.impossible,
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Download').first);
    await tester.pump();

    expect(downloaded.single.filename, 'Crystal Vanguard (USA).zip');
    expect(downloaded.single.uncertain, isTrue);
  });

  testWidgets('all discarded: the band says none passed', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (_) => SourceVerification.crcDiscarded,
    ));

    expect(find.text('no source passed CRC verification'), findsOneWidget);
    expect(find.text('2 sources, 2 discarded'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
  });

  testWidgets('an unverifiable source reads as a plain row', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip', size: 20),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.crcOk
          : SourceVerification.impossible,
    ));

    await tester.tap(find.text('other source'));
    await tester.pumpAndSettle();

    // "Cannot verify" is the absence of an answer, not an answer, so it earns
    // no words.
    expect(find.text('20.0 B · listing'), findsOneWidget);
    expect(find.textContaining('cannot verify'), findsNothing);
  });

  testWidgets('the green check marks the CRC-confirmed row and no other', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip', size: 20),
        _source('Crystal Vanguard (Europe).zip', size: 30),
      ]),
      // USA wins on preferred region and takes the highlight, so the two rows
      // left are one confirmed and one discarded.
      verification: (filename) => filename.contains('Europe')
          ? SourceVerification.crcDiscarded
          : SourceVerification.crcOk,
    ));

    await tester.tap(find.text('2 other sources, 1 discarded'));
    await tester.pumpAndSettle();

    expect(find.text('20.0 B · listing'), findsOneWidget);
    expect(find.text('30.0 B · listing · discarded by CRC'), findsOneWidget);
    // The mark is on the confirmed row alone, not on the discarded one.
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
  });

  testWidgets('with no selection the detail screen shows no bar', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    // The `SelectionBar` is always mounted and shrinks to zero when the
    // selection is empty, so the test measures height instead of finding it.
    expect(tester.getSize(find.byType(SelectionBar)).height, 0);
  });

  testWidgets('checking the checkbox makes the bar appear with the count', (tester) async {
    await tester.pumpWidget(_host(_entry(sources:[_source('Crystal Vanguard (USA).zip')])));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.getSize(find.byType(SelectionBar)).height, greaterThan(0));
  });

  testWidgets('the bar Download is the batch one, not the highlight one', (tester) async {
    // Both buttons say "Download" and do different things: the card one queues
    // this game, the bar one opens the batch sheet. Swapping them is the bug
    // this test locks.
    final called = <String>[];
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip')]),
      onDownload: (_) => called.add('highlight'),
      onBatchDownload: () => called.add('batch'),
    ));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.tap(find.descendant(
      of: find.byType(SelectionBar),
      matching: find.text('Download'),
    ));
    await tester.pump();

    expect(called, ['batch']);
  });

  testWidgets('the user priority decides the highlight between tied sources', (tester) async {
    // Same filename on both, so region, revision and confidence tie and only
    // the addon axis remains. `size` differs as an observable of which one won.
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'slow'),
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'fast'),
      ]),
      priority: const ['fast', 'slow'],
    ));

    // By arrival order the 10-byte one would win. The 20-byte one won.
    expect(find.text('20.0 B · fast'), findsOneWidget);
  });

  testWidgets('reversing addon order swaps the highlight', (tester) async {
    // The pair of the case above, with arrival order reversed alongside
    // priority: together they separate "the screen passes the user's list" from
    // "the screen passes any list that happened to be right".
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'fast'),
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'slow'),
      ]),
      priority: const ['slow', 'fast'],
    ));

    expect(find.text('10.0 B · slow'), findsOneWidget);
  });

  testWidgets('with no addon in the list, the tiebreak falls back to arrival order', (tester) async {
    // A user who removed every addon and kept only the cache. An empty list
    // must not throw nor drop the highlight.
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'slow'),
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'fast'),
      ]),
      priority: const [],
    ));

    expect(find.text('10.0 B · slow'), findsOneWidget);
  });

  testWidgets('the highlight shows the addon name, not the id', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip', sourceId: 'myrient_org_files')]),
      names: const {'myrient_org_files': 'Myrient'},
    ));

    expect(find.text('4.0 MB · Myrient'), findsOneWidget);
  });

  testWidgets('the other-sources list also shows the name', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources:[
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'myrient_org_files'),
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'someones_archive'),
      ]),
      names: const {'myrient_org_files': 'Myrient', 'someones_archive': "Someone's Files"},
    ));

    await tester.tap(find.text('other source'));
    await tester.pumpAndSettle();

    expect(find.text("20.0 B · Someone's Files"), findsOneWidget);
  });

  testWidgets('an addon no longer in the list falls back to the id, not blank', (tester) async {
    // The user removed the addon and its game cache is still on disk. The info
    // goes stale and must still exist: "4.0 MB, " with a dangling comma is worse
    // than an ugly id.
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip', sourceId: 'addon_removed')]),
      names: const {},
    ));

    expect(find.text('4.0 MB · addon_removed'), findsOneWidget);
  });
}
