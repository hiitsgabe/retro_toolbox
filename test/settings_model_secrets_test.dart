import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';

void main() {
  test('saved JSON omits the three Internet Archive credentials', () {
    const settings = AppSettings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz');

    final json = settings.toJson();

    expect(json.containsKey('iaAccessKey'), isFalse);
    expect(json.containsKey('iaSecretKey'), isFalse);
    expect(json.containsKey('iaCookies'), isFalse);
  });

  test('saved JSON omits the console token', () {
    const console = BaseSettings(downloadDir: '/roms/snes', authToken: 'tok-snes');

    final json = console.toJson();

    expect(json.containsKey('authToken'), isFalse);
    expect(json['downloadDir'], '/roms/snes');
  });

  test('reading the legacy format still works', () {
    // Deliberate asymmetry: writes without, reads with. An unmigrated file
    // still has these fields, and migration strips them from the raw map.
    final settings = AppSettings.fromJson({
      'iaAccessKey': 'AK',
      'consoleSettings': {
        'snes': {'authToken': 'tok-snes'},
      },
    });

    expect(settings.iaAccessKey, 'AK');
    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
  });

  test('non-secret fields are still saved', () {
    const settings = AppSettings(nszDecompressEnabled: false, catalogSourceUrl: 'https://example/consoles.json');

    final json = settings.toJson();

    expect(json['nszDecompressEnabled'], isFalse);
    expect(json['catalogSourceUrl'], 'https://example/consoles.json');
  });
}
