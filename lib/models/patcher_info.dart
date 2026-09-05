// Dart mirrors of the retro_roster_patcher JSON payloads. Parsing is defensive
// (missing keys tolerated) because the library is the source of truth for shape
// and evolves independently.

class PatcherInfo {
  final String gameId;
  final String platform;
  final String sport;
  final bool requiresSlotMapping;
  final List<String> providers;

  const PatcherInfo({
    required this.gameId,
    required this.platform,
    required this.sport,
    required this.requiresSlotMapping,
    required this.providers,
  });

  factory PatcherInfo.fromJson(Map<String, dynamic> j) => PatcherInfo(
        gameId: (j['game_id'] ?? '') as String,
        platform: (j['platform'] ?? '') as String,
        sport: (j['sport'] ?? '') as String,
        requiresSlotMapping: (j['requires_slot_mapping'] ?? false) as bool,
        providers: ((j['providers'] as List?) ?? const []).map((e) => '$e').toList(),
      );

  String get defaultProvider => providers.isNotEmpty ? providers.first : '';
}

/// A selectable soccer league. Built-in leagues come from the library; custom
/// ones come from the user's JSON file and carry an ESPN [code] so the worker
/// can register them before fetch.
class League {
  final int id;
  final String name;
  final String country;
  final String? code;
  const League({required this.id, required this.name, this.country = '', this.code});

  factory League.fromJson(Map<String, dynamic> j) => League(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '${j['id']}') as String,
        country: (j['country'] ?? '') as String,
        code: j['code'] as String?,
      );

  /// Payload for the fetch job. Includes [code] only for custom leagues.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'country': country,
        if (code != null) 'code': code,
      };

  String get label => country.isEmpty ? name : '$name · $country';
}

class RomSlot {
  final int index;
  final String displayName;
  const RomSlot({required this.index, required this.displayName});

  factory RomSlot.fromJson(Map<String, dynamic> j) => RomSlot(
        index: (j['index'] ?? 0) as int,
        displayName: ((j['display_name'] ?? j['current_name'] ?? '') as String),
      );
}

class RomInfo {
  final bool isValid;
  final List<RomSlot> slots;
  const RomInfo({required this.isValid, required this.slots});

  factory RomInfo.fromJson(Map<String, dynamic> j) => RomInfo(
        isValid: (j['is_valid'] ?? false) as bool,
        slots: ((j['slots'] as List?) ?? const [])
            .map((e) => RomSlot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class LeagueTeam {
  final int id;
  final String name;
  final int playerCount;
  const LeagueTeam({required this.id, required this.name, required this.playerCount});
}

class LeagueData {
  final String leagueName;
  final int season;
  final List<LeagueTeam> teams;
  const LeagueData({required this.leagueName, required this.season, required this.teams});

  factory LeagueData.fromJson(Map<String, dynamic> j) {
    final league = (j['league'] as Map?) ?? const {};
    final teams = <LeagueTeam>[];
    for (final raw in ((j['teams'] as List?) ?? const [])) {
      final tr = Map<String, dynamic>.from(raw as Map);
      final team = Map<String, dynamic>.from((tr['team'] as Map?) ?? const {});
      final players = (tr['players'] as List?) ?? const [];
      teams.add(LeagueTeam(
        id: (team['id'] ?? 0) as int,
        name: (team['name'] ?? team['short_name'] ?? 'Team') as String,
        playerCount: players.length,
      ));
    }
    return LeagueData(
      leagueName: (league['name'] ?? 'League') as String,
      season: (league['season'] ?? 0) as int,
      teams: teams,
    );
  }
}

class PatchResult {
  final String outputPath;
  final int teamsPatched;
  final int playersPatched;
  const PatchResult({
    required this.outputPath,
    required this.teamsPatched,
    required this.playersPatched,
  });

  factory PatchResult.fromJson(Map<String, dynamic> j) => PatchResult(
        outputPath: (j['output_path'] ?? '') as String,
        teamsPatched: (j['teams_patched'] ?? 0) as int,
        playersPatched: (j['players_patched'] ?? 0) as int,
      );
}

/// One ROM-slot → real-team binding for games that require manual mapping.
class SlotMapping {
  final int slotIndex;
  final int teamId;
  final String teamName;
  const SlotMapping({required this.slotIndex, required this.teamId, this.teamName = ''});

  Map<String, dynamic> toJson() =>
      {'slot_index': slotIndex, 'team_id': teamId, 'team_name': teamName};
}
