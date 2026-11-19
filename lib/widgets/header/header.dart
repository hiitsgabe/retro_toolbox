import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/screens/about_screen.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/header/console_dropdown.dart';
import 'package:retro_toolbox/widgets/header/search_field.dart';
import 'package:retro_toolbox/widgets/header/filter_modal.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';

/// Test seam for [downloadSelected].
@visibleForTesting
Future<void> Function(WidgetRef ref, BuildContext context, List<Game> games, String? consoleId)? debugStartDownloads;

/// Whether the "Download Selected" button (and Start) is usable.
bool canDownloadSelected(WidgetRef ref) =>
    !ref.read(appStateProvider).loading && ref.read(downloadProvider.notifier).hasDownloadableSelectedGames();

/// What the "Download Selected" button does; Start runs the same call. Asks
/// first: a stray Start press must not queue a whole selection.
Future<void> downloadSelected(WidgetRef ref, BuildContext context, String? consoleId) async {
  final catalogState = ref.read(catalogProvider);
  final selected = catalogState.games.where((game) => catalogState.selectedGames.contains(game.gameId));
  // What the list shows for a selected game: its entry carries the game (a
  // box set's other games, a version's other discs). The entry can be another
  // version than the one selected (a region change or a re-pick since), so it
  // is found by any disc of its group's versions (an extra, or a game of a
  // box, is what was selected).
  final grouped = consoleId != null && ref.read(catalogProvider.notifier).groupsVersions;
  final shown = {
    if (grouped)
      for (final entry in catalogState.paginatedFilteredGames)
        for (final id in [entry.gameId, ...?entry.group?.versions.expand((v) => v.discs).map((f) => f.gameId)]) id: entry,
  };
  final seen = <String>{};
  final selectedGames = <Game>[];
  for (final game in selected) {
    final entry = shown[game.gameId] ?? game;
    for (final g in grouped ? await gamesToDownload(ref, entry, catalog: catalogState.games) : [game]) {
      if (seen.add(g.gameId)) selectedGames.add(g);
    }
  }
  if (!context.mounted) return;
  if (selectedGames.isEmpty) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Already downloaded')));
    return;
  }
  final n = selectedGames.length;
  final bytes = selectedGames.fold<int>(0, (sum, g) => sum + g.size);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(n == 1 ? 'Download 1 game?' : 'Download $n games?'),
      content: bytes > 0 ? Text('${formatBytes(bytes)} in total.') : null,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(autofocus: true, onPressed: () => Navigator.pop(c, true), child: const Text('Download')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  await (debugStartDownloads ?? TaskQueueService.startDownloads)(ref, context, selectedGames, consoleId);
}

class Header extends ConsumerStatefulWidget {
  final List<Console> consoles;
  final Console? selectedConsole;
  final Function(Console) onConsoleSelect;

  const Header({
    super.key,
    required this.consoles,
    required this.selectedConsole,
    required this.onConsoleSelect,
  });

  @override
  ConsumerState<Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<Header> {
  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final catalogState = ref.watch(catalogProvider);
    final catalogNotifier = ref.read(catalogProvider.notifier);
    final taskQueueState = ref.watch(taskQueueProvider);

    // Below 600dp the console picker gets its own row: squeezed next to the
    // search field and actions it shrank to an unreadable sliver on handhelds.
    final isMobile = MediaQuery.of(context).size.width < 600;
    // The console picker stays enabled while a catalog loads: switching
    // mid-load is safe (stale loads are discarded), and a slow catalog used to
    // lock it, so changing consoles looked broken.

    final canAccessSettings = !appState.loading && !taskQueueState.hasRunningTasks;
    final canDownload = canDownloadSelected(ref);

    return Container(
      height: !isMobile ? (kToolbarHeight - 5) + MediaQuery.of(context).padding.top : null,
      decoration: BoxDecoration(
        color: StyleTokens.of(context).bar,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (Navigator.canPop(context)) ...[
                          IconButton(
                            icon: const Icon(Icons.arrow_back),
                            tooltip: 'Back',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => Navigator.maybePop(context),
                          ),
                          SizedBox(width: 4),
                        ],
                        Expanded(
                          flex: 3,
                          child: ConsoleDropdown(
                            consoles: widget.consoles,
                            selectedConsole: widget.selectedConsole,
                            onConsoleSelect: widget.onConsoleSelect,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: SearchField(
                            initialText: catalogState.filterText,
                            isEnabled: !ref.watch(appStateProvider).loading,
                            onChanged: (text) => catalogNotifier.updateFilterText(text),
                          ),
                        ),
                        SizedBox(width: 8),
                        ..._buildActionWidgets(
                          context: context,
                          appState: appState,
                          catalogState: catalogState,
                          canDownload: canDownload,
                          canAccessSettings: canAccessSettings,
                        ),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    if (Navigator.canPop(context)) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                      ),
                      SizedBox(width: 4),
                    ] else ...[
                      Image.asset('assets/icon.png', width: 35),
                      SizedBox(width: 16),
                    ],
                    Expanded(
                      flex: 2,
                      child: ConsoleDropdown(
                        consoles: widget.consoles,
                        selectedConsole: widget.selectedConsole,
                        onConsoleSelect: widget.onConsoleSelect,
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: SearchField(
                        initialText: catalogState.filterText,
                        isEnabled: !ref.watch(appStateProvider).loading,
                        onChanged: (text) => catalogNotifier.updateFilterText(text),
                      ),
                    ),
                    SizedBox(width: 8),
                    ..._buildActionWidgets(
                      context: context,
                      appState: appState,
                      catalogState: catalogState,
                      canDownload: canDownload,
                      canAccessSettings: canAccessSettings,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  List<Widget> _buildActionWidgets({
    required BuildContext context,
    required AppState appState,
    required CatalogState catalogState,
    required bool canDownload,
    required bool canAccessSettings,
  }) {
    final appStateNotifier = ref.read(appStateProvider.notifier);
    // A card style other than Classic has its own layout: no view modes.
    final classic = cardStyleKit(ref.watch(styleProvider.select((s) => s.cards))) == null;

    return [
      _buildActionButton(
        context: context,
        icon: catalogState.filter.differsFromDefault ? Icons.filter_alt : Icons.filter_alt_outlined,
        isActive: catalogState.filter.differsFromDefault,
        onPressed: () => FilterModal.show(context),
        tooltip: 'Filters',
      ),
      SizedBox(width: 4),
      _buildActionButton(
        context: context,
        icon: Icons.download_rounded,
        isActive: canDownload,
        onPressed: canDownload ? () => downloadSelected(ref, context, widget.selectedConsole?.id) : null,
        tooltip: 'Download Selected',
      ),
      SizedBox(width: 4),
      if (classic) ...[
        _buildActionButton(
          context: context,
          icon: switch (appState.viewMode) {
            ViewMode.grid => Icons.grid_view_rounded,
            ViewMode.list => Icons.view_list_rounded,
            ViewMode.coverflow => Icons.view_carousel_rounded,
          },
          isActive: false,
          onPressed: () => appStateNotifier.toggleViewMode(),
          tooltip: 'Change view',
        ),
        SizedBox(width: 4),
      ],
      PopupMenuButton<String>(
        icon: Icon(
          Icons.more_vert,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        tooltip: 'More options',
        onSelected: (value) {
          switch (value) {
            case 'settings':
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(consoleId: widget.selectedConsole?.id),
                ),
              );
              break;
            case 'about':
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AboutScreen(),
                ),
              );
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'settings',
            enabled: canAccessSettings,
            child: Row(
              children: [
                Icon(Icons.settings, size: 18),
                SizedBox(width: 12),
                Text('Settings'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'about',
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: 12),
                Text('About'),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required VoidCallback? onPressed,
    required String tooltip,
    bool isActive = false,
  }) {
    return Stack(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isActive ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive
                ? Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          child: IconButton(
            icon: Icon(
              icon,
              color: isActive
                  ? Theme.of(context).colorScheme.primary
                  : onPressed != null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              size: 20,
            ),
            onPressed: onPressed,
            tooltip: tooltip,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
