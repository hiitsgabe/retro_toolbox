import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Answers a closed question: does this remote file contain a dump of this
/// game?
///
/// A cousin of `CrcConfirmService`, whose question is open ("which game is this
/// file"). Here the answer is a verdict the screen paints.
///
/// Pure Dart on purpose. Do not add a `package:flutter` import.
class SourceVerificationService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const SourceVerificationService({required this.matcher, required this.fetch});

  /// Never throws: every failure becomes [SourceVerification.impossible].
  Future<SourceVerification> verify(
      Uri uri, String sourceName, String gameId) async {
    if (!sourceName.toLowerCase().endsWith('.zip')) {
      return SourceVerification.impossible;
    }

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return SourceVerification.impossible;

    var sawRom = false;
    for (final entry in entries) {
      // `crcMatchesRom` excludes the archive-within-an-archive, whose CRC is
      // the compressed file's, not the ROM's.
      if (!entry.crcMatchesRom) continue;
      sawRom = true;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null && hit.game.id == gameId) return SourceVerification.crcOk;
    }

    // A zip with only a readme and cover disproves nothing; a zip with a ROM
    // that is not this game does, and gets discarded.
    return sawRom
        ? SourceVerification.crcDiscarded
        : SourceVerification.impossible;
  }
}
