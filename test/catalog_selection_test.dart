import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';

import 'support/favorites_stub.dart';

void main() {
  test('clearSelection wipes the whole selection', () {
    final container = ProviderContainer(overrides: [withoutFavoritesDisk]);
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    notifier.selectGame('snes/a.zip');
    notifier.selectGame('snes/b.zip');
    expect(container.read(catalogProvider).selectedGames,
        {'snes/a.zip', 'snes/b.zip'});

    notifier.clearSelection();

    expect(container.read(catalogProvider).selectedGames, isEmpty);
  });

  test('clearSelection emits no state when the selection is already empty', () {
    final container = ProviderContainer(overrides: [withoutFavoritesDisk]);
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    var emissions = 0;
    container.listen(catalogProvider, (_, __) => emissions++);

    notifier.clearSelection();

    // The whole grid rebuilds on every catalogProvider emission; clearing an
    // already-empty selection must not cost that.
    expect(emissions, 0);
  });
}
