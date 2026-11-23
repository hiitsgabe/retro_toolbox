// Imports the pure slug file and nothing else from the app: if it ever pulls
// in Flutter again, the launch preset check stops running under `dart run`.
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/console_slugs.dart';

void main() {
  test('knownConsoleSlugs is every rule key, the slugs presets may name', () {
    expect(knownConsoleSlugs, containsAll(<String>['psx', 'gamecube', '3ds', 'genesis', 'arcade', 'switch', 'wii', 'wiiu', 'n64']));
    expect(knownConsoleSlugs, hasLength(47));
    expect(knownConsoleSlugs.contains('psvita'), isFalse);
    expect(knownConsoleSlugs.contains('megadrive'), isFalse);
  });

  test('the moved functions answer as they did in console_slug.dart', () {
    expect(consoleArtSlugForText('PlayStation Vita'), 'psx');
    expect(consoleArtSlugForText('Sega Genesis'), 'genesis');
    expect(batoceraPlatformForText('Sega Genesis'), 'megadrive');
    expect(slugForPlatform('megadrive'), 'genesis');
    expect(slugForPlatform('mame'), 'arcade');
    expect(slugForPlatform('gamecube'), 'gamecube');
  });
}
