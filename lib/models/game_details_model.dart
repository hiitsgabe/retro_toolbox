class GameDetails {
  final String? boxart;
  /// yyyymmdd; an unknown month or day is 00 (a year-only 1999 is 19990000).
  final int? releaseDate;
  final int? popularity;

  const GameDetails({
    this.boxart,
    this.releaseDate,
    this.popularity,
  });

  factory GameDetails.fromJson(Map<String, dynamic> json) {
    return GameDetails(
      boxart: json['boxart'],
      releaseDate: json['releaseDate'],
      popularity: json['popularity'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'boxart': boxart,
      if (releaseDate != null) 'releaseDate': releaseDate,
      if (popularity != null) 'popularity': popularity,
    };
  }

  GameDetails copyWith({
    String? boxart,
    int? releaseDate,
    int? popularity,
  }) {
    return GameDetails(
      boxart: boxart ?? this.boxart,
      releaseDate: releaseDate ?? this.releaseDate,
      popularity: popularity ?? this.popularity,
    );
  }
}
