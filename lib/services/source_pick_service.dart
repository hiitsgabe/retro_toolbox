import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';

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
