import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/screens/sport_patcher_wizard_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';

/// Level 2 of the Sports flow: the games for one group, either a [platform] or
/// a [sport], whichever the level-1 toggle drilled in by. Reads the cached
/// patcher list and filters; no refetch. Tapping a game opens its wizard.
class SportGamesGridScreen extends ConsumerWidget {
  final String? platform;
  final String? sport;
  const SportGamesGridScreen({super.key, this.platform, this.sport}) : assert(platform != null || sport != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patchers = ref.watch(patchersProvider);
    final byPlatform = platform != null;
    final games = (patchers.valueOrNull ?? const <PatcherInfo>[]).where((p) => byPlatform ? p.platform == platform : p.sport == sport).toList();
    final title = byPlatform ? platformLabel(platform!) : _cap(sport!);
    final tiles = [
      for (final info in games)
        MenuTile(
          id: info.gameId,
          label: gameName(info),
          // Show the axis the grid isn't grouped by, so each card still
          // identifies both sport and console.
          subtitle: byPlatform ? _cap(info.sport) : platformLabel(info.platform),
          area: AppArea.sports,
          pixelIcon: sportPixelIcon(info.sport),
          icon: sportIcon(info.sport),
          accentColor: sportBrandColor(info.sport),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SportPatcherWizardScreen(info: info)),
          ),
        ),
    ];
    return KitScaffold(
      title: title,
      subtitle: tiles.isEmpty ? null : '${tiles.length} ${tiles.length == 1 ? 'game' : 'games'}',
      icon: byPlatform ? Icons.videogame_asset : sportIcon(sport!),
      glyph: byPlatform ? PixelIcons.games : sportPixelIcon(sport!),
      area: AppArea.sports,
      padding: EdgeInsets.zero,
      body: tiles.isEmpty
          ? const EmptyState(icon: Icons.sports_score, glyph: PixelIcons.sports, line: 'No games here.')
          : MenuGrid(menuId: byPlatform ? 'sport-games:platform:$platform' : 'sport-games:sport:$sport', tiles: tiles),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
