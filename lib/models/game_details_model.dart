class GameDetails {
  final String? boxart;
  /// yyyymmdd; an unknown month or day is 00 (a year-only 1999 is 19990000).
  final int? releaseDate;
  final int? popularity;
  /// LaunchBox DatabaseID of the matched game, in [launchboxPlatform]'s file.
  final int? launchboxId;
  final String? launchboxPlatform;
  /// LaunchBox community rating, 0..5, and its vote count.
  final double? rating;
  final int? ratingCount;
  final List<String> genres;
  final int? maxPlayers;
  final bool? cooperative;

  const GameDetails({
    this.boxart,
    this.releaseDate,
    this.popularity,
    this.launchboxId,
    this.launchboxPlatform,
    this.rating,
    this.ratingCount,
    this.genres = const [],
    this.maxPlayers,
    this.cooperative,
  });

  factory GameDetails.fromJson(Map<String, dynamic> json) {
    return GameDetails(
      boxart: json['boxart'],
      releaseDate: json['releaseDate'],
      popularity: json['popularity'],
      launchboxId: json['launchboxId'],
      launchboxPlatform: json['launchboxPlatform'],
      rating: (json['rating'] as num?)?.toDouble(),
      ratingCount: json['ratingCount'],
      genres: List<String>.from(json['genres'] ?? const []),
      maxPlayers: json['maxPlayers'],
      cooperative: json['cooperative'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'boxart': boxart,
      if (releaseDate != null) 'releaseDate': releaseDate,
      if (popularity != null) 'popularity': popularity,
      if (launchboxId != null) 'launchboxId': launchboxId,
      if (launchboxPlatform != null) 'launchboxPlatform': launchboxPlatform,
      if (rating != null) 'rating': rating,
      if (ratingCount != null) 'ratingCount': ratingCount,
      if (genres.isNotEmpty) 'genres': genres,
      if (maxPlayers != null) 'maxPlayers': maxPlayers,
      if (cooperative != null) 'cooperative': cooperative,
    };
  }

  GameDetails copyWith({
    String? boxart,
    int? releaseDate,
    int? popularity,
    int? launchboxId,
    String? launchboxPlatform,
    double? rating,
    int? ratingCount,
    List<String>? genres,
    int? maxPlayers,
    bool? cooperative,
  }) {
    return GameDetails(
      boxart: boxart ?? this.boxart,
      releaseDate: releaseDate ?? this.releaseDate,
      popularity: popularity ?? this.popularity,
      launchboxId: launchboxId ?? this.launchboxId,
      launchboxPlatform: launchboxPlatform ?? this.launchboxPlatform,
      rating: rating ?? this.rating,
      ratingCount: ratingCount ?? this.ratingCount,
      genres: genres ?? this.genres,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      cooperative: cooperative ?? this.cooperative,
    );
  }
}
