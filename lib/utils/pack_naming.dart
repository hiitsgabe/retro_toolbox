/// Porta Dart das funções de nome do builder (`tool/build_metadata_pack.py`).
///
/// O builder gera o pacote e o app consome, mas o app também precisa
/// normalizar nomes em runtime, porque o nome do arquivo na fonte remota nunca
/// passou pelo builder. As duas implementações têm que concordar caso a caso, e
/// é isso que `test/pack_naming_parity_test.dart` prova contra um golden
/// gerado do DAT real.
///
/// Este arquivo é Dart puro de propósito: `tool/verify_matcher.dart` o roda
/// fora do Flutter. Não adicione import de `package:flutter`.
library;

/// Extensões que o No-Intro e o Redump usam, mais os empacotadores que as
/// fontes servem. Mesma lista de `ROM_EXTS` no builder.
const romExtensions = <String>[
  '.zip', '.7z', '.sfc', '.smc', '.fig', '.swc', '.bin', '.rar', '.gz',
  '.nes', '.gb', '.gbc', '.gba', '.nds', '.3ds', '.n64', '.z64', '.v64',
  '.md', '.gen', '.gg', '.iso', '.cue', '.chd', '.col', '.int',
];

/// As que são contêiner e não ROM. Isso importa para a seção 5.8 do spec: o
/// CRC do diretório central só é comparável com o pacote quando a entrada é a
/// ROM em si. Se a entrada for outro arquivo compactado, o CRC é do compactado
/// e não casa com nada.
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

/// Tabela de dobra de acento. Só as minúsculas, porque `norm` já baixou a
/// caixa antes de dobrar. Cobre latim-1 e os pedaços de latim estendido que
/// aparecem em título de jogo europeu.
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

/// Forma comparável do nome: sem extensão, sem acento, sem pontuação, mas
/// **com** as tags de região e revisão. É o eixo do tier 1 do matcher.
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

/// Equivalente do `.strip().strip(",").strip()` do Python: apara espaço,
/// depois vírgula das duas pontas, depois espaço de novo.
String _trimSpaceThenComma(String value) {
  var v = value.trim();
  var start = 0;
  var end = v.length;
  while (start < end && v[start] == ',') start++;
  while (end > start && v[end - 1] == ',') end--;
  return v.substring(start, end).trim();
}

/// Título de exibição a partir do nome do DAT: sem extensão, sem tags, com o
/// artigo de volta na frente, e com a caixa e os acentos originais intactos.
String displayTitle(String datName) {
  var v = stripRomExtension(datName).replaceAll(_tags, ' ');
  v = _trimSpaceThenComma(v.replaceAll(_spaces, ' '));
  final match = _trailingArticle.firstMatch(v);
  if (match != null) v = '${match.group(2)} ${match.group(1)}';
  return v;
}

/// Título canônico: a chave de agrupamento de um jogo. É o título de exibição
/// passado por [norm].
String canon(String value) => norm(displayTitle(value));
