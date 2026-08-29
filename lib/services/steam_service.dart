import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Searches the Steam store and creates `.steam` shortcut files (ES-DE
/// format: a text file whose content is the Steam app ID).
class SteamGame {
  final int appid;
  final String name;

  const SteamGame({required this.appid, required this.name});

  String get bannerUrl => 'https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/$appid/header.jpg';
}

class SteamSearchPage {
  final List<SteamGame> results;
  final bool hasMore;

  const SteamSearchPage({required this.results, required this.hasMore});
}

class SteamService {
  static const resultsPerPage = 25;
  static final _resultPattern = RegExp(
    r'data-ds-appid="(\d+)".*?<span class="title">(.*?)</span>',
    dotAll: true,
  );

  Future<SteamSearchPage> search(String query, {int start = 0}) async {
    final uri = Uri.https('store.steampowered.com', '/search/results/', {
      'term': query,
      'l': 'english',
      'cc': 'US',
      'count': '$resultsPerPage',
      'start': '$start',
      'sort_by': '_ASC',
      'infinite': '1',
      'json': '1',
    });

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} searching Steam');
      }
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final html = data['results_html'] as String? ?? '';
      final total = data['total_count'] as int? ?? 0;
      final results = parseResults(html);
      return SteamSearchPage(results: results, hasMore: start + results.length < total);
    } finally {
      client.close();
    }
  }

  static List<SteamGame> parseResults(String html) {
    return _resultPattern
        .allMatches(html)
        .map((m) => SteamGame(appid: int.parse(m.group(1)!), name: _unescapeHtml(m.group(2)!)))
        .toList();
  }

  static String _unescapeHtml(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  static String sanitizeFileName(String name) {
    return name.split('').map((c) => RegExp(r"[a-zA-Z0-9 \-_()']").hasMatch(c) ? c : '_').join().trim();
  }

  /// Writes one `<name>.steam` file per game into [folder]. Returns errors
  /// keyed by game name; empty map means full success.
  Future<Map<String, String>> createShortcuts(List<SteamGame> games, String folder) async {
    final errors = <String, String>{};
    for (final game in games) {
      try {
        final file = File(path.join(folder, '${sanitizeFileName(game.name)}.steam'));
        await file.writeAsString('${game.appid}');
      } catch (e) {
        errors[game.name] = '$e';
      }
    }
    return errors;
  }
}
