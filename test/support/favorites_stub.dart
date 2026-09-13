import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/favorites_model.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';

/// In-memory favorites: no disk, no `async` that outlives the test. The real
/// `FavoritesNotifier` loads from `path_provider` in its constructor, whose
/// await completes after teardown and throws use-after-dispose.
class InMemoryFavoritesNotifier extends StateNotifier<Favorites>
    implements FavoritesNotifier {
  InMemoryFavoritesNotifier()
      : super(Favorites(lastUpdated: DateTime.fromMillisecondsSinceEpoch(0)));

  @override
  Future<void> toggleFavorite(String gameId) async {
    final ids = Set<String>.from(state.gameIds);
    ids.contains(gameId) ? ids.remove(gameId) : ids.add(gameId);
    state = state.copyWith(gameIds: ids);
  }

  @override
  Future<void> addFavorite(String gameId) async {
    state = state.copyWith(gameIds: Set<String>.from(state.gameIds)..add(gameId));
  }

  @override
  Future<void> removeFavorite(String gameId) async {
    state = state.copyWith(gameIds: Set<String>.from(state.gameIds)..remove(gameId));
  }

  @override
  Future<void> clearFavorites() async {
    state = state.copyWith(gameIds: {});
  }

  @override
  Future<String> exportFavorites() async => 'stub';

  @override
  Future<void> importFavorites(String slug, {bool merge = true}) async {}

  @override
  Future<void> deleteExport() async {}

  @override
  bool isFavorite(String gameId) => state.isFavorite(gameId);
}

/// Add this to the `overrides` of every test that builds the real
/// `catalogProvider`, in a container or a `ProviderScope`.
final withoutFavoritesDisk =
    favoritesProvider.overrideWith((_) => InMemoryFavoritesNotifier());
