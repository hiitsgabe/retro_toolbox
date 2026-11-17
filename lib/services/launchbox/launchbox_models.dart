/// The LaunchBox image types the app shows, with the `Type` text that names
/// each in Metadata.xml and the short code stored on disk.
enum LaunchboxImageType {
  boxFront('Box - Front', 'bf'),
  boxBack('Box - Back', 'bb'),
  clearLogo('Clear Logo', 'cl'),
  fanart('Fanart - Background', 'fa'),
  screenshot('Screenshot - Gameplay', 'sg'),
  titleScreen('Screenshot - Game Title', 'st');

  const LaunchboxImageType(this.xmlName, this.code);
  final String xmlName;
  final String code;

  static final _byXml = {for (final t in values) t.xmlName: t};
  static final _byCode = {for (final t in values) t.code: t};

  static LaunchboxImageType? fromXml(String name) => _byXml[name];
  static LaunchboxImageType? fromCode(String code) => _byCode[code];
}

class LaunchboxImage {
  const LaunchboxImage(this.type, this.file, [this.region]);
  final LaunchboxImageType type;

  /// File name on the image host, e.g. "41ba4239-....jpg".
  final String file;

  /// e.g. "North America"; null when the row has none.
  final String? region;

  String get url => 'https://images.launchbox-app.com/$file';
}

class LaunchboxGame {
  /// LaunchBox's DatabaseID.
  final int id;
  final String name;
  final List<String> alternateNames;

  /// yyyymmdd; an unknown month or day is 00, as in GameDetails.releaseDate.
  final int? releaseDate;
  final String? overview;
  final int? maxPlayers;
  final bool cooperative;

  /// CommunityRating, 0..5.
  final double? rating;
  final int? ratingCount;
  final List<String> genres;
  final String? developer;
  final String? publisher;
  final String? esrb;
  final List<LaunchboxImage> images;

  const LaunchboxGame({
    required this.id,
    required this.name,
    this.alternateNames = const [],
    this.releaseDate,
    this.overview,
    this.maxPlayers,
    this.cooperative = false,
    this.rating,
    this.ratingCount,
    this.genres = const [],
    this.developer,
    this.publisher,
    this.esrb,
    this.images = const [],
  });

  /// Compact form for the per-platform files: tens of thousands of games per
  /// file, so keys are short and null or empty fields are left out.
  Map<String, dynamic> toJson() => {
    'i': id,
    'n': name,
    if (alternateNames.isNotEmpty) 'a': alternateNames,
    if (releaseDate != null) 'd': releaseDate,
    if (overview != null) 'o': overview,
    if (maxPlayers != null) 'p': maxPlayers,
    if (cooperative) 'c': true,
    if (rating != null) 'r': rating,
    if (ratingCount != null) 'v': ratingCount,
    if (genres.isNotEmpty) 'g': genres,
    if (developer != null) 'dev': developer,
    if (publisher != null) 'pub': publisher,
    if (esrb != null) 'e': esrb,
    if (images.isNotEmpty)
      'img': [
        for (final i in images) [i.type.code, i.file, if (i.region != null) i.region],
      ],
  };

  factory LaunchboxGame.fromJson(Map<String, dynamic> json) {
    final images = <LaunchboxImage>[];
    for (final raw in (json['img'] as List?) ?? const []) {
      final row = raw as List;
      // A code from a newer app version: skip it rather than fail the file.
      final type = LaunchboxImageType.fromCode(row[0] as String);
      if (type == null) continue;
      images.add(LaunchboxImage(type, row[1] as String, row.length > 2 ? row[2] as String? : null));
    }
    return LaunchboxGame(
      id: json['i'] as int,
      name: json['n'] as String,
      alternateNames: List<String>.from(json['a'] ?? const []),
      releaseDate: json['d'] as int?,
      overview: json['o'] as String?,
      maxPlayers: json['p'] as int?,
      cooperative: json['c'] == true,
      rating: (json['r'] as num?)?.toDouble(),
      ratingCount: json['v'] as int?,
      genres: List<String>.from(json['g'] ?? const []),
      developer: json['dev'] as String?,
      publisher: json['pub'] as String?,
      esrb: json['e'] as String?,
      images: images,
    );
  }

  LaunchboxGame withExtras({List<String>? alternateNames, List<LaunchboxImage>? images}) => LaunchboxGame(
    id: id,
    name: name,
    alternateNames: alternateNames ?? this.alternateNames,
    releaseDate: releaseDate,
    overview: overview,
    maxPlayers: maxPlayers,
    cooperative: cooperative,
    rating: rating,
    ratingCount: ratingCount,
    genres: genres,
    developer: developer,
    publisher: publisher,
    esrb: esrb,
    images: images ?? this.images,
  );
}

/// A game from the text of a `<Game>` element's fields, keyed by element name.
/// Null when it has no usable DatabaseID or Name.
LaunchboxGame? launchboxGameFromFields(Map<String, String> f) {
  String? text(String key) {
    final v = f[key]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  final id = int.tryParse(text('DatabaseID') ?? '');
  final name = text('Name');
  if (id == null || name == null) return null;
  return LaunchboxGame(
    id: id,
    name: name,
    releaseDate: _releaseDate(text('ReleaseDate'), text('ReleaseYear')),
    overview: text('Overview'),
    maxPlayers: int.tryParse(text('MaxPlayers') ?? ''),
    cooperative: text('Cooperative')?.toLowerCase() == 'true',
    rating: double.tryParse(text('CommunityRating') ?? ''),
    ratingCount: int.tryParse(text('CommunityRatingCount') ?? ''),
    genres: [
      for (final g in (text('Genres') ?? '').split(';'))
        if (g.trim().isNotEmpty) g.trim(),
    ],
    developer: text('Developer'),
    publisher: text('Publisher'),
    esrb: text('ESRB'),
  );
}

/// ReleaseDate is "yyyy-mm-dd", sometimes with a time after it; it is more
/// precise than ReleaseYear, so it wins when both are there.
int? _releaseDate(String? date, String? year) {
  if (date != null) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date.length > 10 ? date.substring(0, 10) : date);
    if (m == null) return null;
    return int.parse(m[1]!) * 10000 + int.parse(m[2]!) * 100 + int.parse(m[3]!);
  }
  final y = int.tryParse(year ?? '');
  return y == null ? null : y * 10000;
}
