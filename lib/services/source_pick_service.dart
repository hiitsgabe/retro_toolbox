import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_metadata_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/utils/title_metadata_parser.dart';

/// O plano de lote do MODO FONTE.
///
/// Não há escolha a fazer aqui: cada `Game` selecionado já é um arquivo, e
/// todo arquivo da listagem existe. Por isso nenhum pick é incerto e a lista
/// de falhas é sempre vazia.
///
/// A regra de verdade da seção 6 do spec de UI, com região, revisão,
/// confiança e prioridade de addon, mora em `planFromEntries` (Task 14) e só
/// tem sujeito em MODO PACK, onde existe mais de uma versão do mesmo jogo.
BatchPlan planFromGames(List<Game> games) {
  return BatchPlan(
    picks: [
      for (final game in games)
        SourcePick(
          gameId: game.gameId,
          title: game.displayTitle,
          filename: game.filename,
          size: game.size,
          sourceId: kBuiltinSourceId,
          reason: 'você escolheu este arquivo',
          game: game,
        ),
    ],
  );
}

/// Como quem chama transforma uma fonte no `Game` que vai para a fila.
///
/// Nesta fatia é uma busca no catálogo por nome de arquivo (Task 20). Na
/// fatia 4 é o addon que responde. Devolve `null` quando a fonte não existe
/// mais, e aí o jogo vira `PickFailure` em vez de escolha.
typedef GameResolver = Game? Function(MatchedSource source);

typedef _Candidate = ({MatchedSource source, GameMetadata meta, Game game, int order});

/// A regra de escolha da seção 6 do spec de UI, na ordem dela: região
/// preferida, maior revisão, maior confiança, prioridade do addon.
///
/// É a mesma regra que escolhe o destaque da tela de detalhe. Uma regra só,
/// dois lugares: se você precisar de uma variação, mude esta função, não
/// escreva outra.
BatchPlan planFromEntries(
  List<PackGridEntry> entries, {
  required Set<String> preferredRegions,
  required GameResolver resolveGame,
  List<String> sourcePriority = const [],
}) {
  final picks = <SourcePick>[];
  final failures = <PickFailure>[];

  for (final entry in entries) {
    if (entry.sources.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'nenhuma fonte instalada tem este jogo',
      ));
      continue;
    }

    final candidates = <_Candidate>[];
    for (var i = 0; i < entry.sources.length; i++) {
      final source = entry.sources[i];
      final game = resolveGame(source);
      if (game == null) continue;
      candidates.add((
        source: source,
        meta: TitleMetadataParser.parseRomTitle(source.filename),
        game: game,
        order: i,
      ));
    }

    if (candidates.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'a fonte saiu da listagem antes de a fila começar',
      ));
      continue;
    }

    candidates.sort((a, b) => _compare(a, b, preferredRegions, sourcePriority));
    final winner = candidates.first;

    picks.add(SourcePick(
      gameId: entry.selectionKey,
      title: entry.game.title,
      filename: winner.source.filename,
      size: winner.source.size,
      sourceId: winner.source.sourceId,
      reason: _reason(winner, candidates, preferredRegions, sourcePriority),
      // O lote não verifica CRC antes de enfileirar (seção 6): ele marca o
      // palpite e deixa a rede de segurança para a verificação pós-download.
      uncertain: winner.source.confidence == MatchConfidence.guess,
      game: winner.game,
    ));
  }

  return BatchPlan(picks: picks, failures: failures);
}

int _compare(_Candidate a, _Candidate b, Set<String> preferred, List<String> priority) {
  final region = _regionRank(a, preferred).compareTo(_regionRank(b, preferred));
  if (region != 0) return region;

  // Invertido de propósito: revisão maior vem primeiro.
  final revision = _compareRevision(b.meta.revision, a.meta.revision);
  if (revision != 0) return revision;

  // `MatchConfidence` está declarado do mais confiável para o menos, então
  // o índice menor é o melhor.
  final confidence = a.source.confidence.index.compareTo(b.source.confidence.index);
  if (confidence != 0) return confidence;

  final addon = _priorityRank(a, priority).compareTo(_priorityRank(b, priority));
  if (addon != 0) return addon;

  // O desempate final é a ordem de chegada. Está aqui porque `List.sort` não
  // promete estabilidade, e um lote que muda de resultado entre duas rodadas
  // com a mesma entrada seria impossível de reportar como bug.
  return a.order.compareTo(b.order);
}

/// 0 é preferida, 1 não é.
///
/// Sem região no nome o candidato **não** perde, o que espelha
/// `filtering_service.dart:61-65`, onde metadados sem região passam pelo
/// filtro em vez de serem descartados.
int _regionRank(_Candidate candidate, Set<String> preferred) {
  if (preferred.isEmpty) return 0;
  if (candidate.meta.regions.isEmpty) return 0;
  return candidate.meta.regions.any(preferred.contains) ? 0 : 1;
}

/// Positivo quando [a] é mais nova que [b].
///
/// Comparação lexical, igual à de `filtering_service.dart:151-157`, com a
/// mesma limitação conhecida: `Rev A` ganha de `Rev 1`, e `1.10` perde de
/// `1.2`. Divergir daqui faria a grade e o lote discordarem.
int _compareRevision(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return -1;
  if (b.isEmpty) return 1;
  return a.compareTo(b);
}

int _priorityRank(_Candidate candidate, List<String> priority) {
  final index = priority.indexOf(candidate.source.sourceId);
  return index < 0 ? priority.length : index;
}

/// O motivo por extenso, que é o eixo em que o vencedor bateu o segundo
/// colocado. Obrigatório, não decorativo: é a única coisa que separa "o app
/// escolheu por você" de "o app escolheu ao acaso" (seção 7).
String _reason(
  _Candidate winner,
  List<_Candidate> ordered,
  Set<String> preferred,
  List<String> priority,
) {
  if (ordered.length == 1) return 'é a única fonte que tem este jogo';
  final runnerUp = ordered[1];

  if (_regionRank(winner, preferred) != _regionRank(runnerUp, preferred)) {
    final region = winner.meta.regions.where(preferred.contains).firstOrNull;
    return region == null
        ? 'escolhido pela sua região preferida'
        : 'escolhido pela sua região preferida ($region)';
  }

  // Se as revisões diferem, a do vencedor é a maior, senão ele não seria o
  // vencedor. Por isso dá para nomeá-la sem checar de novo.
  if (_compareRevision(winner.meta.revision, runnerUp.meta.revision) != 0) {
    return 'é a revisão mais nova (Rev ${winner.meta.revision})';
  }

  if (winner.source.confidence != runnerUp.source.confidence) {
    return 'é o casamento mais confiável entre as ${ordered.length} fontes';
  }

  if (_priorityRank(winner, priority) != _priorityRank(runnerUp, priority)) {
    return 'vem do addon de maior prioridade';
  }

  return 'empate entre ${ordered.length} fontes, ficou a primeira';
}
