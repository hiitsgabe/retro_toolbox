import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/services/fbi_server_service.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';

Console console(String name, {String? platform, List<String>? formats}) =>
    Console(id: 'a', name: name, urls: const [], platform: platform, originalFormat: formats);

void main() {
  test('genesis is not mistaken for nes', () {
    expect(consoleArtSlugForText('genesis'), 'genesis');
    expect(consoleArtSlugForText('Sega Genesis'), 'genesis');
    expect(consoleArtSlugForText('nes'), 'nes');
    expect(consoleArtSlugForText('snes'), 'snes');
  });

  test('current consoles resolve to their own slug, not an older sibling', () {
    expect(consoleArtSlugForText('PlayStation 5'), 'ps5');
    expect(consoleArtSlugForText('ps5'), 'ps5');
    expect(consoleArtSlugForText('Xbox One'), 'xboxone');
    // One logo for the whole Series generation.
    expect(consoleArtSlugForText('Xbox Series X'), 'xboxseries');
    expect(consoleArtSlugForText('Xbox Series S'), 'xboxseries');
    expect(consoleArtSlugForText('Xbox Series X|S'), 'xboxseries');
    expect(consoleArtSlugForText('Xbox 360'), 'xbox360');
    expect(consoleArtSlugForText('Xbox'), 'xbox');
    expect(consoleArtSlugForText('PlayStation 4'), 'ps4');
  });

  group('resolvedPlatform', () {
    test('explicit platform wins', () {
      expect(console('Game Boy', platform: 'gba').resolvedPlatform, 'gba');
    });

    test('name fallback uses batocera ids', () {
      expect(console('Sega Genesis').resolvedPlatform, 'megadrive');
      expect(console('Nintendo Game Cube').resolvedPlatform, 'gamecube');
      expect(console('PlayStation 1').resolvedPlatform, 'psx');
    });

    test('format fallback', () {
      expect(console('My Files', formats: ['.nsz']).resolvedPlatform, 'switch');
      expect(console('My Files', formats: ['.cia']).resolvedPlatform, '3ds');
      expect(console('My Files', formats: ['.foo']).resolvedPlatform, isNull);
    });
  });

  test('logo follows platform', () {
    expect(consoleLogoAsset(console('x', platform: 'megadrive')), 'assets/console_art/genesis_logo.svg');
    expect(consoleLogoAsset(console('x', platform: 'wswan')), 'assets/console_art/wonderswan_logo.svg');
    expect(consoleLogoAsset(console('PlayStation 5')), 'assets/console_art/ps5_logo.svg');
    expect(consoleLogoAsset(console('Xbox One')), 'assets/console_art/xboxone_logo.svg');
    expect(consoleLogoAsset(console('Xbox Series X')), 'assets/console_art/xboxseries_logo.svg');
  });

  test('servers detect by platform', () {
    expect(TinfoilServerService.isSwitchConsole(console('Nintendo Switch')), true);
    expect(FbiServerService.is3dsConsole(console('x', platform: '3ds')), true);
  });
}
