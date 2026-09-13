/// Dart port of the builder's name functions (`tool/build_metadata_pack.py`).
/// The two must agree case by case, which `test/pack_naming_parity_test.dart`
/// proves against a golden from the real DAT.
///
/// Warning: pure Dart on purpose. Do not add a `package:flutter` import.
library;

/// The extensions No-Intro and Redump use, plus the packagers sources serve.
/// Same list as `ROM_EXTS` in the builder.
const romExtensions = <String>[
  '.zip', '.7z', '.sfc', '.smc', '.fig', '.swc', '.bin', '.rar', '.gz',
  '.nes', '.gb', '.gbc', '.gba', '.nds', '.3ds', '.n64', '.z64', '.v64',
  '.md', '.gen', '.gg', '.iso', '.cue', '.chd', '.col', '.int',
];

/// The container extensions, not ROMs. A central-directory CRC only compares
/// against the pack when the entry is the ROM itself.
const archiveExtensions = <String>['.zip', '.7z', '.rar', '.gz'];

final _byLength = [...romExtensions]..sort((a, b) => b.length.compareTo(a.length));

String stripRomExtension(String name) {
  final low = name.toLowerCase();
  for (final ext in _byLength) {
    if (low.endsWith(ext)) return name.substring(0, name.length - ext.length);
  }
  return name;
}

bool hasRomExtension(String name) {
  final low = name.toLowerCase();
  return romExtensions.any(low.endsWith);
}

bool hasArchiveExtension(String name) {
  final low = name.toLowerCase();
  return archiveExtensions.any(low.endsWith);
}

/// Diacritic-folding table. Lowercase only, because `norm` lowercases before
/// folding.
const _fold = <String, String>{
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c',
  'ď': 'd', 'đ': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'į': 'i',
  'ñ': 'n', 'ń': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o',
  'ř': 'r',
  'ś': 's', 'š': 's', 'ş': 's',
  'ť': 't',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u',
  'ý': 'y', 'ÿ': 'y',
  'ź': 'z', 'ż': 'z', 'ž': 'z',
};

String _stripDiacritics(String value) {
  final out = StringBuffer();
  for (final ch in value.split('')) {
    out.write(_fold[ch] ?? ch);
  }
  return out.toString();
}

final _disallowed = RegExp(r'[^a-z0-9()\[\]]+');
final _spaces = RegExp(r'\s+');

/// The comparable form of a name: no extension, no accents, no punctuation,
/// but with region and revision tags kept. The matcher's exact-name axis.
String norm(String value) {
  var v = stripRomExtension(value).toLowerCase();
  v = _stripDiacritics(v);
  v = v.replaceAll('&', ' and ');
  v = v.replaceAll(_disallowed, ' ');
  return v.replaceAll(_spaces, ' ').trim();
}

final _tags = RegExp(r'\([^)]*\)|\[[^\]]*\]');
final _trailingArticle = RegExp(
  r'^(.*?), (the|a|an|le|la|les|el|los|das|der|die)$',
  caseSensitive: false,
);

/// Mirror of the Python `.strip().strip(",").strip()`: trims space, then
/// commas on both ends, then space again.
String _trimSpaceThenComma(String value) {
  var v = value.trim();
  var start = 0;
  var end = v.length;
  while (start < end && v[start] == ',') {
    start++;
  }
  while (end > start && v[end - 1] == ',') {
    end--;
  }
  return v.substring(start, end).trim();
}

/// Display title from a DAT name: no extension, no tags, trailing article
/// moved back to the front, original case and accents intact.
String displayTitle(String datName) {
  var v = stripRomExtension(datName).replaceAll(_tags, ' ');
  v = _trimSpaceThenComma(v.replaceAll(_spaces, ' '));
  final match = _trailingArticle.firstMatch(v);
  if (match != null) v = '${match.group(2)} ${match.group(1)}';
  return v;
}

/// Canonical title: a game's grouping key, the display title run through [norm].
String canon(String value) => norm(displayTitle(value));
