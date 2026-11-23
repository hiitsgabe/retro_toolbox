import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/screens/app_drawer_screen.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/header/header.dart' show ownedViewLabel;
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_reorder.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// In launcher mode, whether the console list shows only the consoles with
/// games on disk (its Owned toggle). Off shows them all again.
final consoleGridOwnedOnlyProvider = StateProvider<bool>((ref) => true);

/// Grid of consoles. Tapping a console selects it (which starts its catalog
/// load) and opens the game list (HomeScreen). With Retro Toolbox as the
/// home app, an Apps tile after the consoles opens the app drawer.
class ConsoleGridScreen extends ConsumerWidget {
  const ConsoleGridScreen({super.key});

  /// Its route's name: a Home press finds the library's root by it.
  static const routeName = 'console-grid';

  /// The Apps tile's id, apart from every console id.
  static const appsTileId = 'launcher-apps';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appStateProvider);
    // A card style other than Classic has its own layout: no view modes.
    final kit = cardStyleKit(ref.watch(styleProvider.select((s) => s.cards)));
    final launcherMode = ref.watch(launcherModeProvider);
    final ownedOnly = launcherMode && ref.watch(consoleGridOwnedOnlyProvider);
    void toggleOwned() => ref.read(consoleGridOwnedOnlyProvider.notifier).update((on) => !on);
    // As the home app, the other apps are only reachable from here: the
    // drawer stays in reach when there is no console to show too.
    final homeMode = ref.watch(homeModeProvider);
    void openApps() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppDrawerScreen()));
    final apps = homeMode ? KitAction('Apps', openApps, icon: Icons.apps) : null;
    // The check wizard step 2 makes. A console still being checked shows, so
    // the list only ever shrinks while it settles.
    final consoles = [
      for (final c in appState.consolesList)
        if (!ownedOnly || ref.watch(gamesOnDiskProvider(c.id)).valueOrNull != false) c,
    ];

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
        secondAction: apps,
      );
    } else if (consoles.isEmpty) {
      body = EmptyState(
        icon: Icons.folder_off_outlined,
        glyph: PixelIcons.games,
        line: 'No console has games on disk yet',
        action: KitAction('Show all', toggleOwned),
        secondAction: apps,
      );
    } else {
      final k = StyleTokens.of(context);
      final tiles = [
        for (final (i, console) in consoles.indexed) _consoleTile(context, ref, console, k.paletteAt(i)),
        if (homeMode) MenuTile(id: appsTileId, label: 'Apps', area: AppArea.games, pixelIcon: PixelIcons.tools, icon: Icons.apps, onTap: openApps),
      ];
      body = ReorderableMenu(
        menuId: 'consoles',
        tiles: tiles,
        builder: (context, tiles) => kit?.menuList(context, tiles, shrinkWrap: false, autofocusFirst: true) ?? _viewFor(context, appState.consoleViewMode, tiles),
      );
    }

    final count = consoles.length;
    final showToggle = count > 0 && kit == null;
    return KitScaffold(
      title: 'Games Library',
      subtitle: count == 0 ? null : (count == 1 ? '1 console' : '$count consoles'),
      icon: Icons.videogame_asset,
      glyph: PixelIcons.games,
      area: AppArea.games,
      padding: EdgeInsets.zero,
      actions: [
        if (launcherMode && appState.consolesList.isNotEmpty)
          IconButton(
            icon: Icon(Icons.sports_esports_rounded, color: ownedOnly ? StyleTokens.of(context).accent : null),
            tooltip: ownedViewLabel,
            isSelected: ownedOnly,
            onPressed: toggleOwned,
          ),
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

  /// The Classic views. Each lets a console be moved: the lifted one rises
  /// (the cover flow's centre card, a list row, a grid tile).
  Widget _viewFor(BuildContext context, ViewMode mode, List<MenuTile> tiles) {
    final reorder = MenuReorderScope.of(context);
    switch (mode) {
      case ViewMode.coverflow:
        return CoverFlow(
          items: [
            for (final t in tiles)
              CoverFlowItem(
                face: MenuLiftLook(
                  lifted: reorder?.isLifted(t.id) ?? false,
                  look: LiftLook.raised,
                  radius: 20,
                  // The cards slide under a finger: a drag moves the lifted one a place a step.
                  child: GestureDetector(
                    onLongPressStart: (_) => reorder?.lift(t.id, touch: true, steps: Axis.horizontal),
                    child: MenuTileFace(tile: t, showLabel: false),
                  ),
                ),
                label: t.label,
                onTap: t.onTap,
              ),
          ],
          jumpTo: reorder?.moverIndex,
          onKey: reorder == null ? null : (centre, e) => reorder.handleKey(tiles[centre].id, e, const MenuMove.row()),
        );
      case ViewMode.list:
        return MenuMoveLayout(
          move: const MenuMove.list(),
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: tiles.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final t = tiles[i];
              return MenuReorderTarget(
                tile: t,
                look: LiftLook.raised,
                radius: 14,
                // Its own Material, so the row's colour rises with it.
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    tileColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    leading: SizedBox(width: 52, height: 52, child: MenuTileFace(tile: t, showLabel: false)),
                    title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: t.onTap,
                  ),
                ),
              );
            },
          ),
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
      id: console.id,
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
