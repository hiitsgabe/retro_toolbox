import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';

GenMeta g(String id, List<String> parents, Map<String, String> files, {int minute = 0}) => GenMeta(
      gen: id,
      parents: parents,
      recipe: 'r',
      unit: 'u',
      device: 'd-0000',
      deviceName: 'D',
      createdAt: DateTime.utc(2026, 1, 1, 0, minute),
      package: 'a.b',
      files: {for (final e in files.entries) e.key: GenFile(e.value, 1)},
      payloadSha256: 'f' * 64,
    );

UnitPlan plan({Map<String, String> local = const {}, bool busy = false, Base? base, List<GenMeta> gens = const []}) =>
    planUnit(unit: 'u', local: local, busy: busy, base: base, gens: gens);

void main() {
  final g1 = g('g1', [], {'f': 'h1'});
  final g2 = g('g2', ['g1'], {'f': 'h2'}, minute: 1);
  final g3 = g('g3', ['g1'], {'f': 'h3'}, minute: 2);

  test('busy wins', () => expect(plan(busy: true, local: {'f': 'x'}), isA<Busy>()));

  test('empty hub: push local, nothing when there is no local', () {
    expect((plan(local: {'f': 'h1'}) as PushPlan).parents, isEmpty);
    expect(plan(), isA<UpToDate>());
  });

  test('local equal to the head is up to date and adopts it when the base differs', () {
    final p = plan(local: {'f': 'h2'}, gens: [g1, g2]) as UpToDate;
    expect(p.adopt!.gen, 'g2');
    expect((plan(local: {'f': 'h2'}, base: const Base('g2', {'f': 'h2'}), gens: [g1, g2]) as UpToDate).adopt, isNull);
  });

  test('head is the base: unchanged is up to date, changed pushes on top', () {
    const base = Base('g2', {'f': 'h2'});
    expect(plan(local: {'f': 'h2'}, base: base, gens: [g1, g2]), isA<UpToDate>());
    expect((plan(local: {'f': 'new'}, base: base, gens: [g1, g2]) as PushPlan).parents, ['g2']);
  });

  test('hub moved on: unchanged pulls, changed diverges', () {
    const base = Base('g1', {'f': 'h1'});
    expect((plan(local: {'f': 'h1'}, base: base, gens: [g1, g2]) as PullPlan).gen.gen, 'g2');
    final d = plan(local: {'f': 'mine'}, base: base, gens: [g1, g2]) as Diverged;
    expect(d.heads.single.gen, 'g2');
    expect(d.localDiffers, isTrue);
  });

  test('base unknown to the hub pulls only when prune could have removed it', () {
    Base at(DateTime t) => Base(makeGenId(t, 'd-0000', 'e' * 64), const {'f': 'old'});
    final older = at(DateTime.utc(2025, 12, 31, 23, 59));
    // A chain of pruneKeep gens, newest c19 at 00:19; the keep-th newest is c0 at 00:00.
    final kept = [for (var i = 0; i < pruneKeep; i++) g('c$i', [if (i > 0) 'c${i - 1}'], {'f': 'c$i'}, minute: i)];

    // Fewer gens than prune keeps: the hub lost the base (a folder put back
    // from an older copy), so the older head must not replace the local save.
    for (final gens in [
      [g2],
      kept.skip(1).toList(),
    ]) {
      final d = plan(local: {'f': 'old'}, base: older, gens: gens) as Diverged;
      expect(d.heads.single.gen, gens.last.gen);
      expect(d.localDiffers, isTrue);
    }
    // Enough gens, but the base is newer than the keep-th newest.
    expect(plan(local: {'f': 'old'}, base: at(DateTime.utc(2026, 1, 1, 0, 0, 1)), gens: kept), isA<Diverged>());
    // An id with no time cannot show it was pruned.
    expect(plan(local: {'f': 'old'}, base: const Base('pruned', {'f': 'old'}), gens: kept), isA<Diverged>());

    // As old as the keep-th newest or older: pruned, so pull as before.
    expect((plan(local: {'f': 'old'}, base: older, gens: kept) as PullPlan).gen.gen, 'c19');
    expect((plan(local: {'f': 'old'}, base: at(DateTime.utc(2026, 1, 1)), gens: kept) as PullPlan).gen.gen, 'c19');
    expect(plan(local: {'f': 'edited'}, base: older, gens: kept), isA<Diverged>());

    // Local equal to the head is still adopted, lost base or not.
    expect((plan(local: {'f': 'h2'}, base: older, gens: [g2]) as UpToDate).adopt!.gen, 'g2');
  });

  test('no local files pulls the head, flagged as missing locally', () {
    final p = plan(gens: [g1, g2]) as PullPlan;
    expect(p.gen.gen, 'g2');
    expect(p.missingLocally, isTrue);
    expect((plan(base: const Base('g2', {'f': 'h2'}), gens: [g1, g2]) as PullPlan).missingLocally, isTrue);
  });

  test('a new device with different local files diverges', () {
    expect(plan(local: {'f': 'other'}, gens: [g1, g2]), isA<Diverged>());
  });

  test('two heads always diverge; localDiffers is false when local equals one', () {
    final d = plan(local: {'f': 'h1'}, base: const Base('g1', {'f': 'h1'}), gens: [g1, g2, g3]) as Diverged;
    expect(d.heads.map((x) => x.gen), ['g3', 'g2']);
    expect(d.localDiffers, isTrue);
    expect((plan(gens: [g1, g2, g3]) as Diverged).localDiffers, isFalse);
    expect((plan(local: {'f': 'h3'}, gens: [g1, g2, g3]) as Diverged).localDiffers, isFalse);
  });

  test('Base JSON round-trip', () {
    final b = Base.fromJson(const Base('g1', {'f': 'h1'}).toJson());
    expect(b.gen, 'g1');
    expect(b.files, {'f': 'h1'});
  });
}
