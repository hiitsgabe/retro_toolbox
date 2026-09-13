import 'package:rapidfuzz/rapidfuzz.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Tier 3 cutoff, on the 0 to 100 scale of `rapidfuzz.ratio`.
const fuzzyCutoff = 90.0;

/// Matches a filename against a game from the metadata pack.
///
/// Three name tiers: exact name, canonical title, edit similarity. Plus a
/// fourth axis, `matchCrc`, the only one that never errs.
///
/// Pure Dart on purpose: `tool/verify_matcher.dart` runs this outside Flutter.
/// Do not add a `package:flutter` import.
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

  /// The first four characters of the first token. A bucket so tier 3 does not
  /// scan the whole pack on every miss.
  static String _head(String canonKey) {
    final first = canonKey.split(' ').first;
    return first.length <= 4 ? first : first.substring(0, 4);
  }

  /// How many games and canonical keys the matcher indexed.
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

    final key = canon(sourceName);
    if (key.isEmpty) return null;

    final byCanon = _byCanon[key];
    if (byCanon != null) {
      return GameMatch(
        game: byCanon,
        tier: MatchTier.canonicalName,
        sourceName: sourceName,
      );
    }

    final pool = _byHead[_head(key)] ?? _byCanon.keys.toList();
    String? best;
    var bestScore = 0.0;
    for (final candidate in pool) {
      final score = ratio(key, candidate);
      if (score > bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    if (best == null || bestScore < fuzzyCutoff) return null;
    return GameMatch(
      game: _byCanon[best]!,
      tier: MatchTier.fuzzyName,
      sourceName: sourceName,
      score: bestScore,
    );
  }

  /// The axis that never errs. [crc] may come in any case.
  ///
  /// Caller beware: the CRC must be the ROM's, not the served file's. A ZIP has
  /// its own CRC and it is not in the pack.
  GameMatch? matchCrc(String crc, {String sourceName = ''}) {
    final upper = crc.toUpperCase();
    final game = pack.byCrc[upper];
    if (game == null) return null;
    PackDump? dump;
    for (final candidate in game.dumps) {
      if (candidate.crc == upper) {
        dump = candidate;
        break;
      }
    }
    return GameMatch(
      game: game,
      dump: dump,
      tier: MatchTier.checksum,
      sourceName: sourceName,
    );
  }
}
