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
      (filename: game.filename, sourceId: game.sourceId, size: game.size, url: game.url),
  ]);
});

/// Todos os jogos do pacote com as fontes casadas, ordenados, **sem** a busca
/// aplicada.
///
/// É daqui que o lote lê. A grade lê do filtrado logo abaixo. A separação não
/// é enfeite: a seleção não é a tela, e um lote que lesse da lista filtrada
/// perderia os jogos que o usuário marcou antes de digitar na busca.
///
/// Como não depende de `gridSearchQueryProvider`, este provider é construído
/// uma vez por carga de catálogo e não a cada tecla digitada. O filtro por
/// tecla passa a rodar sobre uma lista já ordenada, o que é mais barato que
/// a versão anterior, que remontava as entradas do zero a cada letra.
final allPackEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return const [];
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  if (pack == null) return const [];

  final index = ref.watch(sourceIndexProvider);
  // Busca vazia: `filterPackEntries` não filtra nada e serve só para ordenar.
  // A ordenação mora lá porque a grade e o lote têm que concordar sobre ela.
  return filterPackEntries([
    for (final game in pack.games)
      PackGridEntry(game: game, sources: index?.sourcesFor(game.id) ?? const []),
  ], '');
});

/// O que a grade de MODO PACK desenha: o de cima, com a busca do header.
///
/// Em MODO FONTE ninguém lê este provider, e ele devolve lista vazia sem
/// custo, porque `metadataPackProvider` já resolveu para null.
final packGridEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  return filterPackEntries(
    ref.watch(allPackEntriesProvider),
    ref.watch(gridSearchQueryProvider),
  );
});

/// A região preferida do usuário, lida do filtro que já existe.
///
/// É seam de teste, como `catalogGamesProvider` e `gridSearchQueryProvider`:
/// sobrescreva **este** provider nos testes, nunca o `catalogProvider`.
final preferredRegionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(catalogProvider.select((state) => state.filter.regions));
});

/// Como uma fonte vira o `Game` que entra na fila.
///
/// Nesta fatia toda fonte veio da listagem do console, então resolver é achar
/// de volta o `Game` pelo nome do arquivo. Na fatia 4 quem responde é o addon,
/// e este provider passa a consultá-lo. `planFromEntries` não precisa saber
/// de nenhum dos dois.
final gameResolverProvider = Provider<GameResolver>((ref) {
  final byFilename = <String, Game>{};
  for (final game in ref.watch(catalogGamesProvider)) {
    // `putIfAbsent`: se dois arquivos da listagem tiverem o mesmo nome, o
    // primeiro do catálogo vence, que é a mesma ordem que `SourceIndex.build`
    // já usa. Duas respostas diferentes para o mesmo nome seria pior.
    byFilename.putIfAbsent(game.filename, () => game);
  }
  return (source) => byFilename[source.filename];
});
