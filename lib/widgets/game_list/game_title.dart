import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';

class GameTitle extends StatelessWidget {
  final Game game;
  final GameState gameState;

  const GameTitle({
    super.key,
    required this.game,
    required this.gameState,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) => Row(
      children: [
        Expanded(
          child: Tooltip(
            message: game.title,
            child: Text(
              game.displayTitle,
              style: TextStyle(
                fontSize: 13,
                color: gameState.status == GameStatus.extracted ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
                fontWeight: gameState.status == GameStatus.extracted ? FontWeight.bold : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // At the text floor the chips do not always fit beside the title on a
        // small screen: they wrap under each other instead of overflowing,
        // and never take more than about half the row from the title.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
          child: Align(
            alignment: Alignment.centerRight,
            widthFactor: 1,
            child: Wrap(
              alignment: WrapAlignment.end,
              runSpacing: 2,
              children: [
                if (game.discs.length >= 2 || game.metadata?.diskNumber.isNotEmpty == true) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      game.discs.length >= 2 ? '${game.discs.length} discs' : 'Disk ${game.metadata!.diskNumber}',
                      style: TextStyle(
                        fontSize: DeviceClass.of(context).textFloor,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (game.metadata?.revision.isNotEmpty == true) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'Rev ${game.metadata!.revision}',
                      style: TextStyle(
                        fontSize: DeviceClass.of(context).textFloor,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                if (game.metadata?.regions.isNotEmpty == true) ...[
                  const SizedBox(width: 4),
                  // One region and a count: at the text floor three did not fit a phone's row.
                  ...game.metadata!.regions.take(1).map((region) => Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withAlpha(20),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withAlpha(60),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            region,
                            style: TextStyle(
                              fontSize: DeviceClass.of(context).textFloor,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      )),
                  if (game.metadata!.regions.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '+${game.metadata!.regions.length - 1}',
                        style: TextStyle(
                          fontSize: DeviceClass.of(context).textFloor,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    ));
  }
}
