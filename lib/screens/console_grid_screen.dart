import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';

/// Grid of consoles. Tapping a console selects it (which starts its catalog
/// load) and opens the game list (HomeScreen).
class ConsoleGridScreen extends ConsumerWidget {
  const ConsoleGridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);

    // Always the console list: a catalog loads (and can fail) on the games
    // screen, never here.
    Widget body;
    if (appState.consolesList.isEmpty) {
      body = Center(
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
      );
    } else {
      final tiles = [
        for (final console in appState.consolesList) _consoleTile(context, ref, console),
      ];
      body = _viewFor(appState.consoleViewMode, tiles);
    }

    final showToggle = appState.consolesList.isNotEmpty;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(96),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                ),
                const Spacer(),
                Text(
                  'Games Library',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (showToggle)
                  IconButton(
                    icon: Icon(_viewIcon(appState.consoleViewMode)),
                    tooltip: 'Change view',
                    onPressed: () => ref.read(appStateProvider.notifier).toggleConsoleViewMode(),
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: body,
      ),
    );
  }

  Widget _viewFor(ViewMode mode, List<MenuTile> tiles) {
    switch (mode) {
      case ViewMode.coverflow:
        return CoverFlow(
          items: [
            for (final t in tiles)
              CoverFlowItem(face: MenuTileFace(tile: t, showLabel: false), label: t.label, onTap: t.onTap),
          ],
        );
      case ViewMode.list:
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: tiles.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final t = tiles[i];
            return ListTile(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              leading: SizedBox(width: 52, height: 52, child: MenuTileFace(tile: t, showLabel: false)),
              title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: const Icon(Icons.chevron_right),
              onTap: t.onTap,
            );
          },
        );
      case ViewMode.grid:
        return MenuGrid(tiles: tiles);
    }
  }

  IconData _viewIcon(ViewMode mode) {
    switch (mode) {
      case ViewMode.grid:
        return Icons.grid_view_rounded;
      case ViewMode.list:
        return Icons.view_list_rounded;
      case ViewMode.coverflow:
        return Icons.view_carousel_rounded;
    }
  }

  MenuTile _consoleTile(BuildContext context, WidgetRef ref, Console console) {
    final appStateNotifier = ref.read(appStateProvider.notifier);
    return MenuTile(
      label: console.name,
      icon: Icons.videogame_asset,
      assetPath: consoleLogoAsset(console),
      accentColor: consoleBrandColor(console),
      onTap: () {
        appStateNotifier.selectConsole(console);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
      },
    );
  }
}
