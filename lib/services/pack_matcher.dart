import 'package:rapidfuzz/rapidfuzz.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Corte do tier 3, na escala 0 a 100 do `rapidfuzz.ratio`.
///
/// O valor vem da PoC, que usou `difflib.SequenceMatcher` com corte 0.90. A
/// seção 5.9 do spec registra que as duas métricas resolvem os mesmos 26
/// arquivos para os mesmos alvos neste corte, então a troca de biblioteca não
/// pede recalibragem.
const fuzzyCutoff = 90.0;

/// Casa um nome de arquivo com um jogo do metadata pack.
///
/// Três tiers de nome, na ordem da seção 5.5 do spec: nome exato, título
/// canônico, similaridade de edição. Mais um quarto eixo, o `matchCrc`, que é
/// o único que não erra.
///
/// Dart puro de propósito: `tool/verify_matcher.dart` roda esta classe fora do
/// Flutter. Não adicione import de `package:flutter`.
class PackMatcher {
  final MetadataPack pack;

  final Map<String, ({PackGame game, PackDump dump})> _byName = {};
  final Map<String, PackGame> _byCanon = {};
  final Map<String, List<String>> _byHead = {};

  PackMatcher(this.pack) {
    for (final game in pack.games) {
      for (final dump in game.dumps) {
        _byName.putIfAbsent(norm(dump.name), () => (game: game, dump: dump));
        final key = canon(dump.name);
        if (key.isEmpty) continue;
        _byCanon.putIfAbsent(key, () => game);
      }
    }
    for (final key in _byCanon.keys) {
      _byHead.putIfAbsent(_head(key), () => <String>[]).add(key);
    }
  }

  /// Os quatro primeiros caracteres do primeiro token. Mesmo balde da PoC:
  /// serve só para o tier 3 não varrer o pacote inteiro a cada falha.
  static String _head(String canonKey) {
    final first = canonKey.split(' ').first;
    return first.length <= 4 ? first : first.substring(0, 4);
  }

  /// Quantos jogos e quantas chaves canônicas o matcher indexou. Serve para o
  /// `tool/verify_matcher.dart` e para diagnóstico.
  int get indexedGames => pack.games.length;
  int get indexedCanonKeys => _byCanon.length;

  GameMatch? match(String sourceName) {
    final exact = _byName[norm(sourceName)];
    if (exact != null) {
      return GameMatch(
        game: exact.game,
        dump: exact.dump,
        tier: MatchTier.exactName,
        sourceName: sourceName,
      );
    }
    return null;
  }
}
