import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';

/// Art (logo + color + icon) for sport and game cards.
///
/// Everything keys off the library's non-identifying fields (`sport`,
/// `platform`) — no game titles live in the app. Bundled logos are named by
/// those fields: `assets/sport_art/<sport>.svg` for a sport card,
/// `assets/sport_art/<sport>_<platform>.svg` for a game card. A name is only
/// returned once its file is registered below, so a missing SVG can never crash
/// the SVG renderer (which has no error fallback) — the tile shows [sportIcon].

/// Sport-level logos present under assets/sport_art/ (add the slug when you drop
/// the file in).
const Set<String> _bundledSportLogos = {};

/// Game-level logos present under assets/sport_art/, named `<sport>_<platform>`.
const Set<String> _bundledGameLogos = {};

String? sportLogoAsset(String sport) {
  final slug = sport.toLowerCase();
  if (!_bundledSportLogos.contains(slug)) return null;
  return 'assets/sport_art/$slug.svg';
}

String? gameLogoAsset(PatcherInfo info) {
  // ponytail: sport+platform is unique across the current 9 games; if the
  // library ever ships two games with the same sport+platform, add a
  // disambiguating field to this key.
  final slug = '${info.sport}_${info.platform}'.toLowerCase();
  if (!_bundledGameLogos.contains(slug)) return null;
  return 'assets/sport_art/$slug.svg';
}

/// Human-readable game name for a card/header. The library only exposes
/// game_id/sport/platform, so the display names live here in the UI layer.
String gameName(PatcherInfo info) => gameDisplayName(info.gameId);

/// The display name of a game by its id (what messages and titles call it).
String gameDisplayName(String gameId) => _gameNames[gameId] ?? gameId;

const Map<String, String> _gameNames = {
  'iss-snes': 'International Superstar Soccer',
  'iss2000-n64': 'International Superstar Soccer 2000',
  'we2002': 'Winning Eleven 2002',
  'nbalive95-genesis': 'NBA Live 95',
  'nhl94-genesis': 'NHL 94',
  'nhl94-snes': 'NHL 94',
  'nhl05-ps2': 'NHL 05',
  'nhl07-psp': 'NHL 07',
  'kgj-mlb-snes': 'Ken Griffey Jr. Presents MLB',
  'mvp-psp': 'MVP Baseball',
  'pes2013-ps2': 'PES 2013',
};

/// Pretty console name for a platform slug.
String platformLabel(String platform) => _platformLabels[platform.toLowerCase()] ?? platform.toUpperCase();

const Map<String, String> _platformLabels = {
  'genesis': 'Genesis',
  'snes': 'SNES',
  'ps2': 'PS2',
  'psp': 'PSP',
  'psx': 'PS1',
  'n64': 'N64',
};

/// Per-game ROM roster structure, read from the retro_roster_patcher game code
/// (each game's PLAYERS_PER_TEAM and the players it puts in the game's lineup).
/// [rosterSize] is how many players the ROM stores per team; players beyond it
/// are ignored on patch. [starters] is the starting lineup; the rest are bench.
/// A team's own `extra["lineup_size"]` overrides [starters] (KGJ: 8 for NL clubs).
class GameRoster {
  final int rosterSize;
  final int starters;
  const GameRoster(this.rosterSize, this.starters);
}

GameRoster gameRoster(String gameId) => _gameRosters[gameId] ?? const GameRoster(20, 11);

/// WE2002 slots 0-31 are Master League clubs as well as national teams: the
/// Master League keeps the first 14 (slots 0-17) or 15 (18-31) of the 23.
/// Null for any other game or slot.
int? masterLeagueSize(String gameId, int? slot) =>
    gameId != 'we2002' || slot == null || slot >= 32 ? null : (slot < 18 ? 14 : 15);

const Map<String, GameRoster> _gameRosters = {
  'iss-snes': GameRoster(15, 11), // 11 start, 4 subs; slot 0 is the keeper
  'iss2000-n64': GameRoster(22, 11), // 11 start in formation order, 11 subs; slot 0 is the keeper
  'we2002': GameRoster(23, 11), // national squads hold 23; Master League keeps 14 or 15
  'nbalive95-genesis': GameRoster(12, 5),
  'kgj-mlb-snes': GameRoster(25, 9), // 25 roster, 9 batting lineup
  'mvp-psp': GameRoster(25, 9),
  // Hockey starts six: a goalie, a forward line and a defence pair.
  'nhl94-genesis': GameRoster(23, 6),
  'nhl94-snes': GameRoster(23, 6),
  'nhl05-ps2': GameRoster(25, 6),
  'nhl07-psp': GameRoster(25, 6),
  'pes2013-ps2': GameRoster(32, 11),
};

/// Why the game will not start the first [starters] of [positions] (the squad's
/// positions in list order) as listed: one sentence per problem, none when it will.
List<String> lineupWarnings(String gameId, List<String> positions, int starters) {
  final n = positions.length;
  final top = positions.take(starters);
  int count(String pos) => top.where((p) => p == pos).length;
  final full = n >= starters;
  // Baseball pitchers never bat in the lineup, so count only the rest.
  final batters = positions.where((p) => !isPitcher(p)).length;
  return [
    if (!full && gameId == 'we2002')
      "Only $n players: blank 'PLAYER' records with no abilities fill the other ${starters - n} starting places."
    else if (!full && !gameSplitsPitchers(gameId))
      "Only $n players: the game's old players fill the other ${starters - n} starting places.",
    if (gameId == 'kgj-mlb-snes' && batters < starters)
      "Only $batters position players: pitchers past the first $pitchersStored, then the game's old players, "
          'fill the other ${starters - batters} lineup places.',
    if (gameId == 'mvp-psp' && batters < starters) 'Only $batters position players: the batting order is ${starters - batters} short.',
    if ((gameId == 'iss-snes' || gameId == 'iss2000-n64' || gameId == 'we2002') && n > 0 && positions.first != 'Goalkeeper')
      'The game puts the first player in goal: move a goalkeeper to the top.',
    if (gameId == 'pes2013-ps2' && full && count('Goalkeeper') != 1)
      'The game plays exactly one goalkeeper: keep one, and only one, in the first $starters.',
    if ((gameId == 'nhl05-ps2' || gameId == 'nhl07-psp') &&
        full &&
        !(count('G') == 1 && count('C') == 1 && count('LW') == 1 && count('RW') == 1 && count('D') == 2))
      'The game starts the first G, C, LW, RW and two D in the list: make the first $starters exactly those.',
    // Genesis is left out until a Genesis cartridge confirms its line table.
    if (gameId == 'nhl94-snes' &&
        full &&
        // NHL 94 plays anyone but a G or D as a forward.
        !(count('G') == 1 && count('D') == 2 && top.where((p) => p != 'G' && p != 'D').length == 3))
      'The game starts the first G, three forwards and two D in the list: make the first $starters exactly those.',
    if (gameId == 'nhl94-genesis' && n > 0 && positions.where((p) => p == 'G').length < 2) 'NHL 94 needs two goalies: add one, or the patch stops.',
    if (gameId == 'nhl94-snes' && n > 0 && positions.where((p) => p == 'G').length < 2)
      "NHL 94 needs two goalies: add one, or the slot keeps the cartridge's team.",
  ];
}

/// Things true of the game's lineup that the order alone does not show.
List<String> lineupNotes(String gameId) => [
      if (gameId == 'nhl94-genesis') 'Not yet checked on a Genesis cartridge: the game may not start the first six as listed.',
      if (gameId == 'mvp-psp') 'At NL parks the DH sits, the hitters behind him move up, and the first starting pitcher bats ninth.',
      if (gameId == 'kgj-mlb-snes') 'The lineup bats in this order. NL clubs bat eight, and their pitcher bats ninth.',
    ];

/// What the Look step's Team logos switch draws, in [gameId]'s own terms.
String logosNote(String gameId) => '${switch (gameId) {
      'nhl94-snes' => "Draw each team's logo in the menus and at center ice, and on the title pucks while the cartridge's title stays.",
      'kgj-mlb-snes' => "Draw each club's logo on team select, Today's Game and the season screens.",
      _ => "Draw each team's logo as its in-game flag.",
    }} Tap a crest on the Teams step to use your own PNG.';

/// What the editor calls the players who start: baseball's lineup is also the
/// order they bat in.
String startersLabel(String gameId) => gameId == 'kgj-mlb-snes' ? 'Batting order' : 'Starting lineup';

/// NHL 94 keeps up to [counts] (goalies, forwards, defencemen; 2, 14 and 7
/// when the slot's own are unknown), each taken in list order wherever they
/// sit: the rows of [positions] the game stores.
Set<int> nhl94StoredRows(List<String> positions, [List<int>? counts]) {
  final c = counts != null && counts.length == 3 ? counts : const [2, 14, 7];
  final caps = {'G': c[0], 'F': c[1], 'D': c[2]};
  final taken = {'G': 0, 'F': 0, 'D': 0};
  final kept = <int>{};
  for (final (i, p) in positions.indexed) {
    final group = p == 'G' || p == 'D' ? p : 'F';
    taken[group] = taken[group]! + 1;
    if (taken[group]! <= caps[group]!) kept.add(i);
  }
  return kept;
}

bool gameStoresByPosition(String gameId) => gameId == 'nhl94-genesis' || gameId == 'nhl94-snes';

/// Baseball games write up to 15 non-pitchers (lineup, then bench) and then up
/// to 10 pitchers (five starters, then the bullpen), so up to 25 are stored.
/// Leftovers fill a short block: KGJ bats spare pitchers on the bench and
/// pitches spare batters in relief; MVP benches spare batters and puts spare
/// pitchers in long relief.
bool gameSplitsPitchers(String gameId) => gameId == 'kgj-mlb-snes' || gameId == 'mvp-psp';

/// The section a baseball game puts its leftover players in, by the first
/// leftover's role.
String leftoverSection(String gameId, {required bool pitcher}) => gameId == 'kgj-mlb-snes'
    ? (pitcher ? 'Bench (bats)' : 'Bullpen (pitches)')
    : (pitcher ? 'Bullpen (long relief)' : 'Bench');
const battersStored = 15, pitchersStored = 10, rotationSize = 5;

/// The position strings both baseball patchers read as a pitcher.
bool isPitcher(String position) => const {'P', 'SP', 'RP', 'CL', 'CP'}.contains(position.toUpperCase());

/// [players] in the order a baseball game writes them: the first 15
/// non-pitchers, the first 10 pitchers, then everyone else as listed.
List<RosterPlayer> splitPitchers(List<RosterPlayer> players) {
  final batters = players.where((p) => !isPitcher(p.position)).take(battersStored);
  final pitchers = players.where((p) => isPitcher(p.position)).take(pitchersStored);
  final kept = Set<RosterPlayer>.identity()..addAll(batters)..addAll(pitchers);
  return [...batters, ...pitchers, ...players.where((p) => !kept.contains(p))];
}

/// ESPN athlete headshot URL, built from the player's ESPN id and sport. The
/// library leaves photo_url empty, but ESPN serves headshots at a stable path.
/// Returns null for players with no ESPN id (e.g. user-added) or unknown sport.
String? espnHeadshot(int playerId, String sport) {
  if (playerId <= 0) return null;
  final slug = const {'soccer': 'soccer', 'hockey': 'nhl', 'baseball': 'mlb', 'basketball': 'nba'}[sport.toLowerCase()];
  if (slug == null) return null;
  return 'https://a.espncdn.com/i/headshots/$slug/players/full/$playerId.png';
}

/// Catalog search terms per game — the titles a ROM listing actually uses
/// (often the Japanese/original name), mirrored from console_utilities so the
/// library lookup finds the game. Falls back to the display name.
List<String> gameSearchTerms(String gameId) => _searchTerms[gameId] ?? [_gameNames[gameId] ?? gameId];

const Map<String, List<String>> _searchTerms = {
  'iss-snes': ['International Superstar Soccer'],
  'iss2000-n64': ['International Superstar Soccer 2000', 'ISS 2000'],
  'we2002': ['World Soccer Winning Eleven 2002', 'Winning Eleven 2002'],
  'nbalive95-genesis': ['NBA Live 95'],
  'nhl94-genesis': ["NHL '94", "NHL Hockey '94", 'NHL 94'],
  'nhl94-snes': ["NHL '94", "NHL Hockey '94", 'NHL 94'],
  'nhl05-ps2': ['NHL 2005', 'NHL 05'],
  'nhl07-psp': ['NHL 07', 'NHL 2007'],
  'kgj-mlb-snes': ['Ken Griffey Jr. Presents Major League Baseball'],
  'mvp-psp': ['MVP Baseball'],
  'pes2013-ps2': ['pro evolution soccer 2013', 'pes 2013', 'world soccer winning eleven 2013'],
};

/// File extensions the patcher takes for a game, best first: the order ranks
/// several local files of the same game (a .cue over its .bin, an extracted
/// image over the archive it came from). A .zip is unpacked by the worker.
List<String> gameRomExtensions(String gameId) => _romExtensions[gameId] ?? const ['.iso', '.bin', '.zip'];

const Map<String, List<String>> _romExtensions = {
  'iss-snes': ['.sfc', '.smc', '.zip'],
  'iss2000-n64': ['.z64', '.v64', '.n64', '.zip'],
  'nhl94-snes': ['.sfc', '.smc', '.zip'],
  'kgj-mlb-snes': ['.sfc', '.smc', '.zip'],
  'we2002': ['.cue', '.iso', '.bin', '.zip'],
  'nbalive95-genesis': ['.md', '.gen', '.bin', '.zip'],
  'nhl94-genesis': ['.md', '.gen', '.bin', '.zip'],
  'nhl05-ps2': ['.iso', '.zip'],
  'pes2013-ps2': ['.iso', '.zip'],
  // Not .cso: both PSP patchers refuse a compressed image by name.
  'nhl07-psp': ['.iso', '.zip'],
  'mvp-psp': ['.iso', '.zip'],
};

/// Preferred ROM region per game, used to break ties between matches (e.g.
/// prefer "(USA)" over "(Korea)"). Winning Eleven only works with the Japanese
/// release; everything else defaults to USA.
String gamePreferredRegion(String gameId) => gameId == 'we2002' ? 'Japan' : 'USA';

/// What ROM the wizard expects for a game — file type, format and notes. Shown
/// on the Select ROM step so the user picks the right dump.
String romExpectation(String gameId) => _romExpectations[gameId] ??
    'Provide the original game ROM/disc image for this platform.';

const Map<String, String> _romExpectations = {
  'iss-snes':
      'International Superstar Soccer (SNES). A .sfc or .smc file (USA or Japan). '
      'A 512-byte copier header is handled automatically; no specific revision is required.',
  'iss2000-n64':
      'International Superstar Soccer 2000 (N64, USA). A .z64, .v64 or .n64 file. '
      'The patched ROM grows to 20 MB, which emulators and flash carts load.',
  'we2002':
      'Winning Eleven 2002 (PS1). The disc image: a .bin (with its .cue) or a single .iso. '
      'Use your own dump of the original disc.',
  'nbalive95-genesis':
      'NBA Live 95 (Mega Drive / Genesis). A .bin, .md or .gen file. '
      'Other revisions of the same game work; NBA Live 96 is rejected.',
  'nhl94-genesis':
      'NHL 94 (Mega Drive / Genesis). A .bin, .md or .gen file. The header checksum is fixed up automatically.',
  'nhl94-snes':
      'NHL 94 (SNES). A .sfc or .smc file. A 512-byte copier header is handled automatically.',
  'nhl05-ps2':
      'NHL 2005 (PlayStation 2). A .iso disc image (a .zip of it also works). Use your own dump.',
  'nhl07-psp':
      'NHL 07 (PSP). A .iso or .cso disc image. Use your own dump.',
  'kgj-mlb-snes':
      'Ken Griffey Jr. Presents MLB (SNES). A .sfc or .smc file. '
      'A 512-byte copier header is handled automatically.',
  'mvp-psp':
      'MVP Baseball (PSP). A .iso or .cso disc image (USA). Use your own dump.',
  'pes2013-ps2':
      'A PlayStation 2 disc image (.iso) of Pro Evolution Soccer 2013 (USA, SLUS-21955). Zips are fine.',
};

/// Games whose ROM stores per-team colors (soccer kits, MVP uniforms), so the
/// editor should let the user set them. Read from the game code's color usage.
bool gameUsesTeamColor(String gameId) => const {'iss-snes', 'we2002', 'mvp-psp', 'pes2013-ps2'}.contains(gameId);

/// Which providers expose a selectable season. ESPN only serves the current
/// year, so only the NHL source lets the user pick a season.
bool providerHasSeason(String provider) => provider == 'nhl';

/// The season to start on. Hockey seasons run October to June and are named by
/// their start year, so before October the current one began last year. Other
/// sources are fixed to the calendar year.
int defaultSeason(String provider, [DateTime? now]) {
  now ??= DateTime.now();
  return providerHasSeason(provider) && now.month < 10 ? now.year - 1 : now.year;
}

Color sportBrandColor(String sport) =>
    _sportColors[sport.toLowerCase()] ?? const Color(0xFF55606E);

IconData sportIcon(String sport) => _sportIcons[sport.toLowerCase()] ?? Icons.sports;

const Map<String, Color> _sportColors = {
  'soccer': Color(0xFF2E9E4F),
  'basketball': Color(0xFFE56717),
  'hockey': Color(0xFF2E6DB4),
  'baseball': Color(0xFFC0392B),
};

const Map<String, IconData> _sportIcons = {
  'soccer': Icons.sports_soccer,
  'basketball': Icons.sports_basketball,
  'hockey': Icons.sports_hockey,
  'baseball': Icons.sports_baseball,
};
