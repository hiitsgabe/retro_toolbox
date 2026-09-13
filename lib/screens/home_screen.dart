import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/app_state_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/widgets/header/header.dart';
import 'package:roms_downloader/widgets/game_list/game_list.dart';
import 'package:roms_downloader/widgets/game_grid/game_grid.dart';
import 'package:roms_downloader/widgets/game_grid/game_cover_flow.dart';
import 'package:roms_downloader/widgets/footer/footer.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/services/task_queue_service.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';
import 'package:roms_downloader/screens/settings_screen.dart';
import 'package:roms_downloader/widgets/common/hammer_loader.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// The batch plan for the current mode. Both branches return the same type
  /// and fall into the same sheet, queue and clear; only how the `BatchPlan` is
  /// built varies between modes.
  BatchPlan _selectionPlan(Set<String> selected) {
    if (ref.read(gridModeProvider) == GridMode.pack) {
      // `allPackEntriesProvider`, not `packGridEntriesProvider`: the batch acts
      // on the whole selection, not just the filtered grid.
      return planFromEntries(
        entriesForSelection(ref.read(allPackEntriesProvider), selected),
        preferredRegions: ref.read(preferredRegionsProvider),
        resolveGame: ref.read(gameResolverProvider),
        sourcePriority: ref.read(sourcePriorityProvider),
      );
    }
    // SOURCE MODE: each key is already a file, nothing to pick.
    final games = ref.read(catalogProvider).games;
    return planFromGames(games.where((game) => selected.contains(game.gameId)).toList());
  }

  /// Opens the confirmation sheet, and only queues what comes back from it.
  Future<void> _confirmBatch(Set<String> selected) async {
    var plan = _selectionPlan(selected);
    // A failures-only plan is not empty: the sheet opens to explain why nothing
    // will be downloaded.
    if (plan.isEmpty) return;

    final confirmed = await showModalBottomSheet<BatchPlan>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => BatchConfirmSheet(
          plan: plan,
          onConfirm: (p) => Navigator.of(sheetContext).pop(p),
          onRemove: (gameId) => setSheetState(() => plan = plan.withoutPick(gameId)),
        ),
      ),
    );
    if (confirmed == null || !mounted) return;

    await TaskQueueService.startDownloads(
      ref,
      context,
      confirmed.picks.map((pick) => pick.game).toList(),
      ref.read(appStateProvider).selectedConsole?.id,
    );
    if (!mounted) return;
    ref.read(catalogProvider.notifier).clearSelection();
  }

  /// Pushes the detail screen.
  ///
  /// The grid does not navigate and the screen does not know the queue; the two
  /// loose ends meet here, and only here.
  void _openDetail(PackGridEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDetailScreen(
        entry: entry,
        onDownload: _downloadOne,
        onBatchDownload: () => _confirmBatch(_modeSelection),
      ),
    ));
  }

  /// The current mode's selection, read at tap time.
  ///
  /// `build` computes the same thing for the bar count, but the batch reads
  /// here because the sheet can be opened from the detail screen sitting on top
  /// of this one.
  Set<String> get _modeSelection => selectionKeysFor(
        ref.read(catalogProvider).selectedGames,
        pack: ref.read(gridModeProvider) == GridMode.pack,
      );

  /// A single pick from the detail screen goes straight to the queue.
  ///
  /// No confirmation sheet, and that is a decision, not an oversight: the detail
  /// screen is the confirmation. It already shows the chosen file, its size, the
  /// full reason and the CRC verdict. The sheet exists for the batch, where the
  /// user saw no pick before pressing Download.
  Future<void> _downloadOne(SourcePick pick) async {
    await TaskQueueService.startDownloads(
      ref,
      context,
      [pick.game],
      ref.read(appStateProvider).selectedConsole?.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final appStateNotifier = ref.read(appStateProvider.notifier);
    final loadingStatus = ref.watch(catalogProvider.select((s) => s.loadingStatus));
    final errorMessage = ref.watch(catalogProvider.select((s) => s.errorMessage));
    final gridMode = ref.watch(gridModeProvider);
    final selected = selectionKeysFor(
      ref.watch(catalogProvider.select((s) => s.selectedGames)),
      pack: gridMode == GridMode.pack,
    );

    return Scaffold(
      body: Column(
        children: [
          Header(
            consoles: appState.consolesList,
            selectedConsole: appState.selectedConsole,
            onConsoleSelect: appStateNotifier.selectConsole,
          ),
          Expanded(
            child: appState.consolesList.isEmpty && !appState.loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dataset_outlined, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          const Text('No catalog configured', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 8),
                          const Text(
                            'Add a console catalog to get started: import a JSON file or load one from a URL.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen(consoleId: null)),
                            ),
                            icon: const Icon(Icons.settings),
                            label: const Text('Open Settings'),
                          ),
                        ],
                      ),
                    ),
                  )
                : appState.loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        HammerLoader(),
                        SizedBox(height: 16),
                        Text(loadingStatus.isEmpty ? 'Loading (this can take a while)...' : '$loadingStatus...'),
                      ],
                    ),
                  )
                : errorMessage.isNotEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
                              const SizedBox(height: 12),
                              Text(errorMessage, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : switch (gridMode) {
                        GridMode.pack => PackGrid(onOpenGame: _openDetail),
                        GridMode.source => switch (appState.viewMode) {
                            ViewMode.grid => GameGrid(),
                            ViewMode.coverflow => const GameCoverFlow(),
                            ViewMode.list => GameList(),
                          },
                      },
          ),
          SelectionBar(
            count: selected.length,
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () => _confirmBatch(_modeSelection),
          ),
          Footer(),
        ],
      ),
    );
  }
}
