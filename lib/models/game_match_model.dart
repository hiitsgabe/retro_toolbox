import 'package:roms_downloader/models/metadata_pack_model.dart';

/// Como o match foi obtido. A ordem da declaração é a ordem de preferência: o
/// matcher tenta de cima para baixo e para no primeiro que resolve.
enum MatchTier {
  /// O CRC32 bateu com um dump do pacote. É o único tier que não erra.
  checksum,

  /// `norm` do nome do arquivo é igual ao `norm` do nome de um dump.
  exactName,

  /// `canon` do nome do arquivo é igual ao `canon` de um jogo do pacote.
  /// Casa variantes de região e revisão, que é o caso comum.
  canonicalName,

  /// Similaridade de edição acima do corte. Erra: a seção 5.9 do spec mediu
  /// pelo menos 4 alvos errados em 26 casos, contra 0.63% de ganho de
  /// cobertura. Existe porque o ganho é de graça, e nunca vira certeza.
  fuzzyName,
}

/// O que a tela pode afirmar. Deriva do tier e existe para a fatia 3 não ter
/// que redecidir isso em cada widget.
enum MatchConfidence { confirmed, likely, guess }

extension MatchTierConfidence on MatchTier {
  MatchConfidence get confidence => switch (this) {
        MatchTier.checksum => MatchConfidence.confirmed,
        MatchTier.exactName => MatchConfidence.likely,
        MatchTier.canonicalName => MatchConfidence.likely,
        MatchTier.fuzzyName => MatchConfidence.guess,
      };
}

/// Um arquivo da fonte atribuído a um jogo do pacote.
///
/// [dump] só vem preenchido quando o tier identifica **qual** versão, ou seja
/// no `checksum` e no `exactName`. Os tiers canônico e fuzzy resolvem o jogo,
/// não a versão, e deixam [dump] nulo de propósito.
class GameMatch {
  final PackGame game;
  final MatchTier tier;

  /// O nome do arquivo na fonte, cru, do jeito que a fonte deu.
  final String sourceName;

  final PackDump? dump;

  /// 0 a 100. Só o tier fuzzy usa; os outros ficam em 100.
  final double score;

  const GameMatch({
    required this.game,
    required this.tier,
    required this.sourceName,
    this.dump,
    this.score = 100,
  });

  MatchConfidence get confidence => tier.confidence;

  @override
  String toString() => 'GameMatch(${game.id}, ${tier.name}, $score)';
}
