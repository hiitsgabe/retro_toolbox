import 'dart:convert';

/// A concrete dump of a game, as a No-Intro or Redump DAT describes it.
/// [name] is the DAT name, without extension, with region and revision tags
/// preserved, because the matcher compares it against the remote filename.
///
/// [crc] and [sha1] are uppercased for stable comparison; [serial] is not, as
/// its case and hyphens are part of the value. [region] is the DAT region when
/// present, and is optional because not every dump declares one.
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

/// A canonical game: one title, several versions.
class PackGame {
  final String id;
  final String title;
  final List<PackDump> dumps;
  final String? cover;

  /// In-game capture. Independent of [titleScreen]: a game can have one and
  /// not the other, because they come from two separate folders.
  final String? screenshot;
  final String? titleScreen;
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
    this.screenshot,
    this.titleScreen,
    this.synopsis,
    this.genre,
    this.developer,
    this.publisher,
    this.year,
  });

  /// The captures to show, in the order they should appear, skipping the ones
  /// the pack does not carry.
  List<String> get shots => [
        if ((screenshot ?? '').isNotEmpty) screenshot!,
        if ((titleScreen ?? '').isNotEmpty) titleScreen!,
      ];

  factory PackGame.fromJson(Map<String, dynamic> json) => PackGame(
        id: json['id'] as String,
        title: json['title'] as String,
        dumps: ((json['dumps'] as List?) ?? const [])
            .map((e) => PackDump.fromJson(e as Map<String, dynamic>))
            .toList(),
        cover: json['cover'] as String?,
        screenshot: json['screenshot'] as String?,
        titleScreen: json['titleScreen'] as String?,
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
        if (screenshot != null) 'screenshot': screenshot,
        if (titleScreen != null) 'titleScreen': titleScreen,
        if (synopsis != null) 'synopsis': synopsis,
        if (genre != null) 'genre': genre,
        if (developer != null) 'developer': developer,
        if (publisher != null) 'publisher': publisher,
        if (year != null) 'year': year,
      };
}

/// The pack for a whole console.
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

  /// Uppercase CRC32 to the game owning that dump. Built lazily and cached.
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
