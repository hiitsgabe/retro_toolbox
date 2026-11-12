import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';

GenMeta g(String id, List<String> parents, {int minute = 0, DateTime? at, Map<String, String> files = const {'a': 'h1'}}) => GenMeta(
      gen: id,
      parents: parents,
      recipe: 'stardew-valley',
      unit: 'Farm_1',
      device: 'thor-7f3a',
      deviceName: 'AYN Thor',
      createdAt: at ?? DateTime.utc(2026, 11, 10, 22, minute),
      package: 'com.chucklefish.stardewvalley',
      files: {for (final e in files.entries) e.key: GenFile(e.value, 1)},
      payloadSha256: 'f' * 64,
    );

void main() {
  test('makeGenId and genTime round-trip', () {
    final id = makeGenId(DateTime.utc(2026, 11, 10, 22, 41, 7), 'thor-7f3a', '9f2c01e1abcdef');
    expect(id, '20261110T224107Z-thor-7f3a-9f2c01e1');
    expect(genIdRe.hasMatch(id), isTrue);
    expect(genTime(id), DateTime.utc(2026, 11, 10, 22, 41, 7));
    expect(genTime('nope'), isNull);
  });

  test('makeDeviceId slugs the model and adds 4 hex digits', () {
    final id = makeDeviceId('AYN Thor', Random(1));
    expect(id, matches(RegExp(r'^ayn-thor-[0-9a-f]{4}$')));
    expect(makeDeviceId('!!!', Random(1)), matches(RegExp(r'^device-[0-9a-f]{4}$')));
    expect(makeDeviceId('Anbernic RG Rotate Super Long Model Name', Random(1)).length, lessThanOrEqualTo(24));
  });

  test('GenMeta JSON round-trip', () {
    final a = g('20261110T224107Z-thor-7f3a-9f2c01e1', ['20261110T191004Z-odin-02c4-41aa0907']);
    final b = GenMeta.fromJson(a.toJson());
    expect(b.gen, a.gen);
    expect(b.parents, a.parents);
    expect(b.createdAt, a.createdAt);
    expect(b.hashes, {'a': 'h1'});
    expect(() => GenMeta.fromJson({...a.toJson(), 'format': 2}), throwsFormatException);
    expect(() => GenMeta.fromJson({...a.toJson(), 'files': 'x'}), throwsFormatException);
  });

  test('headsOf: gens nobody names as a parent', () {
    final gens = [g('a', []), g('b', ['a']), g('c', ['b']), g('d', ['b'])];
    expect(headsOf(gens).map((x) => x.gen), unorderedEquals(['c', 'd']));
    expect(headsOf([g('a', []), g('m', ['a', 'x'])]).map((x) => x.gen), ['m']);
  });

  test('pruneCandidates keeps heads and the newest N', () {
    final gens = [for (var i = 0; i < 6; i++) g('g$i', i == 0 ? [] : ['g${i - 1}'], minute: i)];
    expect(pruneCandidates(gens, keep: 3).map((x) => x.gen), unorderedEquals(['g0', 'g1', 'g2']));
    final branched = [...gens, g('side', ['g0'], minute: 0)];
    expect(pruneCandidates(branched, keep: 3).map((x) => x.gen), isNot(contains('side')));
  });

  test('pruneCandidates never deletes a child while its parent stays, even when the clocks disagree', () {
    final gens = [
      g('g1', [], at: DateTime.utc(2026, 11, 10, 10)),
      g('g2', ['g1'], at: DateTime.utc(2026, 11, 10, 9, 58)), // pushed from a device whose clock is slow
      for (var i = 3; i <= 21; i++) g('g$i', ['g${i - 1}'], at: DateTime.utc(2026, 11, 10, 10, i)),
    ];
    final gone = {for (final x in pruneCandidates(gens, keep: 20)) x.gen};
    final remaining = gens.where((x) => !gone.contains(x.gen)).toList();
    expect(headsOf(remaining).map((x) => x.gen), ['g21']);
  });

  test('pruneCandidates lists parents first, so every prefix is safe to delete', () {
    void expectSafePrefixes(List<GenMeta> gens, int keep, List<String> expected) {
      final out = pruneCandidates(gens, keep: keep);
      expect(out.map((x) => x.gen).toList(), expected);
      final heads = headsOf(gens).map((x) => x.gen).toSet();
      for (var n = 0; n <= out.length; n++) {
        final gone = {for (final x in out.take(n)) x.gen};
        final rest = gens.where((x) => !gone.contains(x.gen)).toList();
        expect(headsOf(rest).map((x) => x.gen).toSet(), heads, reason: 'after deleting $n');
      }
    }

    final chain = [for (var i = 1; i <= 22; i++) g('g$i', i == 1 ? [] : ['g${i - 1}'], at: DateTime.utc(2026, 11, 10, 10, i))];
    expectSafePrefixes(chain, 20, ['g1', 'g2']);

    final skewed = [
      g('p', [], at: DateTime.utc(2026, 11, 10, 10)),
      g('c', ['p'], at: DateTime.utc(2026, 11, 10, 9)), // child older than its parent
      for (var i = 1; i <= 5; i++) g('n$i', [i == 1 ? 'c' : 'n${i - 1}'], at: DateTime.utc(2026, 11, 10, 11, i)),
    ];
    expectSafePrefixes(skewed, 3, ['p', 'c', 'n1', 'n2']);
  });

  test('sameFiles compares path to hash maps', () {
    expect(sameFiles({'a': '1', 'b': '2'}, {'b': '2', 'a': '1'}), isTrue);
    expect(sameFiles({'a': '1'}, {'a': '2'}), isFalse);
    expect(sameFiles({}, {}), isTrue);
  });
}
