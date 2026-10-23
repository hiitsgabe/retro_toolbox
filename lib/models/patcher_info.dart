// Dart mirrors of the retro_roster_patcher JSON payloads. Parsing is defensive
// (missing keys tolerated) because the library is the source of truth for shape
// and evolves independently.

class PatcherInfo {
  final String gameId;
  final String platform;
  final String sport;
  final bool requiresSlotMapping;
  final List<String> providers;

  /// In-game text languages the patch can apply (codes like `en`); empty when
  /// the game has no translation choice.
  final List<String> languages;

  /// The patch can draw each team's logo into the game's flag slots.
  final bool supportsLogos;

  /// The patch can empty the team slots the league leaves unused.
  final bool supportsBlankUnused;

  /// Screen art slots (`title`, `menu`, ...) whose image the patch can replace.
  final List<String> imageSlots;

  /// The patch draws each team's home and away kit (from its colours, a
  /// pattern, one of the game's designs or a PNG).
  final bool supportsKits;

  /// The game ships jersey designs a kit can reuse (previewed from the ROM).
  final bool kitTemplates;

  /// The patch can update the national sides too.
  final bool supportsNationals;
  final int? nationalSlotBase;

  /// Team-slot groups the game splits its clubs into; empty when it has none.
  final List<SlotGroup> slotGroups;

  /// How many leagues one patch takes, the k-th filling slot group k. 1 when
  /// the groups only describe the slots (WE2002): a second league would
  /// overwrite the next group.
  final int maxLeagues;

  const PatcherInfo({
    required this.gameId,
    required this.platform,
    required this.sport,
    required this.requiresSlotMapping,
    required this.providers,
    this.languages = const [],
    this.supportsLogos = false,
    this.supportsBlankUnused = false,
    this.imageSlots = const [],
    this.supportsKits = false,
    this.kitTemplates = false,
    this.supportsNationals = false,
    this.nationalSlotBase,
    this.slotGroups = const [],
    this.maxLeagues = 1,
  });

  /// Whether the wizard has a visuals step to show for this game.
  bool get hasVisuals => supportsLogos || supportsBlankUnused || imageSlots.isNotEmpty;

  /// One league per slot group: the wizard fetches several leagues.
  bool get multiLeague => leagueCap > 1;

  /// Leagues the wizard lets the user tick: one per slot group, at most
  /// [maxLeagues].
  int get leagueCap => maxLeagues < slotGroups.length ? maxLeagues : slotGroups.length;

  factory PatcherInfo.fromJson(Map<String, dynamic> j) => PatcherInfo(
        gameId: (j['game_id'] ?? '') as String,
        platform: (j['platform'] ?? '') as String,
        sport: (j['sport'] ?? '') as String,
        requiresSlotMapping: (j['requires_slot_mapping'] ?? false) as bool,
        providers: ((j['providers'] as List?) ?? const []).map((e) => '$e').toList(),
        languages: ((j['languages'] as List?) ?? const []).map((e) => '$e').toList(),
        supportsLogos: (j['supports_logos'] ?? false) as bool,
        supportsBlankUnused: (j['supports_blank_unused'] ?? false) as bool,
        imageSlots: ((j['image_slots'] as List?) ?? const []).map((e) => '$e').toList(),
        supportsKits: (j['supports_kits'] ?? false) as bool,
        kitTemplates: (j['kit_templates'] ?? false) as bool,
        supportsNationals: (j['supports_nationals'] ?? false) as bool,
        nationalSlotBase: (j['national_slot_base'] as num?)?.toInt(),
        slotGroups: [
          for (final g in ((j['slot_groups'] as List?) ?? const [])) SlotGroup.fromJson(Map<String, dynamic>.from(g as Map)),
        ],
        maxLeagues: ((j['max_leagues'] ?? 1) as num).toInt(),
      );

  String get defaultProvider => providers.isNotEmpty ? providers.first : '';
}

/// A run of team slots one league fills: [count] slots from [first].
class SlotGroup {
  final String name;
  final int first;
  final int count;
  const SlotGroup(this.name, this.first, this.count);

  factory SlotGroup.fromJson(Map<String, dynamic> j) => SlotGroup('${j['name'] ?? ''}', ((j['first'] ?? 0) as num).toInt(), ((j['count'] ?? 0) as num).toInt());
}

/// One of the game's own jersey designs, previewed from the ROM.
class KitTemplate {
  final int index;
  final String name;
  final String path;
  const KitTemplate({required this.index, required this.name, required this.path});

  factory KitTemplate.fromJson(Map<String, dynamic> j) => KitTemplate(
        index: ((j['index'] ?? 0) as num).toInt(),
        name: '${j['name'] ?? ''}',
        path: '${j['path'] ?? ''}',
      );
}

const _languageNames = {'en': 'English', 'es': 'Español', 'fr': 'Français', 'pt': 'Português'};

/// Display name for a patch language code; the upper-cased code when unknown.
String languageName(String code) => _languageNames[code] ?? code.toUpperCase();

const _slotNames = {
  'title': ('Title screen', 'The logo and ball on the title screen.'),
  'menu': ('Main menu', 'The ball, banner and year beside the main menu.'),
  'boot': ('Boot screens', 'The publisher and licence screens shown at start-up.'),
  'loading': ('Loading screen', 'Shown while a match loads.'),
  'match': ('Match screen', 'Behind the match menus.'),
};

/// Per-game wording where a slot shows something else than in WE2002/PES.
const _gameSlotNames = {
  'iss-snes': {
    'konami': ('Konami screen', 'The logo screen at boot; a line sweeps it in from the top.'),
    'title': ('Title screen', 'Behind the ISS logo, PRESS START, the two players and the copyright lines.'),
    'menu': ('Menu wallpaper', 'A pattern the menus scroll: it repeats both ways, so match its edges.'),
  },
  'nhl07-psp': {
    'boot': ('Boot screen', 'The splash before the autosave prompt; the game draws its loading bar over it.'),
    'title': ('Title screen', 'Behind PRESS START; the game writes its own lines in the bottom quarter.'),
    'menu': ('Menu backdrop', 'Under every menu and the legal screen; keep the middle light, the game writes navy text there.'),
    'logo': ('Game logo', 'The logo above the main menu, on transparency.'),
    'player': ('Menu player', 'Beside the main menu, on transparency; the top 272 rows show.'),
    'loading': ('Loading screens', 'All eight screens shown while a game loads.'),
    'league_badge': ('League badge', 'Where the NHL shield shows on the legal and title screens.'),
    'players_badge': ('Players badge', 'Where the NHLPA logo shows on the legal and title screens.'),
  },
  'nhl94-snes': {
    'boot': ('Boot screen', 'The EA SPORTS screen at power-on, held still about 12 seconds.'),
    'title': ('Title screen', 'The whole title; the credits and the NHL and NHLPA shields sit over the bottom.'),
    'menu': ('Menu wallpaper', 'Behind every menu and pause screen; keep the logo boxes plain and the lower part dark.'),
  },
  'kgj-mlb-snes': {
    'boot': ('Boot screen', 'The licence screen at power-on, faded in and out.'),
    'title': ('Stadium', 'Behind the title and the menus; the logo, Griffey, PUSH START and the menu box sit over most of it.'),
  },
};

/// Display name and one-line description of a screen art slot, worded for
/// [gameId] when that game has its own.
(String, String) imageSlotLabel(String slot, [String? gameId]) =>
    _gameSlotNames[gameId]?[slot] ??
    _slotNames[slot] ??
    ('${slot[0].toUpperCase()}${slot.substring(1).replaceAll('_', ' ')}', 'Screen art the patch can replace.');

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

  /// Per slot, the (goalies, forwards, defencemen) the image keeps (NHL '94);
  /// empty when the game does not say.
  final List<List<int>> rosterCounts;

  /// The slot each asked team code lands in, for games that slot by code.
  final Map<String, int> teamSlots;
  const RomInfo({required this.isValid, required this.slots, this.rosterCounts = const [], this.teamSlots = const {}});

  factory RomInfo.fromJson(Map<String, dynamic> j) => RomInfo(
        isValid: (j['is_valid'] ?? false) as bool,
        slots: ((j['slots'] as List?) ?? const []).map((e) => RomSlot.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        rosterCounts: [
          for (final row in (((j['extra'] as Map?)?['roster_counts'] as List?) ?? const []))
            [for (final n in row as List) (n as num).toInt()],
        ],
        teamSlots: {for (final e in ((j['team_slots'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
      );

  /// The (goalies, forwards, defencemen) of the slot team [code] lands in, or null.
  List<int>? countsFor(String code) {
    final slot = teamSlots[code];
    return slot != null && slot < rosterCounts.length ? rosterCounts[slot] : null;
  }
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

  /// What mapping said, e.g. a team it left out and why.
  final List<String> notes;
  const PatchResult({
    required this.outputPath,
    required this.teamsPatched,
    required this.playersPatched,
    this.notes = const [],
  });

  factory PatchResult.fromJson(Map<String, dynamic> j) => PatchResult(
        outputPath: (j['output_path'] ?? '') as String,
        teamsPatched: (j['teams_patched'] ?? 0) as int,
        playersPatched: (j['players_patched'] ?? 0) as int,
        notes: [for (final n in (j['notes'] as List?) ?? const []) '$n'],
      );
}

/// One ROM-slot → real-team binding for games that require manual mapping.
class SlotMapping {
  final int slotIndex;
  final int teamId;
  final String teamName;
  const SlotMapping({required this.slotIndex, required this.teamId, this.teamName = ''});

  Map<String, dynamic> toJson() => {'slot_index': slotIndex, 'team_id': teamId, 'team_name': teamName};
}
