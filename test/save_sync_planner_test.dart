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

  test('base unknown to the hub behaves the same', () {
    const base = Base('pruned', {'f': 'old'});
    expect(plan(local: {'f': 'old'}, base: base, gens: [g2]), isA<PullPlan>());
    expect(plan(local: {'f': 'edited'}, base: base, gens: [g2]), isA<Diverged>());
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
