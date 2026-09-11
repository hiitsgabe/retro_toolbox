import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Um arquivo cru de uma fonte, antes de o matcher opinar sobre ele.
///
/// É um registro e não uma classe porque não tem comportamento nenhum e
/// porque quem o produz muda por fatia: nesta é a listagem do console, na
/// fatia 4 é o addon. `pack_matcher.dart:25` já usa registro pelo mesmo motivo.
typedef SourceFile = ({String filename, String sourceId, int size, String? url});

/// Índice invertido: dado o id de um `PackGame`, quais arquivos existem.
///
/// O `PackMatcher` responde "que jogo é este arquivo". Isto responde
/// "que arquivos são este jogo", que é o que a grade pergunta.
///
/// Construa uma vez por console, em `build`, e guarde. Não construa dentro do
/// `build` de um widget: são milhares de chamadas de `match` por vez.
class SourceIndex {
  final Map<String, List<MatchedSource>> _byGameId;

  /// Nomes com extensão de ROM que o matcher não atribuiu a jogo nenhum.
  /// O que não é ROM nunca entra aqui: seria ruído de índice de listagem.
  final List<String> unmatched;

  const SourceIndex._(this._byGameId, this.unmatched);

  static SourceIndex build(PackMatcher matcher, List<SourceFile> files) {
    final byGameId = <String, List<MatchedSource>>{};
    final unmatched = <String>[];

    for (final file in files) {
      if (!hasRomExtension(file.filename)) continue;
      final match = matcher.match(file.filename);
      if (match == null) {
        unmatched.add(file.filename);
        continue;
      }
      byGameId.putIfAbsent(match.game.id, () => <MatchedSource>[]).add(MatchedSource(
            filename: file.filename,
            sourceId: file.sourceId,
            confidence: match.confidence,
            size: file.size,
            url: file.url,
          ));
    }

    return SourceIndex._(byGameId, unmatched);
  }

  /// As fontes daquele jogo, **na ordem da listagem**. Quem ordena por
  /// preferência é a regra de escolha (Task 14), não o índice.
  List<MatchedSource> sourcesFor(String gameId) => _byGameId[gameId] ?? const [];

  bool hasSource(String gameId) => _byGameId.containsKey(gameId);

  /// Quantos jogos do pacote têm ao menos uma fonte. É o que decide a faixa
  /// de estado vazio da Task 12.
  int get matchedGameCount => _byGameId.length;
}
