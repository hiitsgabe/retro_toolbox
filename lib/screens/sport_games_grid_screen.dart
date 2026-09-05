import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/patcher_info.dart';
import 'package:roms_downloader/providers/sports_provider.dart';
import 'package:roms_downloader/screens/sport_patcher_wizard_screen.dart';
import 'package:roms_downloader/widgets/menu_grid/menu_grid.dart';
import 'package:roms_downloader/widgets/menu_grid/sport_slug.dart';

/// Level 2 of the Sports flow: the games for one group — either a [platform] or
/// a [sport], whichever the level-1 toggle drilled in by. Reads the cached
/// patcher list and filters; no refetch. Tapping a game opens its wizard.
class SportGamesGridScreen extends ConsumerWidget {
  final String? platform;
  final String? sport;
  const SportGamesGridScreen({super.key, this.platform, this.sport})
      : assert(platform != null || sport != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patchers = ref.watch(patchersProvider);
    final byPlatform = platform != null;
    final games = (patchers.valueOrNull ?? const <PatcherInfo>[])
        .where((p) => byPlatform ? p.platform == platform : p.sport == sport)
        .toList();
    final title = byPlatform ? platformLabel(platform!) : _cap(sport!);
    final tiles = [
      for (final info in games)
        MenuTile(
          label: gameName(info),
          // Show the axis the grid isn't grouped by, so each card still
          // identifies both sport and console.
          subtitle: byPlatform ? _cap(info.sport) : platformLabel(info.platform),
          icon: sportIcon(info.sport),
          accentColor: sportBrandColor(info.sport),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SportPatcherWizardScreen(info: info)),
          ),
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: tiles.isEmpty
          ? const Center(child: Text('No games here.'))
          : MenuGrid(tiles: tiles),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
