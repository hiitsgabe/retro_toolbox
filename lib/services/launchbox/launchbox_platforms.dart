import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';

/// LaunchBox platform name per Batocera system id. Names are exactly as
/// LaunchBox's Metadata.xml spells them.
const launchboxPlatformById = {
  '3do': '3DO Interactive Multiplayer',
  '3ds': 'Nintendo 3DS',
  'atari2600': 'Atari 2600',
  'atari7800': 'Atari 7800',
  'colecovision': 'ColecoVision',
  'dreamcast': 'Sega Dreamcast',
  'fds': 'Nintendo Famicom Disk System',
  'gamecube': 'Nintendo GameCube',
  'gamegear': 'Sega Game Gear',
  'gb': 'Nintendo Game Boy',
  'gba': 'Nintendo Game Boy Advance',
  'gbc': 'Nintendo Game Boy Color',
  'intellivision': 'Mattel Intellivision',
  'jaguar': 'Atari Jaguar',
  'lynx': 'Atari Lynx',
  'mastersystem': 'Sega Master System',
  'megadrive': 'Sega Genesis',
  'msx': 'Microsoft MSX',
  'msx1': 'Microsoft MSX',
  'msx2': 'Microsoft MSX2',
  'n64': 'Nintendo 64',
  'nds': 'Nintendo DS',
  'neogeo': 'SNK Neo Geo AES',
  'neogeocd': 'SNK Neo Geo CD',
  'nes': 'Nintendo Entertainment System',
  'ngp': 'SNK Neo Geo Pocket',
  'ngpc': 'SNK Neo Geo Pocket Color',
  'pcengine': 'NEC TurboGrafx-16',
  'pcenginecd': 'NEC TurboGrafx-CD',
  'pokemini': 'Nintendo Pokemon Mini',
  'ps2': 'Sony Playstation 2',
  'ps3': 'Sony Playstation 3',
  'ps4': 'Sony Playstation 4',
  'psp': 'Sony PSP',
  'psvita': 'Sony Playstation Vita',
  'psx': 'Sony Playstation',
  'satellaview': 'Nintendo Satellaview',
  'saturn': 'Sega Saturn',
  'sega32x': 'Sega 32X',
  'segacd': 'Sega CD',
  'sg1000': 'Sega SG-1000',
  'snes': 'Super Nintendo Entertainment System',
  'supergrafx': 'PC Engine SuperGrafx',
  'switch': 'Nintendo Switch',
  'switch2': 'Nintendo Switch 2',
  'virtualboy': 'Nintendo Virtual Boy',
  'wii': 'Nintendo Wii',
  'wiiu': 'Nintendo Wii U',
  'wswan': 'WonderSwan',
  'wswanc': 'WonderSwan Color',
  'xbox': 'Microsoft Xbox',
  'xbox360': 'Microsoft Xbox 360',
};

/// The LaunchBox platform a console's games are looked up in: the catalog's
/// own `launchbox_platform`, else the built-in name for its platform id, else
/// null (no metadata for it).
String? launchboxPlatformFor(Console console) {
  final own = console.launchboxPlatform?.trim();
  if (own != null && own.isNotEmpty) return own;
  return launchboxPlatformById[console.resolvedPlatform];
}

/// File-safe name for a platform: "Sony Playstation 2" -> "sony_playstation_2".
String launchboxPlatformSlug(String platform) =>
    platform.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
