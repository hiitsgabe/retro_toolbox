// Jumping through a game list by first letter (L1/R1 in the library).

/// The bucket a title files under, in the order the library's name sort puts
/// it (lowercased titles compared by code unit): '#' for anything before 'a'
/// (digits, punctuation, a leading space), then a to z, then each accented or
/// other-script first character after z.
// ponytail: buckets by rune; a first character outside the BMP orders a little
// differently from the code-unit sort. Compare code units if that ever shows.
String _bucket(String title) {
  final t = title.toLowerCase();
  if (t.isEmpty || t.codeUnitAt(0) < 0x61) return '#';
  return String.fromCharCode(t.runes.first);
}

/// The letter flashed for a title: 'B' for "bomberman", '#' for "007 Racing",
/// 'É' for "Éric Cantona".
String letterOf(String title) => _bucket(title).toUpperCase();

int _order(String bucket) => bucket == '#' ? -1 : bucket.runes.first;

/// Where L1/R1 lands in [titles] (the list as shown, in its own order), from
/// the focused title [fromTitle] (null when nothing is focused): the next
/// ([forward]) or previous letter that some title starts with, and the first
/// title in list order under it. Null at either end, so a held button stops
/// at the first or last letter rather than wrapping.
({String letter, int index})? letterJumpTarget(List<String> titles, String? fromTitle, {required bool forward}) {
  final firstIndex = <String, int>{};
  for (var i = 0; i < titles.length; i++) {
    firstIndex.putIfAbsent(_bucket(titles[i]), () => i);
  }
  if (firstIndex.isEmpty) return null;
  final buckets = firstIndex.keys.toList()..sort((a, b) => _order(a) - _order(b));
  final from = fromTitle == null ? null : _order(_bucket(fromTitle));
  final String? target;
  if (from == null) {
    target = forward ? buckets.first : buckets.last;
  } else if (forward) {
    target = buckets.where((b) => _order(b) > from).firstOrNull;
  } else {
    target = buckets.where((b) => _order(b) < from).lastOrNull;
  }
  return target == null ? null : (letter: target.toUpperCase(), index: firstIndex[target]!);
}
