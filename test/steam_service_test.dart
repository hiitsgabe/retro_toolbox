import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/steam_service.dart';

void main() {
  test('parseResults extracts appid, name and unescapes entities', () {
    const html = '''
<a data-ds-appid="620" href="..."><div><span class="title">Portal 2</span></div></a>
<a data-ds-appid="1091500" href="..."><div><span class="title">Tom &amp; Jerry&#39;s Quest</span></div></a>
''';
    final results = SteamService.parseResults(html);
    expect(results.length, 2);
    expect(results[0].appid, 620);
    expect(results[0].name, 'Portal 2');
    expect(results[0].bannerUrl, contains('/620/header.jpg'));
    expect(results[1].name, "Tom & Jerry's Quest");
  });

  test('sanitizeFileName keeps safe chars, replaces the rest', () {
    expect(SteamService.sanitizeFileName("Portal 2: The Sequel"), 'Portal 2_ The Sequel');
    expect(SteamService.sanitizeFileName("Tom & Jerry's (HD)"), "Tom _ Jerry's (HD)");
  });
}
