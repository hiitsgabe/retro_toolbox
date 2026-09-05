// Editable wrapper over the library's league_data JSON (what fetch writes and
// patch reads). Edits mutate the underlying maps so unmodified fields —
// player_stats, provider extras, colors — round-trip untouched back into the
// patch input.

class RosterDoc {
  final Map<String, dynamic> leagueRaw;
  final List<RosterTeam> teams;

  RosterDoc({required this.leagueRaw, required this.teams});

  factory RosterDoc.fromJson(Map<String, dynamic> j) => RosterDoc(
        leagueRaw: Map<String, dynamic>.from((j['league'] as Map?) ?? {}),
        teams: [
          for (final t in ((j['teams'] as List?) ?? const []))
            RosterTeam.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'league': leagueRaw,
        'teams': [for (final t in teams) t.toJson()],
      };

  String get leagueName => (leagueRaw['name'] ?? 'League') as String;

  /// A fresh team id that doesn't collide with an existing one.
  int _nextTeamId() {
    var max = 0;
    for (final t in teams) {
      if (t.id > max) max = t.id;
    }
    return max + 1;
  }

  RosterTeam addTeam(String name) {
    final team = RosterTeam(
      teamRaw: {'id': _nextTeamId(), 'name': name},
      players: [],
      statsRaw: {},
      extraRaw: {},
    );
    teams.add(team);
    return team;
  }

  /// Adds a team from a JSON object. Accepts either the full roster shape
  /// (`{"team": {...}, "players": [...]}`, as fetch produces) or a simple
  /// `{"name": "...", "players": [{"name","position","number"}, ...]}`. Assigns
  /// a fresh team id when the JSON omits one. Throws [FormatException] on a
  /// shape it can't read.
  RosterTeam addTeamFromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> shaped;
    if (j['team'] is Map) {
      shaped = Map<String, dynamic>.from(j);
    } else if (j['name'] != null) {
      shaped = {
        'team': {'id': j['id'], 'name': j['name']},
        'players': j['players'] ?? [],
      };
    } else {
      throw const FormatException('Team JSON needs a "team" object or a "name" field');
    }
    final team = RosterTeam.fromJson(shaped);
    if (team.id == 0) team.teamRaw['id'] = _nextTeamId();
    teams.add(team);
    return team;
  }
}

class RosterTeam {
  final Map<String, dynamic> teamRaw;
  final List<RosterPlayer> players;
  final Map<String, dynamic> statsRaw;
  final Map<String, dynamic> extraRaw;

  RosterTeam({
    required this.teamRaw,
    required this.players,
    required this.statsRaw,
    required this.extraRaw,
  });

  factory RosterTeam.fromJson(Map<String, dynamic> j) => RosterTeam(
        teamRaw: Map<String, dynamic>.from((j['team'] as Map?) ?? {}),
        players: [
          for (final p in ((j['players'] as List?) ?? const []))
            RosterPlayer.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        statsRaw: Map<String, dynamic>.from((j['player_stats'] as Map?) ?? {}),
        extraRaw: Map<String, dynamic>.from((j['extra'] as Map?) ?? {}),
      );

  Map<String, dynamic> toJson() => {
        'team': teamRaw,
        'players': [for (final p in players) p.toJson()],
        'player_stats': statsRaw,
        'loading': false,
        'error': '',
        'extra': extraRaw,
      };

  int get id => (teamRaw['id'] as num?)?.toInt() ?? 0;
  String get name => (teamRaw['name'] ?? '') as String;
  set name(String v) => teamRaw['name'] = v;
  String get logoUrl => (teamRaw['logo_url'] ?? '') as String;

  /// Primary team color as a hex string (e.g. "C60000"), '' if unset.
  String get color => (teamRaw['color'] ?? '') as String;
  set color(String v) => teamRaw['color'] = v;

  /// Secondary/away team color as a hex string, '' if unset.
  String get alternateColor => (teamRaw['alternate_color'] ?? '') as String;
  set alternateColor(String v) => teamRaw['alternate_color'] = v;

  /// This player's editable stats map (PlayerStats fields), or null if none.
  /// player_stats is keyed by the player id as a string in the JSON.
  Map<String, dynamic>? statsFor(int playerId) {
    final s = statsRaw['$playerId'];
    return s is Map ? Map<String, dynamic>.from(s) : null;
  }

  void setStats(int playerId, Map<String, dynamic> stats) => statsRaw['$playerId'] = stats;

  int _nextPlayerId() {
    var max = 0;
    for (final p in players) {
      if (p.id > max) max = p.id;
    }
    return max + 1;
  }

  RosterPlayer addPlayer(String name) {
    final p = RosterPlayer(raw: {'id': _nextPlayerId(), 'name': name});
    players.add(p);
    return p;
  }
}

class RosterPlayer {
  final Map<String, dynamic> raw;
  RosterPlayer({required this.raw});

  factory RosterPlayer.fromJson(Map<String, dynamic> j) => RosterPlayer(raw: j);
  Map<String, dynamic> toJson() => raw;

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  String get name => (raw['name'] ?? '') as String;
  set name(String v) => raw['name'] = v;
  String get position => (raw['position'] ?? '') as String;
  set position(String v) => raw['position'] = v;
  int? get number => (raw['number'] as num?)?.toInt();
  set number(int? v) => raw['number'] = v;
  String get nationality => (raw['nationality'] ?? '') as String;
  String get photoUrl => (raw['photo_url'] ?? '') as String;
}
