import 'dart:convert';

/// Um dump concreto de um jogo, como o DAT do No-Intro ou do Redump descreve.
/// [name] é o nome do jogo no DAT, sem extensão, com as tags de região e
/// revisão preservadas, porque é ele que o matcher compara com o nome do
/// arquivo remoto.
///
/// [crc] e [sha1] são normalizados para maiúsculas, porque são hexadecimais e a
/// comparação precisa ser estável entre o DAT e o que o app calcula. O [serial]
/// não é: ele é uma string de catálogo do fabricante, com maiúsculas e hifens
/// que fazem parte do valor, e é gravado exatamente como o DAT emite.
/// [region] é a região declarada no DAT, quando existe. Nem todo bloco traz
/// uma: no SNES 293 dos 4268 blocos não têm, no GameCube 33 de 2268. Por isso é
/// opcional. Ela existe para a regra de região preferida do download em lote e
/// para o cartão de detalhe mostrar "(USA)" sem reparsear o nome em runtime.
class PackDump {
  final String name;
  final String? crc;
  final String? sha1;
  final String? serial;
  final String? region;

  const PackDump({
    required this.name,
    this.crc,
    this.sha1,
    this.serial,
    this.region,
  });

  factory PackDump.fromJson(Map<String, dynamic> json) => PackDump(
        name: json['name'] as String,
        crc: (json['crc'] as String?)?.toUpperCase(),
        sha1: (json['sha1'] as String?)?.toUpperCase(),
        serial: json['serial'] as String?,
        region: json['region'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (crc != null) 'crc': crc,
        if (sha1 != null) 'sha1': sha1,
        if (serial != null) 'serial': serial,
        if (region != null) 'region': region,
      };
}

/// Um jogo canônico: um título, várias versões.
class PackGame {
  final String id;
  final String title;
  final List<PackDump> dumps;
  final String? cover;
  final String? synopsis;
  final String? genre;
  final String? developer;
  final String? publisher;
  final int? year;

  const PackGame({
    required this.id,
    required this.title,
    required this.dumps,
    this.cover,
    this.synopsis,
    this.genre,
    this.developer,
    this.publisher,
    this.year,
  });

  factory PackGame.fromJson(Map<String, dynamic> json) => PackGame(
        id: json['id'] as String,
        title: json['title'] as String,
        dumps: ((json['dumps'] as List?) ?? const [])
            .map((e) => PackDump.fromJson(e as Map<String, dynamic>))
            .toList(),
        cover: json['cover'] as String?,
        synopsis: json['synopsis'] as String?,
        genre: json['genre'] as String?,
        developer: json['developer'] as String?,
        publisher: json['publisher'] as String?,
        year: json['year'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dumps': dumps.map((d) => d.toJson()).toList(),
        if (cover != null) 'cover': cover,
        if (synopsis != null) 'synopsis': synopsis,
        if (genre != null) 'genre': genre,
        if (developer != null) 'developer': developer,
        if (publisher != null) 'publisher': publisher,
        if (year != null) 'year': year,
      };
}

/// O pacote de um console inteiro.
class MetadataPack {
  final String pack;
  final String system;
  final String built;
  final List<PackGame> games;

  MetadataPack({
    required this.pack,
    required this.system,
    required this.built,
    required this.games,
  });

  Map<String, PackGame>? _byCrc;

  /// CRC32 em maiúsculas para o jogo dono daquele dump. Construído sob demanda
  /// e guardado, porque um pacote grande tem dezenas de milhares de dumps.
  Map<String, PackGame> get byCrc {
    final cached = _byCrc;
    if (cached != null) return cached;
    final map = <String, PackGame>{};
    for (final game in games) {
      for (final dump in game.dumps) {
        final crc = dump.crc;
        if (crc != null) map[crc] = game;
      }
    }
    return _byCrc = map;
  }

  factory MetadataPack.fromJson(Map<String, dynamic> json) => MetadataPack(
        pack: json['pack'] as String,
        system: json['system'] as String,
        built: json['built'] as String,
        games: ((json['games'] as List?) ?? const [])
            .map((e) => PackGame.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'pack': pack,
        'system': system,
        'built': built,
        'games': games.map((g) => g.toJson()).toList(),
      };

  static MetadataPack decode(String jsonStr) =>
      MetadataPack.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}
