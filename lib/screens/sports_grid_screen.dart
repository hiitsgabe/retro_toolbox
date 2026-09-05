import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:roms_downloader/models/patcher_info.dart';
import 'package:roms_downloader/providers/sports_provider.dart';
import 'package:roms_downloader/screens/sport_games_grid_screen.dart';
import 'package:roms_downloader/widgets/menu_grid/console_slug.dart';
import 'package:roms_downloader/widgets/menu_grid/menu_grid.dart';
import 'package:roms_downloader/widgets/menu_grid/sport_slug.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Level 1 of the Sports flow: cards grouped by console (default) or by sport,
/// toggled in the app bar. Tapping a card drills into that group's games.
class SportsGridScreen extends ConsumerStatefulWidget {
  const SportsGridScreen({super.key});

  @override
  ConsumerState<SportsGridScreen> createState() => _SportsGridScreenState();
}

class _SportsGridScreenState extends ConsumerState<SportsGridScreen> {
  bool _bySport = false; // console grouping is the default

  @override
  Widget build(BuildContext context) {
    final patchers = ref.watch(patchersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sports'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.videogame_asset), label: Text('Console')),
                ButtonSegment(value: true, icon: Icon(Icons.sports), label: Text('Sport')),
              ],
              selected: {_bySport},
              onSelectionChanged: (s) => setState(() => _bySport = s.first),
            ),
          ),
        ],
      ),
      body: patchers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _error('$e'),
        data: (list) {
          if (list.isEmpty) return _error('No patchers available.');
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: ToolDescription(
                  icon: Icons.sports_score,
                  text: 'Update the rosters of classic sports games with real, '
                      'current teams and players, then patch your own ROM. Pick a '
                      'console or sport, choose a game, edit the squads, and go.\n\n'
                      'ALPHA. This is new and rough, so expect bugs, keep a backup '
                      'of your ROM, and report anything odd.',
                ),
              ),
              MenuGrid(tiles: _bySport ? _sportTiles(list) : _consoleTiles(list), shrinkWrap: true),
              _contributeFooter(context),
            ],
          );
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
          icon: Icons.videogame_asset,
          assetPath: platformLogoAsset(platform),
          accentColor: platformBrandColor(platform),
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
          icon: sportIcon(sport),
          accentColor: sportBrandColor(sport),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SportGamesGridScreen(sport: sport)),
          ),
        ),
    ];
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _contributeFooter(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Only a handful of games are supported so far. If you know ROM '
                'formats or rosters, help add more. The patchers are open source.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://github.com/hiitsgabe/retro_roster_patcher'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.code, size: 16),
              label: const Text('Contribute'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _error(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.invalidate(patchersProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
}
