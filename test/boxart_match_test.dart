import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rapidfuzz/rapidfuzz.dart';
import 'package:retro_toolbox/utils/title_match.dart';

// ---------------------------------------------------------------------------
// Reference implementation: the matcher as it was before the speed-up, copied
// verbatim. The golden test below asserts the shipped matcher picks exactly
// the same box art for every game of a large synthetic corpus.
// ---------------------------------------------------------------------------

String legacyNormalizeTitle(String name) {
  return RegExp(r'[_\W]+')
      .allMatches(name.toLowerCase())
      .fold<StringBuffer>(StringBuffer(), (b, m) {
        b
          ..write(name.substring(b.length, m.start).replaceAll('_', ' '))
          ..write(' ');
        return b;
      })
      .toString()
      .trim();
}

Map<String, List<String>> legacyBuildTokenIndex(Iterable<String> names) {
  final Map<String, List<String>> index = {};
  for (final name in names) {
    for (final token in name.split(' ')) {
      if (token.length > 1) {
        index.putIfAbsent(token, () => []).add(name);
      }
    }
  }
  return index;
}

String? legacyMatch({
  required String titleToMatch,
  required Map<String, String> candidates,
  required Map<String, List<String>> tokenIndex,
}) {
  final normalizedTitle = legacyNormalizeTitle(titleToMatch);

  if (candidates.containsKey(normalizedTitle)) {
    return candidates[normalizedTitle];
  }

  final numericRegExp = RegExp(r'^\d+$');
  final mixedTokenRegExp = RegExp(r'^[a-z]+\d+$');
  final titleTokens = normalizedTitle.split(' ').where((token) {
    return token.length > 1;
  }).toList();

  final numericTokens = titleTokens.where((t) => numericRegExp.hasMatch(t)).toList();

  Set<String> candidateNames = {};

  if (numericTokens.isNotEmpty) {
    Set<String>? intersection;
    for (final nt in numericTokens) {
      final names = tokenIndex[nt];
      if (names == null) {
        intersection = <String>{};
        break;
      }
      final nameSet = names.toSet();
      intersection = intersection == null ? nameSet : intersection.intersection(nameSet);
      if (intersection.isEmpty) break;
    }
    candidateNames = intersection ?? <String>{};
  }

  if (candidateNames.isEmpty && numericTokens.isEmpty) {
    for (final token in titleTokens.where((t) => !numericRegExp.hasMatch(t))) {
      final names = tokenIndex[token];
      if (names != null) candidateNames.addAll(names);
    }
  }

  if (candidateNames.isEmpty) {
    return null;
  }

  final mixedTokens = titleTokens.where((t) => mixedTokenRegExp.hasMatch(t)).toList();

  final hasMixedTokensInGame = mixedTokens.isNotEmpty;
  candidateNames = candidateNames.where((name) {
    if (!hasMixedTokensInGame && RegExp(r'\b[a-z]+\d+\b').hasMatch(name)) {
      return false;
    }
    return true;
  }).toSet();

  // Generic meaningful-token Jaccard style filter.
  if (candidateNames.isNotEmpty) {
    final Set<String> meaningfulGameTokens = {
      for (final t in titleTokens)
        if (!numericRegExp.hasMatch(t) && t.length > 1) t
    };

    if (meaningfulGameTokens.isNotEmpty) {
      candidateNames = candidateNames.where((name) {
        final tokens = name.split(' ').where((tok) => tok.length > 1 && !numericRegExp.hasMatch(tok)).toSet();
        final int common = tokens.intersection(meaningfulGameTokens).length;
        return common >= meaningfulGameTokens.length * 0.7;
      }).toSet();
    }
  }

  if (candidateNames.isEmpty) return null;

  final Iterable<String> searchSpace = candidateNames;

  String? bestMatchName;
  int highestScore = 0;
  for (final candidate in searchSpace) {
    final score = tokenSetRatio(normalizedTitle, candidate).toInt();
    if (score > highestScore && score >= 90) {
      highestScore = score;
      bestMatchName = candidate;
    }
  }
  if (bestMatchName != null) {
    return candidates[bestMatchName];
  }
  return null;
}

/// The per-game steps of the old `_process` (id, name, then stripped name).
List<String?> legacyMatchBoxartUrls(List<String> names, Map<String, String> boxarts) {
  final tokenIndex = legacyBuildTokenIndex(boxarts.keys);
  final bracketedId = RegExp(r'[\[(]([A-Za-z0-9-]{4,12})[\])]');
  return names.map((gameNameWithoutExt) {
    String? boxartUrl;
    for (final m in bracketedId.allMatches(gameNameWithoutExt)) {
      boxartUrl = boxarts['id:${m.group(1)!.toLowerCase()}'];
      if (boxartUrl != null) break;
    }
    boxartUrl ??= legacyMatch(titleToMatch: gameNameWithoutExt, candidates: boxarts, tokenIndex: tokenIndex);
    if (boxartUrl == null) {
      final stripped = gameNameWithoutExt.replaceAll(RegExp(r'\s*[\[(][^\])]*[\])]'), '').trim();
      if (stripped.isNotEmpty && stripped != gameNameWithoutExt) {
        boxartUrl = legacyMatch(titleToMatch: stripped, candidates: boxarts, tokenIndex: tokenIndex);
      }
    }
    return boxartUrl;
  }).toList();
}

// ---------------------------------------------------------------------------
// Deterministic synthetic corpus: made-up words, sequel numbers, mixed tokens
// ("abc2"), region/bracket decorations, near-duplicates and noise.
// ---------------------------------------------------------------------------

class Corpus {
  final Map<String, String> boxarts; // normalized name (or id:xxx) -> url
  final List<String> games; // filenames without extension
  Corpus(this.boxarts, this.games);
}

Corpus buildCorpus({required int boxartCount, required int gameCount, int seed = 7}) {
  final r = Random(seed);
  T pick<T>(List<T> l) => l[r.nextInt(l.length)];

  const syllables = [
    'ka',
    'lo',
    'mi',
    'zu',
    'ter',
    'ran',
    'vex',
    'qua',
    'dor',
    'fin',
    'gal',
    'hes',
    'ix',
    'om',
    'pra',
    'sol',
    'tor',
    'um',
    'wy',
    'zen',
    'bri',
    'cor',
    'el',
    'nu',
  ];
  final words = <String>{};
  while (words.length < 300) {
    final w = List.generate(1 + r.nextInt(3), (_) => pick(syllables)).join();
    if (w.length > 1) words.add(w[0].toUpperCase() + w.substring(1));
  }
  final pool = words.toList();
  // A few very common words so the token index has long posting lists.
  const common = ['The', 'Of', 'Super', 'World', 'Quest', 'Racing', 'Legend'];
  const regions = [
    '(USA)',
    '(Europe)',
    '(Japan)',
    '(World)',
    '(USA, Europe)',
    '(En,Fr,De)',
    '(Rev 1)',
    '(Beta)',
    '(Proto)',
    '(Disc 1)',
    '(Japan) (Rev 2)',
    '[!]',
    '(USA) [b]',
  ];
  const mixed = ['abc2', 'mk2', 'x360', 'vol3', 'ep1', 'MK2', 'Zx81'];
  const numbers = ['2', '3', '4', '64', '2000', '99', '16', '32', '128', '98', 'II', 'III'];
  const seps = [' ', ' ', ' ', ' - ', ': ', '_', ' & '];

  String baseTitle() {
    final n = 1 + r.nextInt(4);
    final parts = <String>[];
    for (var i = 0; i < n; i++) {
      parts.add(r.nextInt(5) == 0 ? pick(common) : pick(pool));
    }
    if (r.nextInt(4) == 0) parts.add(pick(numbers));
    if (r.nextInt(10) == 0) parts.insert(r.nextInt(parts.length + 1), pick(mixed));
    final b = StringBuffer(parts.first);
    for (final p in parts.skip(1)) {
      b.write(r.nextInt(6) == 0 ? pick(seps) : ' ');
      b.write(p);
    }
    if (r.nextInt(12) == 0) b.write("'s");
    if (r.nextInt(15) == 0) b.write('!');
    return b.toString();
  }

  // Box art filenames: base titles with region variants, sequels and ids.
  final bases = <String>[];
  final boxartNames = <String>[];
  while (boxartNames.length < boxartCount) {
    final base = baseTitle();
    bases.add(base);
    final variants = 1 + r.nextInt(3);
    for (var v = 0; v < variants; v++) {
      boxartNames.add(r.nextInt(20) == 0 ? base : '$base ${pick(regions)}');
    }
    if (r.nextInt(6) == 0) boxartNames.add('$base ${pick(numbers)} ${pick(regions)}');
  }

  final boxarts = <String, String>{};
  for (var i = 0; i < boxartNames.length; i++) {
    boxarts[normalizeTitle(boxartNames[i])] = 'https://img.test/$i.png';
  }
  final ids = <String>[];
  for (var i = 0; i < boxartCount ~/ 30; i++) {
    final id = 'ABCD${1000 + i}';
    ids.add(id);
    boxarts['id:${id.toLowerCase()}'] = 'https://img.test/id$i.png';
  }

  // Game filenames: mutations of box art names / base titles plus noise.
  String mutate(String s) {
    switch (r.nextInt(14)) {
      case 0:
        return s; // exact
      case 1:
        return '$s ${pick(regions)}';
      case 2:
        return s.toUpperCase();
      case 3:
        final w = s.split(' ')..removeAt(r.nextInt(s.split(' ').length));
        return w.isEmpty ? s : w.join(' ');
      case 4:
        final w = s.split(' ')..insert(r.nextInt(s.split(' ').length + 1), r.nextBool() ? pick(pool) : pick(numbers));
        return w.join(' ');
      case 5:
        final w = s.split(' ');
        if (w.length > 1) {
          final i = r.nextInt(w.length - 1);
          final t = w[i];
          w[i] = w[i + 1];
          w[i + 1] = t;
        }
        return w.join(' ');
      case 6:
        return '$s ${pick(numbers)}';
      case 7:
        return '$s [${pick(ids)}]';
      case 8:
        return '$s [ZZZZ${r.nextInt(99)}]';
      case 9:
        return '$s ${pick(mixed)} ${pick(regions)}';
      case 10:
        return s.replaceAll(' ', '_');
      case 11:
        return '${pick(common)} $s';
      case 12:
        return s.toLowerCase();
      default:
        return '$s ${pick(regions)} ${pick(regions)}';
    }
  }

  final games = <String>[];
  while (games.length < gameCount) {
    final kind = r.nextInt(10);
    if (kind < 4) {
      games.add(mutate(pick(boxartNames)));
    } else if (kind < 8) {
      games.add(mutate(pick(bases)));
    } else if (kind < 9) {
      games.add(mutate(mutate(pick(boxartNames))));
    } else {
      games.add('${baseTitle()} ${pick(regions)}'); // mostly unmatched noise
    }
  }
  return Corpus(boxarts, games);
}

void main() {
  test('synthetic corpus exercises every matcher path', () {
    final c = buildCorpus(boxartCount: 3000, gameCount: 2000);
    final legacy = legacyMatchBoxartUrls(c.games, c.boxarts);
    final exact = c.games.where((g) => c.boxarts.containsKey(legacyNormalizeTitle(g))).length;
    final matched = legacy.where((u) => u != null).length;
    final byId = legacy.where((u) => u != null && u.contains('/id')).length;
    // Plenty of fuzzy matches, plenty of misses, and the id path is hit.
    expect(matched - exact - byId, greaterThan(300));
    expect(legacy.length - matched, greaterThan(200));
    expect(byId, greaterThan(20));
  });

  test('golden: matcher picks exactly the same box art as the legacy matcher', () {
    final c = buildCorpus(boxartCount: 3000, gameCount: 2000);

    final sw = Stopwatch()..start();
    final legacy = legacyMatchBoxartUrls(c.games, c.boxarts);
    final legacyMs = sw.elapsedMilliseconds;

    sw.reset();
    final current = matchBoxartUrls(c.games, c.boxarts);
    final currentMs = sw.elapsedMilliseconds;

    // ignore: avoid_print
    print('boxart match ${c.games.length} games x ${c.boxarts.length} names: '
        'legacy ${legacyMs}ms, current ${currentMs}ms');

    for (var i = 0; i < c.games.length; i++) {
      expect(current[i], legacy[i], reason: 'game #$i "${c.games[i]}"');
    }
  });

  test('parallel matching keeps input order and results', () async {
    final c = buildCorpus(boxartCount: 1500, gameCount: 1200, seed: 3);
    expect(await matchBoxartUrlsParallel(c.games, c.boxarts), matchBoxartUrls(c.games, c.boxarts));
    expect(await matchBoxartUrlsParallel(c.games.take(10).toList(), c.boxarts), matchBoxartUrls(c.games.take(10).toList(), c.boxarts));
    expect(await matchBoxartUrlsParallel([], c.boxarts), isEmpty);
  });
}
