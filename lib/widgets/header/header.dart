import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/screens/about_screen.dart';
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

/// The owned view's name: its header button's tooltip.
const ownedViewLabel = 'Owned';

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
  /// Narrow screens: the search field is open in the console's place.
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final appState = ref.watch(appStateProvider);
    final catalogState = ref.watch(catalogProvider);
    final catalogNotifier = ref.read(catalogProvider.notifier);
    final taskQueueState = ref.watch(taskQueueProvider);
    final k = StyleTokens.of(context);

    // One row everywhere. Below 600 dp search is an icon that opens the field
    // in the console's place: next to the console, the actions and back, a
    // field on a phone was a sliver (it used to take a second row).
    final narrow = MediaQuery.sizeOf(context).width < 600;
    // A search under way stays open, so the query shows.
    final searching = !narrow || _searching || catalogState.filterText.isNotEmpty;
    // The console picker stays enabled while a catalog loads: switching
    // mid-load is safe (stale loads are discarded), and a slow catalog used to
    // lock it, so changing consoles looked broken.

    final canAccessSettings = !appState.loading && !taskQueueState.hasRunningTasks;
    final canDownload = canDownloadSelected(ref);

    final search = SearchField(
      initialText: catalogState.filterText,
      isEnabled: !appState.loading,
      autofocus: narrow,
      onFocusChange: (focused) {
        if (!focused && mounted && _searching && ref.read(catalogProvider).filterText.isEmpty) setState(() => _searching = false);
      },
      onChanged: (text) => catalogNotifier.updateFilterText(text),
    );
    final console = ConsoleDropdown(
      consoles: widget.consoles,
      selectedConsole: widget.selectedConsole,
      onConsoleSelect: widget.onConsoleSelect,
    );

    return Container(
      decoration: BoxDecoration(
        // Translucent, as the kit's bars: the backdrop shows through.
        color: Color.alphaBlend(Colors.black.withValues(alpha: 0.3), k.surface.withValues(alpha: 0.55)),
        border: Border(bottom: BorderSide(color: k.panelLine)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                if (Navigator.canPop(context))
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.maybePop(context),
                  )
                else ...[
                  const SizedBox(width: 4),
                  Image.asset('assets/icon.png', width: 32),
                  const SizedBox(width: 8),
                ],
                const SizedBox(width: 2),
                if (narrow) ...[
                  Expanded(child: searching ? search : console),
                  if (!searching)
                    _HeaderButton(
                      icon: Icons.search_rounded,
                      tooltip: 'Search',
                      onPressed: appState.loading ? null : () => setState(() => _searching = true),
                    ),
                ] else ...[
                  Expanded(flex: 2, child: console),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: search),
                ],
                const SizedBox(width: 4),
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
    // Shown with a Classic view (Classic's own, or the game layout's): the
    // card styles' own layouts have no view modes.
    final style = ref.watch(styleProvider);
    final view = style.gameView(appState.viewMode);
    final changed = catalogState.filter.changesFromDefault;

    return [
      // Launcher mode's owned view: the games on disk, or the whole catalog.
      if (ref.watch(launcherModeProvider))
        _HeaderButton(
          icon: Icons.sports_esports_rounded,
          isActive: catalogState.filter.ownedOnly,
          onPressed: () => ref.read(catalogProvider.notifier).toggleOwnedOnly(),
          tooltip: ownedViewLabel,
        ),
      // The badge only when the filter is off its defaults: the defaults hide
      // bad dumps and other regions, which is not something the user set.
      _HeaderButton(
        icon: changed > 0 ? Icons.filter_alt : Icons.filter_alt_outlined,
        isActive: changed > 0,
        badge: changed > 0 ? '$changed' : null,
        onPressed: () => FilterModal.show(context),
        tooltip: 'Filters',
      ),
      _HeaderButton(
        icon: Icons.download_rounded,
        isActive: canDownload,
        onPressed: canDownload ? () => downloadSelected(ref, context, widget.selectedConsole?.id) : null,
        tooltip: 'Download Selected',
      ),
      if (view != null)
        _HeaderButton(
          icon: switch (view) {
            ViewMode.grid => Icons.grid_view_rounded,
            ViewMode.list => Icons.view_list_rounded,
            ViewMode.coverflow => Icons.view_carousel_rounded,
          },
          // A picked layout is the setting: the toggle moves it on (never
          // back to the style's own, which Settings > Style picks).
          onPressed: style.gameLayout == GameLayout.styleDefault
              ? () => appStateNotifier.toggleViewMode()
              : () => ref.read(styleProvider.notifier).setGameLayout(style.gameLayout.next),
          tooltip: 'Change view',
        ),
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
}

/// A 40 px icon button of the header, lit when [isActive], with an optional
/// count in its corner.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onPressed, required this.tooltip, this.isActive = false, this.badge});

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool isActive;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = StyleTokens.of(context);
    final badge = this.badge;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isActive ? k.accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(
                icon,
                color: isActive
                    ? k.accent
                    : onPressed != null
                        ? scheme.onSurfaceVariant
                        : scheme.onSurfaceVariant.withValues(alpha: 0.4),
                size: 22,
              ),
              onPressed: onPressed,
              tooltip: tooltip,
              padding: EdgeInsets.zero,
            ),
          ),
          if (badge != null)
            Positioned(
              top: -2,
              right: -2,
              child: IgnorePointer(
                child: Container(
                  key: const ValueKey('filter-badge'),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: k.accent, borderRadius: BorderRadius.circular(9)),
                  child: Text(
                    badge,
                    style: TextStyle(fontFamily: StyleTokens.displayFont, fontSize: 12, height: 1.1, fontWeight: FontWeight.w700, color: k.onAccent),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
