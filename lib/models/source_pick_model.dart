import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_model.dart';

/// O id de fonte das listagens que já vêm no `consoles.json`.
///
/// Nesta fatia só existe uma fonte por console, então o valor é constante. Na
/// fatia 4 ele vira o id do addon que serviu o arquivo, e é por isso que
/// [SourcePick.sourceId] e `MatchedSource.sourceId` são campos em vez de
/// serem implícitos.
///
/// Mora neste arquivo por uma razão de ordem, não de gosto: ele é o primeiro
/// arquivo Dart puro desta fatia a existir, e tanto `source_pick_service.dart`
/// (Task 6) quanto `pack_grid_provider.dart` (Task 10) precisam da constante.
/// Pô-la no provider arrastaria Riverpod para dentro de um serviço que roda
/// fora do Flutter; pô-la em `grid_entry_model.dart` a faria nascer três
/// Tasks depois do primeiro uso.
const kBuiltinSourceId = 'listagem';

/// Uma versão escolhida para um jogo, com o motivo escrito por extenso.
///
/// O motivo é obrigatório e não é decorativo: ele é a única coisa que separa
/// "o app escolheu por você" de "o app escolheu ao acaso" (spec de UI, seção 7).
@immutable
class SourcePick {
  /// A chave de seleção do jogo. Em MODO FONTE é `Game.gameId`; em MODO PACK
  /// é `'pack:${packGame.id}'`. A folha não precisa saber qual dos dois é.
  final String gameId;
  final String title;
  final String filename;

  /// Bytes. Zero quando a fonte não declara tamanho, e nesse caso a folha
  /// mostra o total como aproximado.
  final int size;

  /// De qual fonte veio. Nesta fatia é sempre [kBuiltinSourceId] e na fatia 4
  /// é o id do addon. É o que a linha "4.0 MB, Myrient" da seção 7 mostra, e
  /// é por isso que ele nasce aqui em vez de nascer na fatia 4.
  final String sourceId;
  final String reason;

  /// Marca o selo de incerteza da seção 6. É `true` quando a confiança do
  /// match é `guess`. O lote **não** verifica CRC antes de enfileirar.
  final bool uncertain;

  /// O que efetivamente vai para a fila. A folha nunca lê este campo: ela
  /// desenha os campos de exibição acima e devolve os picks inteiros.
  final Game game;

  const SourcePick({
    required this.gameId,
    required this.title,
    required this.filename,
    required this.size,
    required this.sourceId,
    required this.reason,
    required this.game,
    this.uncertain = false,
  });
}

/// Um jogo selecionado que não vai para a fila, com o motivo.
@immutable
class PickFailure {
  final String gameId;
  final String title;
  final String reason;

  const PickFailure({
    required this.gameId,
    required this.title,
    required this.reason,
  });
}

/// O que a folha de confirmação da seção 6 desenha: o que vai e o que não vai.
@immutable
class BatchPlan {
  final List<SourcePick> picks;
  final List<PickFailure> failures;

  const BatchPlan({this.picks = const [], this.failures = const []});

  int get totalBytes => picks.fold(0, (sum, pick) => sum + pick.size);

  int get uncertainCount => picks.where((pick) => pick.uncertain).length;

  /// Vazio de verdade: nada a baixar e nada a explicar. Um plano só de
  /// falhas **não** é vazio, porque a folha precisa abrir para dizer por quê.
  bool get isEmpty => picks.isEmpty && failures.isEmpty;

  /// Tira um item do lote. Devolve um plano novo; o original não muda.
  BatchPlan withoutPick(String gameId) => BatchPlan(
        picks: picks.where((pick) => pick.gameId != gameId).toList(),
        failures: failures,
      );
}
