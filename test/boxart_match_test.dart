import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/title_match.dart';

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
  Map<String, String> arts(List<String> names) => {for (final n in names) normalizeTitle(n): 'https://art/${normalizeTitle(n)}'};
  String? art(Map<String, String> boxarts, String game) => matchBoxartUrls([game], boxarts).single;

  test('normalizeTitle: lowercase words, apostrophes dropped, punctuation a break', () {
    expect(normalizeTitle("Zorb: Quest-Two's  Run_Off"), 'zorb quest twos run off');
    expect(normalizeTitle('A: B'), 'a b');
    expect(normalizeTitle('Game - Sub Title'), 'game sub title');
  });

  test('sequels keep their own art: numbers must agree, arabic or roman', () {
    final b = arts(['Zorb Quest', 'Zorb Quest II', 'Zorb Quest III', 'Zorb Quest IV']);
    expect(art(b, 'Zorb Quest (USA)'), 'https://art/zorb quest');
    expect(art(b, 'Zorb Quest II (Europe) (En,Fr)'), 'https://art/zorb quest ii');
    expect(art(b, 'Zorb Quest 3 (USA)'), 'https://art/zorb quest iii');
    expect(art(b, 'Zorb Quest V (USA)'), isNull); // not IV's art
    // Disc numbers and dates are tags, not sequel numbers.
    expect(art(b, 'Zorb Quest II (USA) (Disc 2) (2009-11-18)'), 'https://art/zorb quest ii');
  });

  test('a subtitle picks its own art, not the first name it contains', () {
    final b = arts(['Vexa Saga', 'Vexa Saga: Ironfall', 'Vexa Saga: Dawnreach']);
    expect(art(b, 'Vexa Saga - Ironfall (USA)'), 'https://art/vexa saga ironfall');
    expect(art(b, 'Vexa Saga - Dawnreach (Japan)'), 'https://art/vexa saga dawnreach');
    expect(art(b, 'Vexa Saga (Europe)'), 'https://art/vexa saga');
  });

  test('edition words still find the base art', () {
    final b = arts(['Kalo Dorm Run']);
    expect(art(b, 'Kalo: Dorm Run - Game of the Year Edition (USA)'), 'https://art/kalo dorm run');
    expect(art(b, 'Kalo - Dorm Run (USA) (Essentials)'), 'https://art/kalo dorm run');
  });

  test('parallel matching keeps input order and results', () async {
    final c = buildCorpus(boxartCount: 1500, gameCount: 1200, seed: 3);
    expect(await matchBoxartUrlsParallel(c.games, c.boxarts), matchBoxartUrls(c.games, c.boxarts));
    expect(await matchBoxartUrlsParallel(c.games.take(10).toList(), c.boxarts), matchBoxartUrls(c.games.take(10).toList(), c.boxarts));
    expect(await matchBoxartUrlsParallel([], c.boxarts), isEmpty);
  });

  test('a failing worker is retried once in a single isolate', () async {
    final c = buildCorpus(boxartCount: 1500, gameCount: 1200, seed: 5);
    final saved = matchInIsolate;
    addTearDown(() => matchInIsolate = saved);
    final calls = <int>[];
    matchInIsolate = (chunk, boxarts) {
      calls.add(chunk.length);
      if (calls.length == 1) throw StateError('worker died');
      return saved(chunk, boxarts);
    };
    expect(await matchBoxartUrlsParallel(c.games, c.boxarts), matchBoxartUrls(c.games, c.boxarts));
    expect(calls.last, c.games.length); // the retry ran the whole list at once

    matchInIsolate = (_, __) async => throw StateError('worker died');
    expect(matchBoxartUrlsParallel(c.games, c.boxarts), throwsStateError);
  });
}
