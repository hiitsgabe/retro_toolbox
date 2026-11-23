/// Console slug rules with no Flutter in them, so tools run under plain
/// `dart run` can use them (the launch preset check is one). The art, logo and
/// color helpers stay in widgets/menu_grid/console_slug.dart, which re-exports
/// this file.
library;

/// Art slugs whose Batocera system id differs; every other slug is its id.
const Map<String, String> _batoceraBySlug = {
  'genesis': 'megadrive',
  'atarilynx': 'lynx',
  'atarijaguar': 'jaguar',
  'wonderswan': 'wswan',
  'amiga': 'amiga500',
  'arcade': 'mame',
};

/// Batocera system id for free text (a console's id and name), by keyword.
String? batoceraPlatformForText(String text) {
  final slug = consoleArtSlugForText(text);
  return slug == null ? null : _batoceraBySlug[slug] ?? slug;
}

/// Art slug for a platform id (Batocera, or any text the keywords know).
String? slugForPlatform(String platform) {
  for (final e in _batoceraBySlug.entries) {
    if (e.value == platform) return e.key;
  }
  if (_rules.any((r) => r.key == platform)) return platform;
  return consoleArtSlugForText(platform);
}

/// The keyword match behind consoleArtSlug, on any text (e.g. a game's
/// platform string like "psx"), so the Sports menu can reuse console art.
String? consoleArtSlugForText(String text) {
  final hay = text.toLowerCase();
  for (final entry in _rules) {
    for (final kw in entry.value) {
      if (hay.contains(kw)) return entry.key;
    }
  }
  return null;
}

/// (slug, keywords). Includes platforms we have no logo for yet: they still
/// resolve to the right brand color and avoid mismatching a sibling's logo.
const List<MapEntry<String, List<String>>> _rules = [
  MapEntry('gba', ['game boy advance', 'gameboy advance', 'gba']),
  MapEntry('gbc', ['game boy color', 'gameboy color', 'gbc']),
  MapEntry('gb', ['game boy', 'gameboy']),
  MapEntry('virtualboy', ['virtual boy', 'virtualboy']),
  MapEntry('n64', ['nintendo 64', 'n64']),
  MapEntry('gamecube', ['gamecube', 'game cube', 'gcn', 'ngc']),
  MapEntry('wiiu', ['wii u', 'wiiu']),
  MapEntry('wii', ['wii']),
  MapEntry('3ds', ['nintendo 3ds', '3ds']),
  MapEntry('nds', ['nintendo ds', 'nds']),
  MapEntry('switch2', ['switch 2', 'switch2']),
  MapEntry('switch', ['switch', 'nsw']),
  // Before nes: "genesis" contains "nes".
  MapEntry('sega32x', ['32x']),
  MapEntry('segacd', ['sega cd', 'mega cd', 'segacd']),
  MapEntry('genesis', ['mega drive', 'megadrive', 'genesis']),
  MapEntry('snes', ['super nintendo', 'super famicom', 'super nes', 'snes', 'sfc']),
  MapEntry('nes', ['famicom', 'nintendo entertainment', 'nes']),
  MapEntry('mastersystem', ['master system', 'sega master', 'mastersystem', 'sms']),
  MapEntry('gamegear', ['game gear', 'gamegear']),
  MapEntry('sg1000', ['sg-1000', 'sg1000']),
  MapEntry('saturn', ['saturn']),
  MapEntry('dreamcast', ['dreamcast']),
  MapEntry('ps5', ['playstation 5', 'ps5']),
  MapEntry('ps4', ['playstation 4', 'ps4']),
  MapEntry('ps3', ['playstation 3', 'ps3']),
  MapEntry('ps2', ['playstation 2', 'ps2']),
  MapEntry('psp', ['playstation portable', 'psp']),
  MapEntry('psx', ['playstation', 'psx', 'ps1', 'psone']),
  MapEntry('xboxseries', ['xbox series', 'xboxseries', 'series x', 'series s']),
  MapEntry('xboxone', ['xbox one', 'xboxone']),
  MapEntry('xbox360', ['xbox 360', 'xbox360', 'x360']),
  MapEntry('xbox', ['xbox']),
  MapEntry('ngp', ['neo geo pocket', 'ngp']),
  MapEntry('neogeo', ['neo geo', 'neogeo']),
  MapEntry('pcengine', ['pc engine', 'pcengine', 'turbografx', 'turbo grafx', 'tg16', 'tg-16']),
  MapEntry('atari2600', ['atari 2600', '2600']),
  MapEntry('atari7800', ['atari 7800', '7800']),
  MapEntry('atarilynx', ['lynx']),
  MapEntry('atarijaguar', ['jaguar']),
  MapEntry('3do', ['3do']),
  MapEntry('colecovision', ['coleco']),
  MapEntry('intellivision', ['intellivision']),
  MapEntry('msx', ['msx']),
  MapEntry('c64', ['commodore 64', 'c64']),
  MapEntry('amiga', ['amiga']),
  MapEntry('wonderswan', ['wonderswan', 'wonder swan', 'wswan']),
  MapEntry('arcade', ['arcade', 'mame', 'fbneo', 'fba']),
];

/// Every slug the keyword rules can produce. A launch preset may only name
/// these as systems.
final Set<String> knownConsoleSlugs = {for (final r in _rules) r.key};
