// Box art matching benchmark (not part of the suite: the name lacks "_test").
// Run: flutter test test/boxart_match_bench.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/title_match.dart';

import 'boxart_match_test.dart';

void main() {
  test('benchmark legacy vs current matcher', () async {
    final c = buildCorpus(boxartCount: 4000, gameCount: 6500, seed: 11);
    final sw = Stopwatch()..start();
    final legacy = legacyMatchBoxartUrls(c.games, c.boxarts);
    final legacyMs = sw.elapsedMilliseconds;
    sw.reset();
    final single = matchBoxartUrls(c.games, c.boxarts);
    final singleMs = sw.elapsedMilliseconds;
    sw.reset();
    final parallel = await matchBoxartUrlsParallel(c.games, c.boxarts);
    final parallelMs = sw.elapsedMilliseconds;
    sw.reset();
    BoxartIndex(c.boxarts);
    final indexMs = sw.elapsedMilliseconds;
    expect(single, legacy);
    expect(parallel, legacy);
    // ignore: avoid_print
    print('${c.games.length} games x ${c.boxarts.length} names: legacy ${legacyMs}ms, '
        'current single-threaded ${singleMs}ms (${(legacyMs / singleMs).toStringAsFixed(1)}x), '
        'current parallel ${parallelMs}ms (${(legacyMs / parallelMs).toStringAsFixed(1)}x), index build ${indexMs}ms');
  });
}
