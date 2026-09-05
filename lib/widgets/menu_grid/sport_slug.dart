import 'package:flutter/material.dart';
import 'package:roms_downloader/models/patcher_info.dart';

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
String gameName(PatcherInfo info) => _gameNames[info.gameId] ?? info.gameId;

const Map<String, String> _gameNames = {
  'iss-snes': 'International Superstar Soccer',
  'we2002': 'Winning Eleven 2002',
  'nbalive95-genesis': 'NBA Live 95',
  'nhl94-genesis': 'NHL 94',
  'nhl94-snes': 'NHL 94',
  'nhl05-ps2': 'NHL 05',
  'nhl07-psp': 'NHL 07',
  'kgj-mlb-snes': 'Ken Griffey Jr. Presents MLB',
  'mvp-psp': 'MVP Baseball',
};

/// Pretty console name for a platform slug.
String platformLabel(String platform) => _platformLabels[platform.toLowerCase()] ?? platform.toUpperCase();

const Map<String, String> _platformLabels = {
  'genesis': 'Genesis',
  'snes': 'SNES',
  'ps2': 'PS2',
  'psp': 'PSP',
  'psx': 'PS1',
};

/// Per-game ROM roster structure, read from the retro_roster_patcher game code
/// (each game's PLAYERS_PER_TEAM and its stat_mapper's starting-lineup split).
/// [rosterSize] is how many players the ROM stores per team; players beyond it
/// are ignored on patch. [starters] is the starting lineup; the rest are bench.
class GameRoster {
  final int rosterSize;
  final int starters;
  const GameRoster(this.rosterSize, this.starters);
}

GameRoster gameRoster(String gameId) => _gameRosters[gameId] ?? const GameRoster(20, 11);

const Map<String, GameRoster> _gameRosters = {
  'iss-snes': GameRoster(15, 11), // 4-4-2: 11 start, 4 subs
  'we2002': GameRoster(23, 11), // starting XI first 11
  'nbalive95-genesis': GameRoster(12, 5),
  'kgj-mlb-snes': GameRoster(25, 9), // 25 roster, 9 batting lineup
  'mvp-psp': GameRoster(25, 9),
  'nhl94-genesis': GameRoster(23, 12), // 2G/14F/7D dressed; ~12 top skaters
  'nhl94-snes': GameRoster(23, 12),
  'nhl05-ps2': GameRoster(25, 12),
  'nhl07-psp': GameRoster(25, 12),
};

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
  'we2002': ['World Soccer Winning Eleven 2002', 'Winning Eleven 2002'],
  'nbalive95-genesis': ['NBA Live 95'],
  'nhl94-genesis': ["NHL '94", "NHL Hockey '94", 'NHL 94'],
  'nhl94-snes': ["NHL '94", "NHL Hockey '94", 'NHL 94'],
  'nhl05-ps2': ['NHL 2005', 'NHL 05'],
  'nhl07-psp': ['NHL 07', 'NHL 2007'],
  'kgj-mlb-snes': ['Ken Griffey Jr. Presents Major League Baseball', "Ken Griffey Jr's Winning Run"],
  'mvp-psp': ['MVP Baseball'],
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
};

/// Games whose ROM stores per-team colors (soccer kits, MVP uniforms), so the
/// editor should let the user set them. Read from the game code's color usage.
bool gameUsesTeamColor(String gameId) => const {'iss-snes', 'we2002', 'mvp-psp'}.contains(gameId);

/// Which providers expose a selectable season. ESPN only serves the current
/// year, so only the NHL source lets the user pick a season.
bool providerHasSeason(String provider) => provider == 'nhl';

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
