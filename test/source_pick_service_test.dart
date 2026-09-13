import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';

Game _game(String filename, int size, {String sourceId = kBuiltinAddonId}) => Game(
      title: filename.replaceAll('.zip', ''),
      url: 'https://example.org/snes/$filename',
      size: size,
      consoleId: 'snes',
      sourceId: sourceId,
    );

MatchedSource _source(
  String filename, {
  MatchConfidence confidence = MatchConfidence.likely,
  String sourceId = 'listing',
  int size = 1000,
}) =>
    MatchedSource(filename: filename, sourceId: sourceId, confidence: confidence, size: size);

PackGridEntry _entry(String title, List<MatchedSource> sources) => PackGridEntry(
      game: PackGame(id: 'snes/${title.toLowerCase()}', title: title, dumps: [PackDump(name: title)]),
      sources: sources,
    );

/// The test resolver: every filename resolves, and the `Game` it returns is
/// recognizable by name.
Game? _resolve(MatchedSource source) => _game(source.filename, source.size);

BatchPlan _plan(
  List<PackGridEntry> entries, {
  Set<String> regions = const {'USA'},
  List<String> priority = const [],
  GameResolver? resolver,
}) =>
    planFromEntries(
      entries,
      preferredRegions: regions,
      resolveGame: resolver ?? _resolve,
      sourcePriority: priority,
    );

VerifiedSource _v(String filename, SourceVerification state) => (
      source: MatchedSource(
        filename: filename,
        sourceId: 'listing',
        confidence: MatchConfidence.likely,
        size: 100,
      ),
      state: state,
    );

void main() {
  test('each selected game becomes a pick, in the same order', () {
    final plan = planFromGames([
      _game('Crystal Vanguard (USA).zip', 4 * 1024 * 1024),
      _game('Super Vectron (USA).zip', 3 * 1024 * 1024),
    ]);

    expect(plan.picks.map((p) => p.filename),
        ['Crystal Vanguard (USA).zip', 'Super Vectron (USA).zip']);
    expect(plan.totalBytes, 7 * 1024 * 1024);
  });

  test('planFromGames carries each game addon id', () {
    final plan = planFromGames([
      _game('Crystal Vanguard (USA).zip', 4 * 1024 * 1024, sourceId: 'myrient'),
      _game('Super Vectron (USA).zip', 2 * 1024 * 1024, sourceId: 'someones-archive'),
    ]);

    expect(plan.picks.map((p) => p.sourceId), ['myrient', 'someones-archive']);
  });

  test('a cached game with no declared addon becomes the builtin', () {
    // Built by hand, without `_game`, so the case exercises `Game`'s default
    // rather than the helper's own default.
    final plan = planFromGames([
      Game(title: 'Crystal Vanguard (USA)', url: 'https://example.org/snes/Crystal Vanguard (USA).zip', size: 1024, consoleId: 'snes'),
    ]);

    expect(plan.picks.single.sourceId, kBuiltinAddonId);
  });

  test('the id and the whole Game travel together into the queue', () {
    final game = _game('Crystal Vanguard (USA).zip', 1024);
    final pick = planFromGames([game]).picks.single;

    expect(pick.gameId, game.gameId);
    expect(pick.game, same(game));
    expect(pick.size, 1024);
  });

  test('in source mode nothing is uncertain and nothing is left out', () {
    final plan = planFromGames([_game('a.zip', 1), _game('b.zip', 2)]);

    expect(plan.uncertainCount, 0);
    expect(plan.failures, isEmpty);
    expect(plan.picks.every((p) => p.reason.isNotEmpty), isTrue);
  });

  test('no games makes a truly empty plan', () {
    expect(planFromGames(const []).isEmpty, isTrue);
  });

  test('with a single source the reason says there was no choice', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [_source('Crystal Vanguard (Japan).zip')]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard (Japan).zip');
    expect(plan.picks.single.reason, 'the only source that has this game');
    expect(plan.failures, isEmpty);
  });

  test('the preferred region wins and the reason names it', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (Japan).zip'),
        _source('Crystal Vanguard (USA).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard (USA).zip');
    expect(plan.picks.single.reason, 'chosen by your preferred region (USA)');
  });

  test('with an empty region filter the axis is neutral and revision decides', () {
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [
          _source('Crystal Vanguard (USA).zip'),
          _source('Crystal Vanguard (Japan) (Rev A).zip'),
        ]),
      ],
      regions: const {},
    );

    expect(plan.picks.single.filename, 'Crystal Vanguard (Japan) (Rev A).zip');
    expect(plan.picks.single.reason, 'the newest revision (Rev A)');
  });

  test('a file with no region tag does not lose to the preferred one', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard.zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard.zip');
  });

  test('within the same region the higher revision wins', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (USA) (Rev A).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard (USA) (Rev A).zip');
    expect(plan.picks.single.reason, 'the newest revision (Rev A)');
  });

  test('region and revision tied, the higher confidence wins', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (USA).zip', confidence: MatchConfidence.guess),
        _source('Crystal Vanguard (USA).zip', confidence: MatchConfidence.confirmed),
      ]),
    ]);

    expect(plan.picks.single.reason, 'the most confident match among the 2 sources');
    expect(plan.picks.single.uncertain, isFalse);
  });

  test('everything else tied, addon priority decides', () {
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [
          _source('Crystal Vanguard (USA).zip', sourceId: 'slow'),
          _source('Crystal Vanguard (USA).zip', sourceId: 'fast'),
        ]),
      ],
      priority: const ['fast', 'slow'],
    );

    expect(plan.picks.single.reason, 'comes from the higher-priority addon');
  });

  test('addon priority picks the source, not only writes the reason', () {
    // The reason recomputes its own rank, so a mutant that neutralizes the addon
    // axis in `_compare` keeps the reason right while picking the wrong file;
    // `size` is not in `_compare`, so the sort winner stays observable.
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [
          _source('Crystal Vanguard (USA).zip', sourceId: 'slow', size: 10),
          _source('Crystal Vanguard (USA).zip', sourceId: 'fast', size: 20),
        ]),
      ],
      priority: const ['fast', 'slow'],
    );

    expect(plan.picks.single.size, 20);
  });

  test('all tied keeps the first, and the reason admits the tie', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (USA).zip', size: 10),
        _source('Crystal Vanguard (USA).zip', size: 20),
      ]),
    ]);

    expect(plan.picks.single.size, 10);
    expect(plan.picks.single.reason, 'tie among 2 sources, kept the first');
  });

  test('a guessed pick is marked uncertain', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [_source('Crystal Vanguard (USA).zip', confidence: MatchConfidence.guess)]),
    ]);

    expect(plan.picks.single.uncertain, isTrue);
  });

  test('a game with no source becomes a failure, not a pick', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [_source('Crystal Vanguard (USA).zip')]),
      _entry('Emberfall', const []),
    ]);

    expect(plan.picks.map((p) => p.title), ['Crystal Vanguard']);
    expect(plan.failures.single.title, 'Emberfall');
    expect(plan.failures.single.gameId, 'pack:snes/emberfall');
    expect(plan.failures.single.reason, 'no installed source has this game');
  });

  test('a game whose sources do not resolve fails with another reason', () {
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [_source('Crystal Vanguard (USA).zip')]),
      ],
      resolver: (_) => null,
    );

    expect(plan.picks, isEmpty);
    expect(plan.failures.single.reason, 'the source left the listing before the queue started');
  });

  test('no sources means nothing eligible and no uncertainty', () {
    final split = splitByVerification(const []);

    expect(split.eligible, isEmpty);
    expect(split.discarded, isEmpty);
    expect(split.confirmed, isFalse);
    expect(split.verifying, isFalse);
    expect(split.noCertainty, isFalse);
  });

  test('without verification all sources compete', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.notVerified),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.eligible.length, 2);
    expect(split.confirmed, isFalse);
    expect(split.noCertainty, isFalse);
  });

  test('one CRC-confirmed source removes the unconfirmed from the race', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.notVerified),
      _v('b.zip', SourceVerification.crcOk),
    ]);

    expect(split.eligible.map((v) => v.source.filename), ['b.zip']);
    expect(split.confirmed, isTrue);
  });

  test('a discarded source never competes and is counted apart', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.crcDiscarded),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.eligible.map((v) => v.source.filename), ['b.zip']);
    expect(split.discarded.map((v) => v.source.filename), ['a.zip']);
  });

  test('while one is verifying, none is excluded', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.verifying),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.verifying, isTrue);
    expect(split.eligible.length, 2);
    expect(split.noCertainty, isFalse);
  });

  test('all impossible becomes the not-sure-about-any state', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.impossible),
      _v('b.zip', SourceVerification.impossible),
    ]);

    expect(split.noCertainty, isTrue);
  });

  test('one impossible and one unverified is not total uncertainty', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.impossible),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    // The second was never asked, so it is still unknown.
    expect(split.noCertainty, isFalse);
    expect(split.eligible.length, 2);
  });

  test('all discarded leaves the race empty without becoming uncertainty', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.crcDiscarded),
      _v('b.zip', SourceVerification.crcDiscarded),
    ]);

    expect(split.eligible, isEmpty);
    expect(split.discarded.length, 2);
    // Not uncertainty: it is certainty that none fits.
    expect(split.noCertainty, isFalse);
  });
}
