import 'package:retro_toolbox/utils/title_match.dart';

import 'launchbox_models.dart';

final _bracketGroups = RegExp(r'\s*[\[(][^\])]*[\])]');

// "X, The" at the end of the name or of its main title, before a " - " or
// ": " subtitle. Only the capitalized article: No-Intro and LaunchBox always
// write it that way, and "Ride, the Wave" is not an inverted title.
final _trailingArticle = RegExp(r'^(.+?), (The|An|A)(?=$| - |: )');

/// A title in the shape LaunchBox names games: bracket groups dropped, a
/// trailing article moved to the front ("Legend of Zelda, The - A Link to
/// the Past" -> "The Legend of Zelda - A Link to the Past"), "&" as "and".
String launchboxTitleKey(String title) {
  final stripped = title.replaceAll(_bracketGroups, '').trim();
  return stripped
      .replaceFirstMapped(_trailingArticle, (m) => '${m[2]} ${m[1]}')
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// The LaunchBox id for each title (a file name without extension), or null.
/// Exact normalized name or alternate name first, then the box art matcher's
/// fuzzy pass, which keeps sequel numbers apart. When two LaunchBox games
/// share a name, the one with more votes wins.
Future<List<int?>> matchLaunchboxIds(List<String> titles, List<LaunchboxGame> games) async {
  // Most votes first, so putIfAbsent leaves each key to the best known game;
  // the index breaks ties so the order does not depend on the sort.
  final order = [for (var i = 0; i < games.length; i++) i]..sort((a, b) {
      final c = (games[b].ratingCount ?? 0).compareTo(games[a].ratingCount ?? 0);
      return c != 0 ? c : a.compareTo(b);
    });
  final ids = <String, String>{};
  for (final i in order) {
    final g = games[i];
    for (final name in [g.name, ...g.alternateNames]) {
      final key = normalizeTitle(launchboxTitleKey(name));
      if (key.isNotEmpty) ids.putIfAbsent(key, () => '${g.id}');
    }
  }
  final matched = await matchBoxartUrlsParallel([for (final t in titles) launchboxTitleKey(t)], ids);
  return [for (final id in matched) id == null ? null : int.parse(id)];
}
