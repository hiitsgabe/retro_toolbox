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
