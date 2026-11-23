import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/utils/console_slugs.dart';

export 'package:retro_toolbox/utils/console_slugs.dart';

/// Canonical platform slug for a catalog [Console], or null when unrecognized.
///
/// The catalog JSON carries no art data — this mapping lives entirely in the
/// app. Matching is keyword-based on the console id + name, so it survives
/// whatever ids a given catalog uses. Order matters: more specific platforms
/// (ps3, wiiu, xbox360, gba) must come before their prefixes (psx, wii, xbox,
/// gb). A slug here is semantic — it drives the brand color even when we have
/// no logo bundled for it (see [_bundledLogos] / [consoleLogoAsset]).
String? consoleArtSlug(Console console) {
  final platform = console.resolvedPlatform;
  return platform == null ? null : slugForPlatform(platform);
}

const _switchFormats = {'.nsp', '.nsz', '.xci', '.xcz'};
const _n3dsFormats = {'.3ds', '.cia', '.cci'};

// ponytail: lives beside the keyword rules it falls back on, though services
// import it too; move both to models/ if this grows.
extension ConsolePlatform on Console {
  /// The catalog's platform, else one guessed from the id and name, else from
  /// the file formats (Switch and 3DS only), else null.
  String? get resolvedPlatform {
    if (platform != null && platform!.isNotEmpty) return platform;
    final byName = batoceraPlatformForText('$id $name');
    if (byName != null) return byName;
    final formats = [...?originalFormat, ...?gameFilesFormat].map((e) => e.toLowerCase());
    if (formats.any(_switchFormats.contains)) return 'switch';
    if (formats.any(_n3dsFormats.contains)) return '3ds';
    return null;
  }
}

/// Bundled console logo for a platform string, or null when none is bundled.
String? platformLogoAsset(String platform) {
  final slug = slugForPlatform(platform);
  if (slug == null || !_bundledLogos.contains(slug)) return null;
  return 'assets/console_art/${slug}_logo.svg';
}

/// Brand color for a platform string.
Color? platformBrandColor(String platform) {
  final slug = slugForPlatform(platform);
  return slug == null ? null : _slugColors[slug];
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

/// Slugs with a bundled `<slug>_logo.svg` under assets/console_art/.
const Set<String> _bundledLogos = {
  'nes', 'snes', 'n64', 'gamecube', 'wii', 'wiiu', 'switch', 'gb', 'gbc', 'gba',
  'nds', '3ds', 'virtualboy', 'genesis', 'mastersystem', 'gamegear', 'saturn',
  'dreamcast', 'segacd', 'sega32x', 'sg1000', 'psx', 'ps2', 'ps3', 'ps4', 'psp', 'xbox',
  'xbox360', 'pcengine', 'neogeo', 'ngp', 'arcade', 'atari2600', 'atari7800',
  'atarilynx', 'atarijaguar', '3do', 'colecovision', 'intellivision', 'msx', 'c64',
  'amiga', 'wonderswan', 'switch2', 'ps5', 'xboxone',
  'xboxseries',
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
  'switch2': Color(0xFFE60012), // Nintendo Switch 2 red
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
  'ps5': Color(0xFF2F5FC4),
  'psp': Color(0xFF2E6DB4),
  // Microsoft
  'xbox': Color(0xFF107C10), // green
  'xbox360': Color(0xFF5DC21E), // lighter green
  'xboxone': Color(0xFF0E7A0D),
  'xboxseries': Color(0xFF0B5C0B), // darker green
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
