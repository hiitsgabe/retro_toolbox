import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/services/dual_screen/companion_files.dart';
import 'package:retro_toolbox/services/dual_screen/companion_sync.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';

/// Runs what the companion screen's buttons ask for (see
/// companionRequestProvider) as if pressed here: [navigatorContext] is where
/// a download's dialogs show.
class CompanionActionListener extends ConsumerWidget {
  const CompanionActionListener({super.key, required this.navigatorContext, required this.child});

  final BuildContext? Function() navigatorContext;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(companionRequestProvider, (_, request) {
      if (request != null) runCompanionRequest(ref, navigatorContext(), request.json);
    });
    return child;
  }
}

/// The game a companion request names: the shown one first (a grouped
/// multi-disc entry carries its discs only there), then its files (a disc,
/// a version, an update), then the console's catalog, then the tasks (a task
/// can be from another console).
Game? companionGame(WidgetRef ref, String gameId) {
  final shown = ref.read(focusedGameProvider);
  if (shown?.gameId == gameId) return shown;
  if (shown != null) {
    for (final f in gameFiles(shown)) {
      if (f.game.gameId == gameId) return f.game;
    }
  }
  for (final g in ref.read(catalogProvider).games) {
    if (g.gameId == gameId) return g;
  }
  return ref.read(gameStateManagerProvider)[gameId]?.game;
}

Future<void> runCompanionRequest(WidgetRef ref, BuildContext? context, Map<String, dynamic> json) async {
  final gameId = json['gameId'];
  final game = gameId is String ? companionGame(ref, gameId) : null;
  if (game == null) {
    debugPrint('Companion request for an unknown game: $json');
    return;
  }
  switch (json['kind']) {
    case 'favorite':
      ref.read(favoritesProvider.notifier).toggleFavorite(game.gameId);
    case 'game':
      final action = GameAction.values.asNameMap()[json['action']];
      if (action == null || context == null || !context.mounted) {
        debugPrint('Companion request not run: $json');
        return;
      }
      await runGameAction(ref, context, game, ref.read(gameStateProvider(game)), action);
    default:
      debugPrint('Companion request of an unknown kind: $json');
  }
}
