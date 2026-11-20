import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/kit/slot.dart';

class Footer extends ConsumerWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    final catalogState = ref.watch(catalogProvider);
    final gameStateManager = ref.watch(gameStateManagerProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);

    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrow = isPortrait || screenWidth < 600;

    final activeGames = gameStateManager.values.where((gameState) => gameState.isActive).toList();

    final downloadingGames = activeGames
        .where((state) => state.status == GameStatus.downloading || state.status == GameStatus.downloadPaused || (state.isTransfer && state.status == GameStatus.extracting))
        .length;
    final extractingGames = activeGames.where((state) => !state.isTransfer && state.status == GameStatus.extracting).length;

    final hasActiveTasks = downloadingGames > 0 || extractingGames > 0;

    final overallProgress = _calculateOverallProgress(activeGames);

    final downloadDir = settingsNotifier.getDownloadDir(appState.selectedConsole?.id);
    final t = KitType.of(context);
    final k = t.k;
    final muted = t.subtitle;

    // One row: what runs (with its progress), the count, and the download
    // folder; the whole bar opens the task manager.
    return SizedBox(
      height: 40,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => TaskPanelModal.show(context),
          // The global DpadScope outline is the only focus indicator.
          focusColor: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              // Translucent, as the kit's bars: the backdrop shows through.
              color: Color.alphaBlend(Colors.black.withValues(alpha: 0.3), k.surface.withValues(alpha: 0.55)),
              border: Border(top: BorderSide(color: hasActiveTasks ? k.accent.withValues(alpha: 0.5) : k.panelLine)),
            ),
            // Three parts: what runs and the count on the left, the chevron in
            // the middle (never over the text), the folder on the right.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (hasActiveTasks) ...[
                          Flexible(
                            child: Text(
                              _buildStatusText(downloadingGames, extractingGames),
                              style: muted.copyWith(color: k.accent, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: isNarrow ? 40 : 72,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(value: overallProgress, backgroundColor: Colors.white.withValues(alpha: 0.12), color: k.accent, minHeight: 4),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        // The body says the catalog is loading; the bar does not repeat it.
                        if (!appState.loading)
                          Flexible(child: Text('${catalogState.filteredGamesCount} games', style: muted, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
                  // The bar's InkWell handles taps on the arrow too.
                  IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.keyboard_arrow_up, size: 24, color: hasActiveTasks ? k.accent : t.muted.withValues(alpha: 0.7)),
                    ),
                  ),
                  Expanded(child: Align(alignment: Alignment.centerRight, child: PathText(downloadDir, style: muted))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _calculateOverallProgress(List<GameState> activeGames) {
    if (activeGames.isEmpty) return 0.0;
    double totalProgress = 0.0;
    for (final gameState in activeGames) {
      totalProgress += gameState.currentProgress;
    }
    return totalProgress / activeGames.length;
  }

  String _buildStatusText(int downloading, int extracting) {
    final statuses = <String>[];
    if (downloading > 0) statuses.add("Downloading $downloading");
    if (extracting > 0) statuses.add("Extracting $extracting");
    return statuses.join(" • ");
  }
}
