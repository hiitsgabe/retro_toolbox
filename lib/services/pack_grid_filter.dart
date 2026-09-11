import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Busca e ordenação da grade em MODO PACK.
///
/// Dart puro e síncrono de propósito. O MODO FONTE usa `FilteringService` num
/// isolate porque lá o filtro é caro (regex de região, revisão, agrupamento de
/// revisão mais recente). Aqui é um `contains` sobre alguns milhares de
/// títulos já normalizados; mandar isso para um isolate custaria mais em
/// serialização do que o próprio filtro.
///
/// **Não** filtra por região, revisão ou qualidade de dump. Ver "Quinta
/// decisão travada" no plano da fatia 3: essas são propriedades de uma versão,
/// e em MODO PACK a grade não tem versão.
///
/// **Não** filtra por disponibilidade. A grade mostra o pacote inteiro e marca
/// a exceção; esconder o que não tem fonte é o oposto do que o spec pede.
List<PackGridEntry> filterPackEntries(List<PackGridEntry> entries, String query) {
  final needle = norm(query);
  final out = needle.isEmpty
      ? [...entries]
      : entries.where((entry) => norm(entry.game.title).contains(needle)).toList();

  out.sort((a, b) {
    final byTitle = norm(a.game.title).compareTo(norm(b.game.title));
    // Desempate estável por id: dois jogos de título igual existem (uma
    // reedição, um homônimo de região), e sem isto a ordem da grade mudaria
    // de uma reconstrução para a outra.
    return byTitle != 0 ? byTitle : a.game.id.compareTo(b.game.id);
  });
  return out;
}

/// As entradas que o usuário marcou, na ordem em que [entries] veio.
///
/// A ordem é a da grade, e não a ordem em que o usuário tocou os tiles,
/// porque é a lista da grade que ele acabou de ver.
///
/// Ignora chave desconhecida em silêncio. É o comportamento certo aqui: as
/// duas causas reais, um pacote republicado com slug novo e uma chave do
/// outro modo, não são erro do usuário e não têm o que ser dito sobre elas.
List<PackGridEntry> entriesForSelection(List<PackGridEntry> entries, Set<String> keys) =>
    [for (final entry in entries) if (keys.contains(entry.selectionKey)) entry];

/// As chaves de seleção que pertencem ao modo corrente.
///
/// A seleção é um `Set<String>` único para os dois modos (ver "Quarta decisão
/// travada"), e existe uma janela real em que os dois convivem no mesmo
/// console: o catálogo carrega do disco em milissegundos e o pacote chega da
/// rede segundos depois. Quem marcou arquivos nesse intervalo vê a grade
/// virar MODO PACK com as chaves de MODO FONTE ainda lá dentro. Sem esta
/// função a barra roxa diria "3 selecionados" e o botão Baixar não faria
/// nada, em silêncio.
///
/// **Não** limpa a seleção do outro modo, de propósito: o console é o mesmo,
/// e se o pacote falhar e o modo cair de volta para FONTE a marcação do
/// usuário ainda está lá. Quem limpa de verdade é a troca de console, em
/// `CatalogNotifier.loadCatalog` (`catalog_provider.dart:53`).
Set<String> selectionKeysFor(Set<String> keys, {required bool pack}) =>
    {for (final key in keys) if (key.startsWith(kPackSelectionPrefix) == pack) key};
