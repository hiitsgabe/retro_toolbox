import 'package:retro_toolbox/utils/handheld.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/screens/sport_games_grid_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Level 1 of the Sports flow: cards grouped by console (default) or by sport;
/// the action bar's button (Y) switches the grouping. Tapping a card drills
/// into that group's games.
class SportsGridScreen extends ConsumerStatefulWidget {
  const SportsGridScreen({super.key});

  /// The patchers' source: where help adding games goes.
  static final contributeUri = Uri.parse('https://github.com/hiitsgabe/retro_roster_patcher');

  @override
  ConsumerState<SportsGridScreen> createState() => _SportsGridScreenState();
}

class _SportsGridScreenState extends ConsumerState<SportsGridScreen> {
  bool _bySport = false; // console grouping is the default

  @override
  Widget build(BuildContext context) {
    final patchers = ref.watch(patchersProvider);
    final list = patchers.valueOrNull ?? const <PatcherInfo>[];
    return KitScaffold(
      title: 'Sports',
      subtitle: 'Update rosters in classic games',
      icon: Icons.sports_score,
      glyph: PixelIcons.sports,
      area: AppArea.sports,
      padding: EdgeInsets.zero,
      info: InfoButton(
        icon: Icons.sports_score,
        title: 'Sports',
        text: 'Update the rosters of classic sports games with real, current teams and players, then patch your own ROM. '
            'Pick a console or sport, choose a game, edit the squads, and go.\n\n'
            'ALPHA. This is new and rough, so expect bugs, keep a backup of your ROM, and report anything odd.\n\n'
            'Only a handful of games are supported so far. If you know ROM formats or rosters, help add more: '
            'the patchers are open source (github.com/hiitsgabe/retro_roster_patcher).',
        learnMore: Handheld.current ? null : SportsGridScreen.contributeUri,
      ),
      actionBar: list.isEmpty
          ? null
          : ActionBar(
              secondary: KitAction(
                _bySport ? 'By console' : 'By sport',
                () => setState(() => _bySport = !_bySport),
                icon: _bySport ? Icons.videogame_asset : Icons.sports,
                button: PadButton.y,
              ),
            ),
      body: patchers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          line: "Couldn't load the game list. $e",
          action: KitAction('Retry', () => ref.invalidate(patchersProvider), icon: Icons.refresh),
        ),
        data: (list) {
          // Nothing failed: retrying would not help (the handheld hides some).
          if (list.isEmpty) return const EmptyState(icon: Icons.sports_score, glyph: PixelIcons.sports, line: 'No games for this device yet');
          return MenuGrid(key: ValueKey(_bySport), tiles: _bySport ? _sportTiles(list) : _consoleTiles(list));
        },
      ),
    );
  }

  List<MenuTile> _consoleTiles(List<PatcherInfo> list) {
    final platforms = <String>[];
    for (final p in list) {
      if (p.platform.isNotEmpty && !platforms.contains(p.platform)) platforms.add(p.platform);
    }
    return [
      for (final platform in platforms)
        MenuTile(
          label: platformLabel(platform),
          area: AppArea.sports,
          pixelIcon: PixelIcons.games,
          icon: Icons.videogame_asset,
          assetPath: platformLogoAsset(platform),
          accentColor: platformBrandColor(platform),
          brandLogo: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SportGamesGridScreen(platform: platform)),
          ),
        ),
    ];
  }

  List<MenuTile> _sportTiles(List<PatcherInfo> list) {
    final sports = <String>[];
    for (final p in list) {
      if (p.sport.isNotEmpty && !sports.contains(p.sport)) sports.add(p.sport);
    }
    return [
      for (final sport in sports)
        MenuTile(
          label: _cap(sport),
          area: AppArea.sports,
          pixelIcon: sportPixelIcon(sport),
          icon: sportIcon(sport),
          accentColor: sportBrandColor(sport),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SportGamesGridScreen(sport: sport)),
          ),
        ),
    ];
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
