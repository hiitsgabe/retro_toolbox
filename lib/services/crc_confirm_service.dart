import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Confirma ou corrige um palpite de nome lendo o CRC da ROM de dentro do ZIP
/// remoto, antes de qualquer download. É o eixo do meio da seção 5.5 do spec.
///
/// Dart puro de propósito. Não adicione import de `package:flutter`.
class CrcConfirmService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const CrcConfirmService({required this.matcher, required this.fetch});

  /// [byName] é o que o eixo de nome achou, e pode ser null.
  ///
  /// Devolve um match de tier [MatchTier.checksum] quando o ZIP foi
  /// conclusivo, e [byName] intocado em todos os outros casos. Nunca levanta:
  /// falha de rede aqui só significa ficar com o palpite que já se tinha.
  Future<GameMatch?> confirm(
      Uri uri, String sourceName, GameMatch? byName) async {
    // Sem leitor de 7z ou rar por Range, então nem gaste a requisição.
    if (!sourceName.toLowerCase().endsWith('.zip')) return byName;

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return byName;

    final hits = <String, GameMatch>{};
    for (final entry in entries) {
      if (!entry.crcMatchesRom) continue;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null) hits[hit.game.id] = hit;
    }

    // Um jogo só é conclusivo, e três discos do mesmo jogo continuam sendo um
    // jogo só. Zero ou dois não decidem nada, e inventar um critério de
    // desempate aqui seria trocar uma certeza por um palpite.
    if (hits.length != 1) return byName;
    return hits.values.first;
  }
}
