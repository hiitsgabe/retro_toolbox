import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/app_state_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/owned_games_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';
import 'package:roms_downloader/widgets/menu_grid/cover_flow.dart';

/// The PACK MODE catalog, in whichever [ViewMode] the header toggle is on.
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

    // Same header toggle that drives SOURCE MODE. Reading it here is what makes
    // the button do anything at all in PACK MODE.
    final viewMode = ref.watch(viewModeProvider);

    PackGridItem tile(PackGridEntry entry, {double aspectRatio = 0.75}) => PackGridItem(
          key: ValueKey(entry.selectionKey),
          title: entry.game.title,
          coverUrl: entry.game.cover,
          hasSource: entry.hasSource,
          isOwned: owned.contains(entry.game.id),
          isSelected: selected.contains(entry.selectionKey),
          selectionActive: selectionActive,
          aspectRatio: aspectRatio,
          onTap: () => onOpenGame(entry),
          onLongPress: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
          onToggleSelection: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
        );

    return Column(
      children: [
        if (noCoverage) const _NoCoverageBanner(),
        Expanded(
          child: entries.isEmpty
              ? const _SearchEmpty()
              : switch (viewMode) {
                  ViewMode.grid => Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
                      child: GridView.builder(
                        padding: EdgeInsets.zero,
                        // Fixed aspect ratio: pack covers share one origin and
                        // are already consistent, so measuring the first one
                        // would cost an image round-trip per console switch for
                        // nothing.
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.75,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => tile(entries[i]),
                      ),
                    ),
                  ViewMode.list => ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final entry = entries[i];
                        return _PackRow(
                          key: ValueKey(entry.selectionKey),
                          entry: entry,
                          isOwned: owned.contains(entry.game.id),
                          isSelected: selected.contains(entry.selectionKey),
                          selectionActive: selectionActive,
                          onTap: () => onOpenGame(entry),
                          onToggleSelection: () =>
                              catalogNotifier.toggleGameSelection(entry.selectionKey),
                        );
                      },
                    ),
                  // The cover flow builds every face up front, so it is capped.
                  // Browsing thousands of covers by drag is not how anyone finds
                  // a game; the search field is.
                  ViewMode.coverflow => CoverFlow(
                      aspectRatio: _coverFlowAspectRatio,
                      items: [
                        for (final entry in entries.take(_coverFlowLimit))
                          CoverFlowItem(
                            face: tile(entry, aspectRatio: _coverFlowAspectRatio),
                            label: entry.game.title,
                          ),
                      ],
                    ),
                },
        ),
      ],
    );
  }
}

const _coverFlowAspectRatio = 0.72;

/// How many covers the flow holds. Above this the drag stops being a way to
/// find anything and the build cost stops paying for itself.
const _coverFlowLimit = 200;

/// One pack game as a list row: thumbnail, title, and whether it can be
/// downloaded. Tap opens the detail, long press starts or extends a selection.
class _PackRow extends StatelessWidget {
  final PackGridEntry entry;
  final bool isOwned;
  final bool isSelected;
  final bool selectionActive;
  final VoidCallback onTap;
  final VoidCallback onToggleSelection;

  const _PackRow({
    super.key,
    required this.entry,
    required this.isOwned,
    required this.isSelected,
    required this.selectionActive,
    required this.onTap,
    required this.onToggleSelection,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cover = entry.game.cover;

    return ListTile(
      onTap: onTap,
      onLongPress: onToggleSelection,
      selected: isSelected,
      selectedTileColor: scheme.primary.withValues(alpha: 0.12),
      leading: SizedBox(
        width: 40,
        height: 54,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: cover == null
              ? Container(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(Icons.videogame_asset_rounded, size: 18, color: scheme.primary),
                )
              : CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  errorWidget: (context, _, __) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.videogame_asset_rounded, size: 18, color: scheme.primary),
                  ),
                  errorListener: (_) {},
                ),
        ),
      ),
      title: Text(entry.game.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: entry.hasSource
          ? null
          : Text(
              'No source has this game',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
      trailing: selectionActive
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onToggleSelection(),
              shape: const CircleBorder(),
            )
          : isOwned
              ? Icon(Icons.check_circle_rounded, size: 18, color: scheme.secondary)
              : null,
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
