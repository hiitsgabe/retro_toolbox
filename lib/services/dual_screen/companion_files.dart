import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/services/disc_sets.dart';
import 'package:retro_toolbox/services/game_groups.dart';

/// The one thing a file's row on the game's page can do, the first of these
/// its state offers.
const fileRowActions = [
  GameAction.download,
  GameAction.pause,
  GameAction.resume,
  GameAction.cancel,
  GameAction.extract,
  GameAction.retryDownload,
  GameAction.retryExtraction,
];

GameAction? fileRowAction(GameState state) => fileRowActions.where(state.availableActions.contains).firstOrNull;

/// One row of the game's page that is a file of its own: a disc, a version,
/// an extra, an update, a DLC or a mod. [main]: the version the list shows.
class GameFile {
  const GameFile(this.section, this.label, this.game, {this.main = false});

  final String section;
  final String label;
  final Game game;
  final bool main;

  /// A multi-disc version's size is its discs'.
  int get size => game.discs.length >= 2 ? game.discs.fold<int>(0, (sum, d) => sum + d.size) : game.size;
}

/// The file rows of [game]'s page, in its order. A box set's contents are
/// not here: each opens a page of its own.
List<GameFile> gameFiles(Game game) {
  final group = game.group;
  return [
    if (game.discs.length >= 2)
      for (final (i, d) in game.discs.indexed) GameFile('Discs', 'Disc ${discNumber(d) == 0 ? i + 1 : discNumber(d)}', d),
    if (group != null && group.versions.length >= 2)
      for (final v in group.versions) GameFile('Versions', v.label, v.entry, main: v.first.gameId == game.gameId),
    if (group != null) for (final e in group.extras) GameFile('Extras', extraLabel(e), e),
    for (final a in game.updates) GameFile('Updates', a.label, a.toGame(game)),
    for (final a in game.dlcs) GameFile('DLC', a.label, a.toGame(game)),
    for (final a in game.mods) GameFile('Mods', a.label, a.toGame(game)),
  ];
}

/// A file row as the second screen gets it.
Map<String, dynamic> gameFileJson(GameFile f, GameState state) => {
      'section': f.section,
      'label': f.label,
      'gameId': f.game.gameId,
      'size': f.size,
      'status': state.statusText,
      'action': fileRowAction(state)?.name,
      if (f.main) 'main': true,
    };
