import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_platforms.dart';

Console console(Map<String, dynamic> extra, {String id = 'x', String name = 'X'}) =>
    Console.fromJson({'id': id, 'name': name, 'url': 'http://a', ...extra});

void main() {
  test('launchbox_platform in the JSON wins over the built-in map', () {
    final c = console({'platform': 'psx', 'launchbox_platform': 'Custom Name'});
    expect(launchboxPlatformFor(c), 'Custom Name');
  });

  test('a blank launchbox_platform falls back to the map', () {
    final c = console({'platform': 'psx', 'launchbox_platform': '  '});
    expect(launchboxPlatformFor(c), 'Sony Playstation');
  });

  test('built-in map covers snes and megadrive', () {
    expect(launchboxPlatformFor(console({'platform': 'snes'})), 'Super Nintendo Entertainment System');
    expect(launchboxPlatformFor(console({'platform': 'megadrive'})), 'Sega Genesis');
  });

  test('no platform field resolves through the name keywords', () {
    final c = console({}, id: 'genesis', name: 'Sega Genesis');
    expect(launchboxPlatformFor(c), 'Sega Genesis');
    expect(launchboxPlatformFor(console({}, id: 'lynx', name: 'Atari Lynx')), 'Atari Lynx');
  });

  test('the msx keyword resolves to the plain msx id', () {
    expect(launchboxPlatformFor(console({}, id: 'msx', name: 'MSX')), 'Microsoft MSX');
  });

  test('an unknown platform id gives null', () {
    expect(launchboxPlatformFor(console({'platform': 'zxspectrum'})), isNull);
  });

  test('toJson and fromJson keep launchboxPlatform', () {
    final c = console({'launchbox_platform': 'Custom Name'});
    expect(Console.fromJson(c.toJson()).launchboxPlatform, 'Custom Name');
  });

  test('platform slugs are file safe', () {
    expect(launchboxPlatformSlug('Sony Playstation 2'), 'sony_playstation_2');
    expect(launchboxPlatformSlug('3DO Interactive Multiplayer'), '3do_interactive_multiplayer');
    expect(launchboxPlatformSlug('NEC TurboGrafx-16'), 'nec_turbografx_16');
    expect(launchboxPlatformSlug(' PC Engine (SuperGrafx)! '), 'pc_engine_supergrafx');
  });
}
