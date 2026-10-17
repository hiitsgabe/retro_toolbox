import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';

void main() {
  test('genesis is not mistaken for nes', () {
    expect(consoleArtSlugForText('genesis'), 'genesis');
    expect(consoleArtSlugForText('Sega Genesis'), 'genesis');
    expect(consoleArtSlugForText('nes'), 'nes');
    expect(consoleArtSlugForText('snes'), 'snes');
  });
}
