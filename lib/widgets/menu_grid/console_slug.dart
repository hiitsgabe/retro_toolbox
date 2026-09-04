import 'package:flutter/material.dart';
import 'package:roms_downloader/models/console_model.dart';

/// Canonical platform slug for a catalog [Console], or null when unrecognized.
///
/// The catalog JSON carries no art data — this mapping lives entirely in the
/// app. Matching is keyword-based on the console id + name, so it survives
/// whatever ids a given catalog uses. Order matters: more specific platforms
/// (ps3, wiiu, xbox360, gba) must come before their prefixes (psx, wii, xbox,
/// gb). A slug here is semantic — it drives the brand color even when we have
/// no logo bundled for it (see [_bundledLogos] / [consoleLogoAsset]).
String? consoleArtSlug(Console console) {
  final hay = '${console.id} ${console.name}'.toLowerCase();
  for (final entry in _rules) {
    for (final kw in entry.value) {
      if (hay.contains(kw)) return entry.key;
    }
  }
  return null;
}

/// Bundled logo asset for [console], or null when no logo file exists for its
/// slug. Guards against referencing a missing SVG (which would crash render).
String? consoleLogoAsset(Console console) {
  final slug = consoleArtSlug(console);
  if (slug == null || !_bundledLogos.contains(slug)) return null;
  return 'assets/console_art/${slug}_logo.svg';
}

/// Per-console accent color for the tile gradient, or null for a neutral tile.
Color? consoleBrandColor(Console console) {
  final slug = consoleArtSlug(console);
  if (slug == null) return null;
  return _slugColors[slug];
}

/// (slug, keywords). Includes platforms we have no logo for yet — they still
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
  MapEntry('switch', ['switch', 'nsw']),
  MapEntry('snes', ['super nintendo', 'super famicom', 'super nes', 'snes', 'sfc']),
  MapEntry('nes', ['famicom', 'nintendo entertainment', 'nes']),
  MapEntry('sega32x', ['32x']),
  MapEntry('segacd', ['sega cd', 'mega cd', 'segacd']),
  MapEntry('genesis', ['mega drive', 'megadrive', 'genesis']),
  MapEntry('mastersystem', ['master system', 'sega master', 'mastersystem', 'sms']),
  MapEntry('gamegear', ['game gear', 'gamegear']),
  MapEntry('sg1000', ['sg-1000', 'sg1000']),
  MapEntry('saturn', ['saturn']),
  MapEntry('dreamcast', ['dreamcast']),
  MapEntry('ps4', ['playstation 4', 'ps4']),
  MapEntry('ps3', ['playstation 3', 'ps3']),
  MapEntry('ps2', ['playstation 2', 'ps2']),
  MapEntry('psp', ['playstation portable', 'psp']),
  MapEntry('psx', ['playstation', 'psx', 'ps1', 'psone']),
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
  MapEntry('wonderswan', ['wonderswan', 'wonder swan']),
  MapEntry('arcade', ['arcade', 'mame', 'fbneo', 'fba']),
];

/// Slugs with a bundled `<slug>_logo.svg` under assets/console_art/.
const Set<String> _bundledLogos = {
  'nes', 'snes', 'n64', 'gamecube', 'wii', 'wiiu', 'switch', 'gb', 'gbc', 'gba',
  'nds', '3ds', 'virtualboy', 'genesis', 'mastersystem', 'gamegear', 'saturn',
  'dreamcast', 'segacd', 'sega32x', 'sg1000', 'psx', 'ps2', 'ps3', 'psp', 'xbox',
  'xbox360', 'pcengine', 'neogeo', 'ngp', 'arcade', 'atari2600', 'atari7800',
  'atarilynx', 'atarijaguar', '3do', 'colecovision', 'intellivision', 'msx', 'c64',
  'amiga', 'wonderswan',
};

/// Per-console accent color, keyed by iconic hardware identity (not brand
/// family) — GameCube purple, N64 green, Game Boy blue, Dreamcast orange, etc.
/// Rendered as a darkened gradient behind the logo.
const Map<String, Color> _slugColors = {
  // Nintendo — each console its own identity
  'nes': Color(0xFFC0392B), // classic red
  'snes': Color(0xFF6C4AB6), // purple buttons
  'n64': Color(0xFF2E9E4F), // green
  'gamecube': Color(0xFF5B4B9E), // indigo/purple
  'wii': Color(0xFF1CA9E0), // light blue glow
  'wiiu': Color(0xFF0A6CB6), // deeper blue
  'switch': Color(0xFFE4000F), // neon red
  'gb': Color(0xFF3B6FB5), // blue
  'gbc': Color(0xFFB0479E), // berry
  'gba': Color(0xFF4A56A6), // glacier indigo
  'nds': Color(0xFF5AAEE0), // silver-blue
  '3ds': Color(0xFFD2202E), // red
  'virtualboy': Color(0xFFB0121A), // deep red
  // Sega
  'genesis': Color(0xFF1565C0), // blue
  'mastersystem': Color(0xFFC62828), // red
  'gamegear': Color(0xFF167C80), // teal
  'saturn': Color(0xFF37408C), // deep indigo
  'dreamcast': Color(0xFFE8730F), // swirl orange
  'segacd': Color(0xFF1E5F9E),
  'sega32x': Color(0xFF455A64), // dark grey
  'sg1000': Color(0xFFB0322B),
  // Sony
  'psx': Color(0xFF4666A6),
  'ps2': Color(0xFF123C8C),
  'ps3': Color(0xFF1E4FA0),
  'ps4': Color(0xFF0A5BB0),
  'psp': Color(0xFF2E6DB4),
  // Microsoft
  'xbox': Color(0xFF107C10), // green
  'xbox360': Color(0xFF5DC21E), // lighter green
  // Atari
  'atari2600': Color(0xFFC8102E),
  'atari7800': Color(0xFFA3122A),
  'atarilynx': Color(0xFFE4820B), // amber
  'atarijaguar': Color(0xFFC0392B),
  // Others
  'pcengine': Color(0xFFE56717), // orange
  'neogeo': Color(0xFFC0202A), // red
  'ngp': Color(0xFF2A6FB0), // blue
  'arcade': Color(0xFFC9820A), // amber
  '3do': Color(0xFF555B66), // grey
  'colecovision': Color(0xFFB0322B),
  'intellivision': Color(0xFF8B6D3F), // brown/gold
  'msx': Color(0xFFC0392B),
  'c64': Color(0xFF4A57C4), // C64 blue
  'amiga': Color(0xFFC0392B), // boing red
  'wonderswan': Color(0xFF4A6FA5),
};
