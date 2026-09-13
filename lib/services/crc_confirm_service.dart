import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Confirms or corrects a name guess by reading the ROM's CRC from inside the
/// remote ZIP, before any download.
///
/// Pure Dart on purpose. Do not add a `package:flutter` import.
class CrcConfirmService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const CrcConfirmService({required this.matcher, required this.fetch});

  /// Returns a [MatchTier.checksum] match when the ZIP was conclusive, and
  /// [byName] untouched otherwise. Never throws: network failure here just
  /// keeps the guess already held.
  Future<GameMatch?> confirm(
      Uri uri, String sourceName, GameMatch? byName) async {
    if (!sourceName.toLowerCase().endsWith('.zip')) return byName;

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return byName;

    final hits = <String, GameMatch>{};
    for (final entry in entries) {
      if (!entry.crcMatchesRom) continue;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null) hits[hit.game.id] = hit;
    }

    if (hits.length != 1) return byName;
    return hits.values.first;
  }
}
