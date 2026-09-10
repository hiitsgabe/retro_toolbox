import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';

import 'support/favorites_stub.dart';

void main() {
  test('clearSelection zera a seleção inteira', () {
    final container = ProviderContainer(overrides: [semDiscoDeFavoritos]);
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    notifier.selectGame('snes/a.zip');
    notifier.selectGame('snes/b.zip');
    expect(container.read(catalogProvider).selectedGames,
        {'snes/a.zip', 'snes/b.zip'});

    notifier.clearSelection();

    expect(container.read(catalogProvider).selectedGames, isEmpty);
  });

  test('clearSelection não emite estado quando a seleção já está vazia', () {
    final container = ProviderContainer(overrides: [semDiscoDeFavoritos]);
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    var emissions = 0;
    container.listen(catalogProvider, (_, __) => emissions++);

    notifier.clearSelection();

    // A grade inteira reconstrói a cada emissão do catalogProvider. Limpar
    // uma seleção que já está vazia não pode custar isso.
    expect(emissions, 0);
  });
}
