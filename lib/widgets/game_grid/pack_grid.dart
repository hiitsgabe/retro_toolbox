import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/owned_games_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

/// The PACK MODE grid: one tile per game in the pack.
class PackGrid extends ConsumerWidget {
  /// Called on a short tap of a tile. The grid does not know `Navigator`:
  /// `HomeScreen` pushes the detail route.
  final void Function(PackGridEntry entry) onOpenGame;

  const PackGrid({super.key, required this.onOpenGame});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(packGridEntriesProvider);
    final index = ref.watch(sourceIndexProvider);
    final selected = ref.watch(catalogProvider.select((s) => s.selectedGames));
    // While the library scan is unresolved the set is empty and no tile gets a
    // border.
    final owned = ref.watch(ownedGameIdsProvider).valueOrNull ?? const <String>{};
    final catalogNotifier = ref.read(catalogProvider.notifier);

    final selectionActive = selected.isNotEmpty;

    final noCoverage = (index?.matchedGameCount ?? 0) == 0;

    return Column(
      children: [
        if (noCoverage) const _NoCoverageBanner(),
        Expanded(
          child: entries.isEmpty
              ? const _SearchEmpty()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    // Fixed aspect ratio: pack covers share one origin and are
                    // already consistent, so measuring the first one would cost
                    // an image round-trip per console switch for nothing.
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return PackGridItem(
                        key: ValueKey(entry.selectionKey),
                        title: entry.game.title,
                        coverUrl: entry.game.cover,
                        hasSource: entry.hasSource,
                        isOwned: owned.contains(entry.game.id),
                        isSelected: selected.contains(entry.selectionKey),
                        selectionActive: selectionActive,
                        onTap: () => onOpenGame(entry),
                        onLongPress: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                        onToggleSelection: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _NoCoverageBanner extends StatelessWidget {
  const _NoCoverageBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No source covers this console',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Games show up for browsing, but there is nothing to download.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No game with that name',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
