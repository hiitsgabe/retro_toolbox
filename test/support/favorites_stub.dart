import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/favorites_model.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';

/// Favoritos em memória, sem disco e sem `async` que sobreviva ao teste.
///
/// O `FavoritesNotifier` de verdade chama `_loadFavorites()` no construtor,
/// que vai ao `path_provider`. Em teste isso dá `MissingPluginException`, e
/// se você calar o canal, dá `Bad state: Tried to use FavoritesNotifier
/// after dispose` porque o `await` completa depois do teardown.
///
/// Guarda favorito de verdade, e não é no-op: as Tasks 15 e 18 apertam o
/// coração e esperam o ícone virar.
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

/// Ponha isto na lista de `overrides` de todo teste que construa
/// `catalogProvider` de verdade, em container ou em `ProviderScope`.
final semDiscoDeFavoritos =
    favoritesProvider.overrideWith((_) => InMemoryFavoritesNotifier());
