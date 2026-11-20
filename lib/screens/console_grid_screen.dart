import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// Grid of consoles. Tapping a console selects it (which starts its catalog
/// load) and opens the game list (HomeScreen).
class ConsoleGridScreen extends ConsumerWidget {
  const ConsoleGridScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    // A card style other than Classic has its own layout: no view modes.
    final kit = cardStyleKit(ref.watch(styleProvider.select((s) => s.cards)));

    // Always the console list: a catalog loads (and can fail) on the games
    // screen, never here.
    final Widget body;
    if (appState.consolesList.isEmpty) {
      body = EmptyState(
        icon: Icons.dataset_outlined,
        glyph: PixelIcons.games,
        line: 'No catalog configured. Add one in Settings.',
        action: KitAction(
          'Open Settings',
          () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen(consoleId: null))),
          icon: Icons.settings,
        ),
      );
    } else {
      final k = StyleTokens.of(context);
      final tiles = [
        for (final (i, console) in appState.consolesList.indexed) _consoleTile(context, ref, console, k.paletteAt(i)),
      ];
      body = kit?.menuList(context, tiles, shrinkWrap: false, autofocusFirst: true) ?? _viewFor(appState.consoleViewMode, tiles);
    }

    final count = appState.consolesList.length;
    final showToggle = count > 0 && kit == null;
    return KitScaffold(
      title: 'Games Library',
      subtitle: count == 0 ? null : (count == 1 ? '1 console' : '$count consoles'),
      icon: Icons.videogame_asset,
      glyph: PixelIcons.games,
      area: AppArea.games,
      padding: EdgeInsets.zero,
      actions: [
        if (showToggle)
          IconButton(
            icon: Icon(_viewIcon(appState.consoleViewMode)),
            tooltip: 'Change view',
            onPressed: () => ref.read(appStateProvider.notifier).toggleConsoleViewMode(),
          ),
      ],
      body: body,
    );
  }

  Widget _viewFor(ViewMode mode, List<MenuTile> tiles) {
    switch (mode) {
      case ViewMode.coverflow:
        return CoverFlow(
          items: [
            for (final t in tiles) CoverFlowItem(face: MenuTileFace(tile: t, showLabel: false), label: t.label, onTap: t.onTap),
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

  /// [tint]: the cartridge's label colour; every console is a Games tile,
  /// and one colour for all of them read as a wall of red.
  MenuTile _consoleTile(BuildContext context, WidgetRef ref, Console console, Color tint) {
    final appStateNotifier = ref.read(appStateProvider.notifier);
    return MenuTile(
      label: console.name,
      area: AppArea.games,
      tint: tint,
      pixelIcon: PixelIcons.games,
      icon: Icons.videogame_asset,
      assetPath: consoleLogoAsset(console),
      accentColor: consoleBrandColor(console),
      brandLogo: true,
      onTap: () {
        appStateNotifier.selectConsole(console);
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HomeScreen()));
      },
    );
  }
}
