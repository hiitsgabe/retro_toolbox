import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';

/// "(Disc 2)", "(Disk 1 of 3)", "(CD 2)", the same token M3uService reads.
final _discToken = RegExp(r'\((?:disc|disk|cd)\s*(\d+)[^)]*\)', caseSensitive: false);
final _ws = RegExp(r'\s+');

/// The key a game's discs share: its console and its title without the disc
/// token. Null when the title names no disc.
String? discGroupKey(Game game) {
  if (!_discToken.hasMatch(game.title)) return null;
  final base = game.title.replaceAll(_discToken, ' ').replaceAll(_ws, ' ').trim();
  return '${game.consoleId}|$base';
}

/// The disc number in [game]'s title, 0 when there is none.
int discNumber(Game game) {
  final m = _discToken.firstMatch(game.title);
  return m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
}

/// Every disc of [game]'s set found in [games], by disc number; just [game]
/// when its title names no disc.
List<Game> discSetOf(Game game, Iterable<Game> games) {
  final key = discGroupKey(game);
  if (key == null) return [game];
  final set = [
    for (final g in games)
      if (discGroupKey(g) == key) g
  ];
  if (set.isEmpty) return [game];
  set.sort((a, b) => discNumber(a).compareTo(discNumber(b)));
  return set;
}

/// [games] with each set of two or more discs as one entry: its lowest disc,
/// carrying the whole set in [Game.discs], where the set's first disc was.
/// Other games are kept as they are, in order.
List<Game> groupDiscSets(List<Game> games) {
  final sets = <String, List<Game>>{};
  for (final g in games) {
    final key = discGroupKey(g);
    if (key != null) sets.putIfAbsent(key, () => []).add(g);
  }
  final out = <Game>[];
  final placed = <String>{};
  for (final g in games) {
    final key = discGroupKey(g);
    final set = key == null ? null : sets[key]!;
    if (set == null || set.length < 2) {
      out.add(g);
      continue;
    }
    if (!placed.add(key!)) continue;
    final ordered = [...set]..sort((a, b) => discNumber(a).compareTo(discNumber(b)));
    out.add(ordered.first.copyWith(discs: ordered));
  }
  return out;
}

/// What Download on [game] gets: with [all], every disc of its set (from
/// [Game.discs], else found in [catalog]) except discs already queued, in
/// progress or done, by [statusOf]; [game] itself always. Otherwise just [game].
List<Game> discsToDownload(Game game, {required bool all, Iterable<Game>? catalog, GameStatus? Function(String gameId)? statusOf}) {
  if (!all) return [game];
  final set = game.discs.length >= 2
      ? game.discs
      : catalog == null
          ? [game]
          : discSetOf(game, catalog);
  if (set.length < 2) return [game];
  return [
    for (final d in set)
      if (d.gameId == game.gameId || _wantsDownload(statusOf?.call(d.gameId))) d,
  ];
}

bool _wantsDownload(GameStatus? status) => switch (status) {
      null || GameStatus.init || GameStatus.loading || GameStatus.ready || GameStatus.downloadFailed || GameStatus.error => true,
      _ => false,
    };
