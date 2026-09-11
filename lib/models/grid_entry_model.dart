import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

/// Um arquivo de uma fonte que o matcher casou com um `PackGame`.
///
/// É o `GameMatch` da fatia 2 virado do avesso: lá a chave é o nome do
/// arquivo e o valor é o jogo; aqui a chave é o jogo e isto é um dos valores.
/// O tamanho vem da listagem, não do matcher.
@immutable
class MatchedSource {
  final String filename;

  /// De qual fonte veio. Nesta fatia é sempre a listagem do console; na
  /// fatia 4 passa a ser o id do addon, e é por isso que o campo já existe.
  final String sourceId;
  final MatchConfidence confidence;

  /// Bytes, ou zero quando a listagem não declara tamanho.
  final int size;

  /// A URL de download. Fica nula quando a fonte não a fornece de imediato.
  final String? url;

  const MatchedSource({
    required this.filename,
    required this.sourceId,
    required this.confidence,
    required this.size,
    this.url,
  });
}

/// Uma entrada da grade em MODO PACK: um jogo canônico e as fontes dele.
///
/// A grade desenha isto, e não `Game`. Ver "Terceira decisão travada" no
/// plano da fatia 3.
@immutable
class PackGridEntry {
  final PackGame game;
  final List<MatchedSource> sources;

  const PackGridEntry({required this.game, this.sources = const []});

  /// O único eixo que o tile pinta. Ver "Armadilha de leitura": o tile mostra
  /// **disponibilidade**, nunca confiança.
  bool get hasSource => sources.isNotEmpty;

  int get sourceCount => sources.length;

  /// A chave de seleção em MODO PACK. O prefixo `pack:` é obrigatório porque
  /// `Game.gameId` e `PackGame.id` não são provadamente disjuntos, e `:` não
  /// pode aparecer num id gerado por `_nameToId` (`catalog_service.dart:61-63`).
  String get selectionKey => 'pack:${game.id}';
}
