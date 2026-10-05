import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rapidfuzz/rapidfuzz.dart';

final _separators = RegExp(r'[_\W]+');
final _numeric = RegExp(r'^\d+$');
final _mixedToken = RegExp(r'^[a-z]+\d+$');
final _mixedInName = RegExp(r'\b[a-z]+\d+\b');
final _bracketedId = RegExp(r'[\[(]([A-Za-z0-9-]{4,12})[\])]');
final _bracketGroups = RegExp(r'\s*[\[(][^\])]*[\])]');

String normalizeTitle(String name) {
  return _separators
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

/// Box art names (normalized, plus "id:xxx" keys) tokenized once so each
/// [matchTitle] call only touches the names sharing its rarest tokens.
class BoxartIndex {
  final Map<String, String> boxarts;
  final List<String> names;

  /// Per name: its tokens longer than one char.
  final List<Set<String>> tokens;

  /// Per name: holds a letters+digits word ("abc2").
  final List<bool> hasMixed;

  /// Token -> ids of the names holding it, ascending (= listing order).
  final Map<String, List<int>> postings = {};

  BoxartIndex(this.boxarts)
      : names = boxarts.keys.toList(),
        tokens = [for (final n in boxarts.keys) n.split(' ').where((t) => t.length > 1).toSet()],
        hasMixed = [for (final n in boxarts.keys) _mixedInName.hasMatch(n)] {
    for (var id = 0; id < names.length; id++) {
      for (final t in tokens[id]) {
        postings.putIfAbsent(t, () => []).add(id);
      }
    }
  }
}

String? matchTitle(String titleToMatch, BoxartIndex index) {
  final normalizedTitle = normalizeTitle(titleToMatch);

  final exact = index.boxarts[normalizedTitle];
  if (exact != null) return exact;

  final titleTokens = normalizedTitle.split(' ').where((t) => t.length > 1).toList();
  final numericTokens = titleTokens.where(_numeric.hasMatch).toList();
  // Insertion order = title order, which fixes the candidate order below.
  final meaningful = [
    ...{
      for (final t in titleTokens)
        if (!_numeric.hasMatch(t)) t
    },
  ];
  final titleHasMixed = titleTokens.any(_mixedToken.hasMatch);

  // A name survives when it has no stray "abc2" word and shares >= 70% of the
  // title's non-numeric tokens.
  bool keep(int id) {
    if (!titleHasMixed && index.hasMixed[id]) return false;
    if (meaningful.isEmpty) return true;
    final nameTokens = index.tokens[id];
    return meaningful.where(nameTokens.contains).length >= meaningful.length * 0.7;
  }

  final List<int> candidates;
  if (numericTokens.isNotEmpty) {
    // Names holding every numeric token, in listing order.
    final lists = <List<int>>[];
    for (final nt in numericTokens.toSet()) {
      final l = index.postings[nt];
      if (l == null) return null;
      lists.add(l);
    }
    lists.sort((a, b) => a.length.compareTo(b.length));
    final need = numericTokens.toSet();
    candidates = [
      for (final id in lists.first)
        if (need.every(index.tokens[id].contains) && keep(id)) id,
    ];
  } else {
    if (meaningful.isEmpty) return null;
    // Smallest token count passing the 70% test; any survivor holds at least
    // one of the (m - need + 1) rarest tokens, so only their names are scanned.
    final m = meaningful.length;
    var need = 0;
    while (need < m * 0.7) {
      need++;
    }
    final byRarity = [...meaningful]..sort((a, b) => (index.postings[a]?.length ?? 0).compareTo(index.postings[b]?.length ?? 0));
    final ids = <int>{
      for (final t in byRarity.take(m - need + 1)) ...?index.postings[t],
    }.where(keep).toList();

    // Same order the old union-of-all-tokens produced: by the first title
    // token the name holds, then listing order.
    final firstToken = {for (final id in ids) id: meaningful.indexWhere(index.tokens[id].contains)};
    ids.sort((a, b) {
      final c = firstToken[a]!.compareTo(firstToken[b]!);
      return c != 0 ? c : a.compareTo(b);
    });
    candidates = ids;
  }

  String? bestMatchName;
  int highestScore = 0;
  for (final id in candidates) {
    final score = tokenSetRatio(normalizedTitle, index.names[id]).toInt();
    if (score > highestScore && score >= 90) {
      highestScore = score;
      bestMatchName = index.names[id];
      if (score >= 100) break; // nothing later can score strictly higher
    }
  }
  return bestMatchName == null ? null : index.boxarts[bestMatchName];
}

/// Box art URL for each name (filename without extension), or null.
List<String?> matchBoxartUrls(List<String> names, Map<String, String> boxarts) {
  final index = BoxartIndex(boxarts);

  return names.map((gameNameWithoutExt) {
    // Exact id match first: filenames carrying a serial/title id in brackets
    // (e.g. "Game Name [ABCD12]") beat any fuzzy name matching.
    String? boxartUrl;
    for (final m in _bracketedId.allMatches(gameNameWithoutExt)) {
      boxartUrl = boxarts['id:${m.group(1)!.toLowerCase()}'];
      if (boxartUrl != null) break;
    }

    boxartUrl ??= matchTitle(gameNameWithoutExt, index);

    // ponytail: fallback strips "(...)"/"[...]" groups so decorated names like
    // "Game (1982) (Mattel)" or "Game [ABCD12]" match plain boxart names.
    // May pick a wrong region variant; better than no art.
    if (boxartUrl == null) {
      final stripped = gameNameWithoutExt.replaceAll(_bracketGroups, '').trim();
      if (stripped.isNotEmpty && stripped != gameNameWithoutExt) {
        boxartUrl = matchTitle(stripped, index);
      }
    }
    return boxartUrl;
  }).toList();
}

/// [matchBoxartUrls] split across up to 4 isolates, results in input order.
/// Each isolate builds its own [BoxartIndex] (a few ms for thousands of names).
/// If a worker fails the whole list is retried once in a single isolate; a
/// second failure is thrown to the caller.
Future<List<String?>> matchBoxartUrlsParallel(List<String> names, Map<String, String> boxarts) async {
  // ~400 names per worker: below that, spawning and copying the listing costs
  // more than it saves.
  final workers = names.length < 500 ? 1 : (names.length ~/ 400).clamp(1, min(4, Platform.numberOfProcessors));
  final size = max(1, (names.length / workers).ceil());
  final chunks = [for (var i = 0; i < names.length; i += size) names.sublist(i, min(i + size, names.length))];
  try {
    final results = await Future.wait(chunks.map((c) => matchInIsolate(c, boxarts)));
    return [for (final r in results) ...r];
  } catch (e) {
    debugPrint('Box art matching failed ($e); retrying in one isolate');
    return matchInIsolate(names, boxarts);
  }
}

/// Runs one chunk in a fresh isolate; replaceable so tests can inject failures.
@visibleForTesting
Future<List<String?>> Function(List<String> chunk, Map<String, String> boxarts) matchInIsolate = _matchInIsolate;

// Top-level so the isolate closure captures only the chunk and the listing.
Future<List<String?>> _matchInIsolate(List<String> chunk, Map<String, String> boxarts) => Isolate.run(() => matchBoxartUrls(chunk, boxarts));
