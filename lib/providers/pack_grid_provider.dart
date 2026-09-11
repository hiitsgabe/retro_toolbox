import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/services/source_index.dart';

/// Os dois modos de grade da seção 7 do spec de arquitetura.
enum GridMode {
  /// A grade de hoje: um tile por arquivo da listagem.
  source,

  /// A grade nova: um tile por jogo do pacote.
  pack,
}

/// O console selecionado, na forma que o provider de pacote entende.
///
/// Este é o seam de teste: sobrescreva **este** provider, nunca o
/// `appStateProvider`, que faz IO de disco e de rede no construtor.
///
/// Nota sobre colisão de chave, que é a "Quarta decisão travada" do plano da
/// fatia 3: a chave de seleção em MODO PACK é `'pack:${packGame.id}'`. O `:`
/// não pode sair de `CatalogService._nameToId` (`catalog_service.dart:61-63`),
/// então ela não colide com `Game.gameId`. O único caminho de colisão é um
/// `consoles.json` no formato de mapa legado (`catalog_service.dart:95-96`),
/// que usa a chave do mapa verbatim: um console escrito à mão com id
/// `pack:snes` colidiria. É edge conhecido e aceito, sem código de defesa.
final packTargetProvider = Provider<PackTarget?>((ref) {
  final console = ref.watch(appStateProvider.select((s) => s.selectedConsole));
  if (console == null) return null;
  return PackTarget(console.id, console.name);
});

/// A listagem do console. Seam de teste pelo mesmo motivo acima.
final catalogGamesProvider =
    Provider<List<Game>>((ref) => ref.watch(catalogProvider.select((s) => s.games)));

/// O texto da caixa de busca do header. A mesma caixa dos dois modos: o que
/// muda é só quem consome. Ver "Quinta decisão travada" no plano.
final gridSearchQueryProvider =
    Provider<String>((ref) => ref.watch(catalogProvider.select((s) => s.filterText)));

/// Qual grade desenhar.
///
/// **Tudo que não é "o pacote chegou" é MODO FONTE**: sem console, pacote
/// carregando, console sem pacote, erro de rede. O MODO FONTE é o app de hoje,
/// então degradar para ele nunca é regressão, e essa é a única razão de este
/// provider ser síncrono em vez de devolver `AsyncValue`.
final gridModeProvider = Provider<GridMode>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return GridMode.source;
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  return pack == null ? GridMode.source : GridMode.pack;
});

/// O índice invertido do console atual. Null enquanto não há matcher.
///
/// Reconstrói quando a listagem muda, o que acontece uma vez por carga de
/// catálogo. **Não** reconstrói a cada tecla digitada: a busca é aplicada
/// depois, no provider de entradas.
final sourceIndexProvider = Provider<SourceIndex?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  final matcher = ref.watch(packMatcherProvider(target)).valueOrNull;
  if (matcher == null) return null;
  return SourceIndex.build(matcher, <SourceFile>[
    for (final game in ref.watch(catalogGamesProvider))
      (filename: game.filename, sourceId: kBuiltinSourceId, size: game.size, url: game.url),
  ]);
});

/// O que a grade de MODO PACK desenha, já filtrado e ordenado.
///
/// Em MODO FONTE ninguém lê este provider, e ele devolve lista vazia sem
/// custo, porque `metadataPackProvider` já resolveu para null.
final packGridEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return const [];
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  if (pack == null) return const [];

  final index = ref.watch(sourceIndexProvider);
  return filterPackEntries([
    for (final game in pack.games)
      PackGridEntry(game: game, sources: index?.sourcesFor(game.id) ?? const []),
  ], ref.watch(gridSearchQueryProvider));
});
