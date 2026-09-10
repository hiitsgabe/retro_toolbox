import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/favorites_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';

// Stub que não toca disco e não dispara async após dispose.
class _NoOpFavoritesNotifier extends StateNotifier<Favorites>
    implements FavoritesNotifier {
  _NoOpFavoritesNotifier()
      : super(Favorites(lastUpdated: DateTime.fromMillisecondsSinceEpoch(0)));

  @override
  Future<void> toggleFavorite(String gameId) async {}
  @override
  Future<void> addFavorite(String gameId) async {}
  @override
  Future<void> removeFavorite(String gameId) async {}
  @override
  Future<void> clearFavorites() async {}
  @override
  Future<String> exportFavorites() async => '';
  @override
  Future<void> importFavorites(String slug, {bool merge = true}) async {}
  @override
  Future<void> deleteExport() async {}
  @override
  bool isFavorite(String gameId) => false;
}

ProviderContainer _container() {
  final c = ProviderContainer(overrides: [
    favoritesProvider
        .overrideWith((_) => _NoOpFavoritesNotifier()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  // O CatalogNotifier escuta favoritesProvider no construtor, e o
  // FavoritesService toca disco. Sem binding isso explode antes do teste.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearSelection zera a seleção inteira', () {
    final container = _container();
    final notifier = container.read(catalogProvider.notifier);

    notifier.selectGame('snes/a.zip');
    notifier.selectGame('snes/b.zip');
    expect(container.read(catalogProvider).selectedGames,
        {'snes/a.zip', 'snes/b.zip'});

    notifier.clearSelection();

    expect(container.read(catalogProvider).selectedGames, isEmpty);
  });

  test('clearSelection não emite estado quando a seleção já está vazia', () {
    final container = _container();
    final notifier = container.read(catalogProvider.notifier);

    var emissions = 0;
    container.listen(catalogProvider, (_, __) => emissions++);

    notifier.clearSelection();

    // A grade inteira reconstrói a cada emissão do catalogProvider. Limpar
    // uma seleção que já está vazia não pode custar isso.
    expect(emissions, 0);
  });
}
