import 'package:roms_downloader/models/metadata_pack_model.dart';

/// How a match was obtained. Declaration order is preference order: the
/// matcher tries top to bottom and stops at the first that resolves.
enum MatchTier {
  /// CRC32 matched a dump in the pack. The only tier that never errs.
  checksum,

  /// The file's `norm` equals a dump's `norm`.
  exactName,

  /// The file's `canon` equals a pack game's `canon`. Matches region and
  /// revision variants, the common case.
  canonicalName,

  /// Edit similarity above the cutoff. Can err, and never becomes certainty.
  fuzzyName,
}

/// What the screen may assert, derived from the tier.
enum MatchConfidence { confirmed, likely, guess }

extension MatchTierConfidence on MatchTier {
  MatchConfidence get confidence => switch (this) {
        MatchTier.checksum => MatchConfidence.confirmed,
        MatchTier.exactName => MatchConfidence.likely,
        MatchTier.canonicalName => MatchConfidence.likely,
        MatchTier.fuzzyName => MatchConfidence.guess,
      };
}

/// A source file assigned to a pack game.
///
/// [dump] is filled only when the tier identifies which version (`checksum`
/// and `exactName`); the canonical and fuzzy tiers leave it null.
class GameMatch {
  final PackGame game;
  final MatchTier tier;

  /// The raw source filename, as the source gave it.
  final String sourceName;

  final PackDump? dump;

  /// 0 to 100. Only the fuzzy tier uses it; the others stay at 100.
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
