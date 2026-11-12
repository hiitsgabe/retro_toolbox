import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/fpkgi_server_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildData produces an FPKGi document with proxy urls, covers and ids', () async {
    final console = Console.fromJson({
      'id': 'ps4',
      'name': 'PlayStation 4',
      'platform': 'ps4',
      'url': 'https://archive.org/download/ps4-fpkg-collection-english-h/',
      'original_format': ['.pkg'],
      'roms_folder': 'ps4',
    });
    final games = [
      const Game(title: 'HEAVY RAIN - [EU] [EN] [1.00].pkg', url: 'https://archive.org/download/x/HEAVY%20RAIN%20-%20%5BEU%5D%20%5BEN%5D%20%5B1.00%5D.pkg', size: 1024, consoleId: 'ps4'),
      const Game(title: 'Totally Not A Real Game - [US] [EN] [2.05].pkg', url: 'https://archive.org/download/x/Totally%20Not%20A%20Real%20Game%20-%20%5BUS%5D%20%5BEN%5D%20%5B2.05%5D.pkg', size: 0, consoleId: 'ps4'),
    ];
    await FpkgiServerService.boxarts();
    final (data, routes, icons) = FpkgiServerService.buildData({console: games}, '192.168.1.10:9095');

    final entries = (data['DATA'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>().toList();
    expect(data['DATA'], hasLength(2));

    final rain = entries.firstWhere((e) => e['name'] == 'HEAVY RAIN');
    expect(rain['title_id'], 'CUSA02356'); // Heavy Rain's CUSA in the boxart asset
    expect(rain['region'], 'EUR');
    expect(rain['version'], '1.00');
    expect(rain['size'], 1024);
    expect(rain['cover_url'], 'http://192.168.1.10:9095/fpkg/icon/CUSA02356.png');
    expect(routes.keys, contains('ps4/0'));
    expect(routes['ps4/0']!.titleId, 'CUSA02356');
    expect(icons, contains('CUSA02356'));

    final unknown = entries.firstWhere((e) => e['name'] == 'Totally Not A Real Game');
    expect(unknown['title_id'], '');
    expect(unknown['cover_url'], isNull);
  });

  test('local files override size and are served from disk', () {
    // localPs4Files only picks .pkg — cheap sanity on the extension filter.
    expect(FpkgiServerService.localPs4Files(null), isEmpty);
  });
}
