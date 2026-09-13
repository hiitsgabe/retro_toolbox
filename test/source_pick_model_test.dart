import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';

Game _game(String name, int size) => Game(
      title: name,
      url: 'https://example/$name',
      size: size,
      consoleId: 'snes',
    );

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listing',
      reason: 'chosen by your preferred region',
      uncertain: uncertain,
      game: _game(name, size),
    );

void main() {
  test('totalBytes sums the size of every pick', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 1000), _pick('b.zip', 2400)]);

    expect(plan.totalBytes, 3400);
  });

  test('totalBytes is zero for a plan with no pick', () {
    const plan = BatchPlan();

    expect(plan.totalBytes, 0);
    expect(plan.isEmpty, isTrue);
  });

  test('uncertainCount counts only picks marked uncertain', () {
    final plan = BatchPlan(picks: [
      _pick('a.zip', 10),
      _pick('b.zip', 10, uncertain: true),
      _pick('c.zip', 10, uncertain: true),
    ]);

    expect(plan.uncertainCount, 2);
  });

  test('withoutPick removes one pick and keeps the failures', () {
    final plan = BatchPlan(
      picks: [_pick('a.zip', 10), _pick('b.zip', 20)],
      failures: const [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    );

    final smaller = plan.withoutPick('snes/a.zip');

    expect(smaller.picks.map((p) => p.gameId), ['snes/b.zip']);
    expect(smaller.failures.single.title, 'C');
    // The original plan is unchanged: the sheet keeps it for undo.
    expect(plan.picks.length, 2);
  });

  test('withoutPick of an id not in the plan returns the same content', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 10)]);

    expect(plan.withoutPick('snes/does-not-exist').picks.length, 1);
  });

  test('a plan of failures only is not empty', () {
    const plan = BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    );

    expect(plan.isEmpty, isFalse);
    expect(plan.picks, isEmpty);
  });
}
