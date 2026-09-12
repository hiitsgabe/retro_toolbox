import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Responde uma pergunta fechada: **este** arquivo remoto contém um dump
/// **deste** jogo?
///
/// É prima de `CrcConfirmService` e não é a mesma coisa. Lá a pergunta é
/// aberta, "de que jogo é este arquivo", e a resposta é um `GameMatch` que
/// pode corrigir o palpite de nome. Aqui a resposta é um veredito que a tela
/// pinta. O `confirm` devolve `byName` intocado tanto quando não leu nada
/// quanto quando leu e não decidiu, e aqui esses dois casos são estados
/// diferentes. O que as duas compartilham de verdade é
/// `ZipCentralDirectory.read`, que é onde mora a parte difícil.
///
/// Dart puro de propósito. Não adicione import de `package:flutter`.
class SourceVerificationService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const SourceVerificationService({required this.matcher, required this.fetch});

  /// Nunca levanta: toda falha vira [SourceVerification.impossible].
  Future<SourceVerification> verify(
      Uri uri, String sourceName, String gameId) async {
    // Sem leitor de 7z ou rar por Range, então nem gaste a requisição.
    if (!sourceName.toLowerCase().endsWith('.zip')) {
      return SourceVerification.impossible;
    }

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return SourceVerification.impossible;

    var viuRom = false;
    for (final entry in entries) {
      // `crcMatchesRom` exclui o compactado dentro do compactado, cujo CRC é
      // do comprimido e não da ROM (seção 5.8, limite 1).
      if (!entry.crcMatchesRom) continue;
      viuRom = true;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null && hit.game.id == gameId) return SourceVerification.crcOk;
    }

    // Um zip só com leia-me e capa não desmente nada, então não descarta. Um
    // zip com ROM que não é deste jogo desmente, e descarta.
    return viuRom
        ? SourceVerification.crcDiscarded
        : SourceVerification.impossible;
  }
}
