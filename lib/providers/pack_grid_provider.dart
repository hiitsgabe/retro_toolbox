import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/services/source_index.dart';
import 'package:roms_downloader/services/source_pick_service.dart';

/// The two grid modes.
enum GridMode {
  /// One tile per listing file.
  source,

  /// One tile per pack game.
  pack,
}

/// The selected console, in the shape the pack provider understands.
/// Test seam: override this provider, never `appStateProvider`.
final packTargetProvider = Provider<PackTarget?>((ref) {
  final console = ref.watch(appStateProvider.select((s) => s.selectedConsole));
  if (console == null) return null;
  return PackTarget(console.id, console.name);
});

/// The console listing. Test seam.
final catalogGamesProvider =
    Provider<List<Game>>((ref) => ref.watch(catalogProvider.select((s) => s.games)));

/// The header search box text, shared by both modes.
final gridSearchQueryProvider =
    Provider<String>((ref) => ref.watch(catalogProvider.select((s) => s.filterText)));

/// Which grid to draw. Anything but "the pack arrived" degrades to source
/// mode: no console, pack loading, console without pack, network error.
final gridModeProvider = Provider<GridMode>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return GridMode.source;
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  return pack == null ? GridMode.source : GridMode.pack;
});

/// The inverted index for the current console. Null while there is no matcher.
/// Rebuilds when the listing changes, not on every keystroke.
final sourceIndexProvider = Provider<SourceIndex?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  final matcher = ref.watch(packMatcherProvider(target)).valueOrNull;
  if (matcher == null) return null;
  return SourceIndex.build(matcher, <SourceFile>[
    for (final game in ref.watch(catalogGamesProvider))
      (filename: game.filename, sourceId: game.sourceId, size: game.size, url: game.url),
  ]);
});

/// Every pack game with matched sources, sorted, without the search applied.
/// The batch reads from here; the grid reads from the filtered provider below.
/// A batch reading the filtered list would lose games selected before typing.
final allPackEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return const [];
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  if (pack == null) return const [];

  final index = ref.watch(sourceIndexProvider);
  // Empty query: `filterPackEntries` filters nothing and only sorts, where the
  // grid and the batch must agree on the order.
  return filterPackEntries([
    for (final game in pack.games)
      PackGridEntry(game: game, sources: index?.sourcesFor(game.id) ?? const []),
  ], '');
});

/// What the pack-mode grid draws: the above, with the header search applied.
final packGridEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  return filterPackEntries(
    ref.watch(allPackEntriesProvider),
    ref.watch(gridSearchQueryProvider),
  );
});

/// The user's preferred regions, read from the existing filter. Test seam:
/// override this provider, never `catalogProvider`.
final preferredRegionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(catalogProvider.select((state) => state.filter.regions));
});

/// How a source becomes the `Game` that enters the queue: find the `Game`
/// back by filename.
final gameResolverProvider = Provider<GameResolver>((ref) {
  final byFilename = <String, Game>{};
  for (final game in ref.watch(catalogGamesProvider)) {
    // `putIfAbsent`: on a duplicate filename the first catalog entry wins,
    // matching the order `SourceIndex.build` uses.
    byFilename.putIfAbsent(game.filename, () => game);
  }
  return (source) => byFilename[source.filename];
});
