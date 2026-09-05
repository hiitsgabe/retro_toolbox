/// Filename↔search-term matching for finding a sports game in the catalog.
/// Ported from console_utilities' rom_finder: normalize (drop extension, region
/// tags, punctuation), then score exact=100 / substring=80 / token-Jaccard×60.
/// A score ≥ [kRomMatchThreshold] is a match.

const int kRomMatchThreshold = 50;

final _extRe = RegExp(r'\.\w{2,4}$');
final _regionRe = RegExp(r'\([^)]*\)');
final _punctRe = RegExp(r"['\-.,!]");
final _multiSpace = RegExp(r'\s+');

String normalizeRomName(String name) {
  var s = name;
  s = s.replaceAll(_extRe, '');
  s = s.replaceAll(_regionRe, ' ');
  s = s.replaceAll(_punctRe, ' ');
  s = s.toLowerCase().trim();
  s = s.replaceAll(_multiSpace, ' ');
  return s;
}

int romFuzzyScore(String searchTerm, String filename) {
  final ns = normalizeRomName(searchTerm);
  final nf = normalizeRomName(filename);
  if (ns.isEmpty || nf.isEmpty) return 0;
  if (ns == nf) return 100;
  if (nf.contains(ns)) return 80;
  final searchTokens = ns.split(' ').toSet();
  final fileTokens = nf.split(' ').toSet();
  if (searchTokens.isEmpty) return 0;
  final overlap = searchTokens.intersection(fileTokens).length;
  final total = searchTokens.union(fileTokens).length;
  return total == 0 ? 0 : (overlap / total * 60).round();
}

/// Best score of any [terms] against [filename].
int romBestScore(String filename, List<String> terms) {
  var best = 0;
  for (final t in terms) {
    final s = romFuzzyScore(t, filename);
    if (s > best) best = s;
  }
  return best;
}

final _betaDemoRe = RegExp(r'\b(beta|demo|proto|sample)\b', caseSensitive: false);

/// Tiebreak among equally-scored matches: prefer [region], then non-beta/demo,
/// then shorter names. Lower tuple sorts first. Ported from console_utilities.
/// Returns a comparable list [regionRank, betaRank, length].
List<int> romTiebreak(String filename, String region) {
  final lower = filename.toLowerCase();
  final hasPref = lower.contains('(${region.toLowerCase()})') ? 0 : 1;
  final isBeta = _betaDemoRe.hasMatch(filename) ? 1 : 0;
  return [hasPref, isBeta, filename.length];
}

/// Compares two tiebreak keys; negative if [a] should come first.
int compareTiebreak(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}
