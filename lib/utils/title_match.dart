import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:rapidfuzz/rapidfuzz.dart';

final _apostrophes = RegExp(r"['\u2019]");
final _separators = RegExp(r'[_\W]+');
final _numeric = RegExp(r'^\d+$');
final _mixedToken = RegExp(r'^[a-z]+\d+$');
final _mixedInName = RegExp(r'\b[a-z]+\d+\b');
final _bracketedId = RegExp(r'[\[(]([A-Za-z0-9-]{4,12})[\])]');
final _bracketGroups = RegExp(r'\s*[\[(][^\])]*[\])]');

/// Lowercase words separated by single spaces: apostrophes dropped
/// ("it's" -> "its"), any other punctuation a word break ("a: b-c" -> "a b c").
String normalizeTitle(String name) =>
    name.toLowerCase().replaceAll(_apostrophes, '').replaceAll(_separators, ' ').trim();

final _roman = RegExp(r'^(?=[ivxl])l?x{0,3}(ix|iv|v?i{0,3})$');
const _romanValue = {'i': 1, 'v': 5, 'x': 10, 'l': 50};

/// The sequel numbers in a normalized name, arabic or roman ("2" = "ii"):
/// a game and its box art must agree on them.
Set<int> sequelMarkers(String normalized) {
  final out = <int>{};
  for (final t in normalized.split(' ')) {
    if (_numeric.hasMatch(t)) {
      out.add(int.parse(t));
    } else if (_roman.hasMatch(t)) {
      var v = 0;
      for (var i = 0; i < t.length; i++) {
        final c = _romanValue[t[i]]!;
        final next = i + 1 < t.length ? _romanValue[t[i + 1]]! : 0;
        v += c < next ? -c : c;
      }
      out.add(v);
    }
  }
  return out;
}

/// Edition and filler words: a title may carry them on top of the box art
/// name ("x game of the year edition" still gets "x"'s art).
const _noise = {'the', 'of', 'game', 'year', 'goty', 'edition', 'special', 'collectors', 'limited', 'platinum', 'hits', 'classics', 'essentials', 'complete'};

bool _sameMarkers(Set<int> a, Set<int> b) => a.length == b.length && a.containsAll(b);

/// Box art names (normalized, plus "id:xxx" keys) tokenized once so each
/// [matchTitle] call only touches the names sharing its rarest tokens.
class BoxartIndex {
  final Map<String, String> boxarts;
  final List<String> names;

  /// Per name: its tokens longer than one char.
  final List<Set<String>> tokens;

  /// Per name: holds a letters+digits word ("abc2").
  final List<bool> hasMixed;

  /// Per name: its [sequelMarkers].
  final List<Set<int>> markers;

  /// Token -> ids of the names holding it, ascending (= listing order).
  final Map<String, List<int>> postings = {};

  BoxartIndex(this.boxarts)
      : names = boxarts.keys.toList(),
        tokens = [for (final n in boxarts.keys) n.split(' ').where((t) => t.length > 1).toSet()],
        hasMixed = [for (final n in boxarts.keys) _mixedInName.hasMatch(n)],
        markers = [for (final n in boxarts.keys) sequelMarkers(n)] {
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
        if (!_numeric.hasMatch(t) && !_noise.contains(t)) t
    },
  ];
  final titleHasMixed = titleTokens.any(_mixedToken.hasMatch);
  final titleMarkers = sequelMarkers(normalizedTitle);

  // A name survives when it has no stray "abc2" word, the same sequel numbers
  // and >= 70% of the title's non-numeric tokens.
  bool keep(int id) {
    if (!titleHasMixed && index.hasMixed[id]) return false;
    if (!_sameMarkers(titleMarkers, index.markers[id])) return false;
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

  // Token-set >= 90 admits a name; the closest whole name (token-sort) wins,
  // so "a b" beats "a b c" for title "a b" instead of whichever came first.
  String? bestMatchName;
  var best = -1;
  for (final id in candidates) {
    final name = index.names[id];
    if (tokenSetRatio(normalizedTitle, name) < 90) continue;
    final score = tokenSortRatio(normalizedTitle, name).toInt();
    if (score > best) {
      best = score;
      bestMatchName = name;
      if (score >= 100) break;
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

    // Exact full name (some listings keep the tags), else the name without its
    // "(...)"/"[...]" groups: region, language, disc and date tags add words
    // and numbers the box art name lacks.
    boxartUrl ??= index.boxarts[normalizeTitle(gameNameWithoutExt)];
    if (boxartUrl == null) {
      final stripped = gameNameWithoutExt.replaceAll(_bracketGroups, '').trim();
      boxartUrl = matchTitle(stripped.isEmpty ? gameNameWithoutExt : stripped, index);
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
