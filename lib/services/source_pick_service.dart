import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_metadata_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/utils/title_metadata_parser.dart';

/// The batch plan for SOURCE MODE.
///
/// There is no choice to make here: each selected `Game` is already a file, so
/// no pick is uncertain and the failure list is always empty. The real rule,
/// with region, revision, confidence, and addon priority, lives in
/// `planFromEntries`.
BatchPlan planFromGames(List<Game> games) {
  return BatchPlan(
    picks: [
      for (final game in games)
        SourcePick(
          gameId: game.gameId,
          title: game.displayTitle,
          filename: game.filename,
          size: game.size,
          sourceId: game.sourceId,
          reason: 'you picked this file',
          game: game,
        ),
    ],
  );
}

/// How the caller turns a source into the `Game` that goes to the queue.
/// Returns `null` when the source no longer exists, and the game becomes a
/// `PickFailure`.
typedef GameResolver = Game? Function(MatchedSource source);

typedef _Candidate = ({MatchedSource source, GameMetadata meta, Game game, int order});

/// The pick rule, in order: preferred region, highest revision, highest
/// confidence, addon priority. The same rule that picks the detail screen's
/// highlight.
BatchPlan planFromEntries(
  List<PackGridEntry> entries, {
  required Set<String> preferredRegions,
  required GameResolver resolveGame,
  List<String> sourcePriority = const [],
}) {
  final picks = <SourcePick>[];
  final failures = <PickFailure>[];

  for (final entry in entries) {
    if (entry.sources.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'no installed source has this game',
      ));
      continue;
    }

    final candidates = <_Candidate>[];
    for (var i = 0; i < entry.sources.length; i++) {
      final source = entry.sources[i];
      final game = resolveGame(source);
      if (game == null) continue;
      candidates.add((
        source: source,
        meta: TitleMetadataParser.parseRomTitle(source.filename),
        game: game,
        order: i,
      ));
    }

    if (candidates.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'the source left the listing before the queue started',
      ));
      continue;
    }

    candidates.sort((a, b) => _compare(a, b, preferredRegions, sourcePriority));
    final winner = candidates.first;

    picks.add(SourcePick(
      gameId: entry.selectionKey,
      title: entry.game.title,
      filename: winner.source.filename,
      size: winner.source.size,
      sourceId: winner.source.sourceId,
      reason: _reason(winner, candidates, preferredRegions, sourcePriority),
      // The batch does not verify CRC before enqueuing: it marks the guess and
      // leaves the safety net to post-download verification.
      uncertain: winner.source.confidence == MatchConfidence.guess,
      game: winner.game,
    ));
  }

  return BatchPlan(picks: picks, failures: failures);
}

/// The rom types that mean "this is not the released game": a beta, an alpha,
/// a prototype, a demo or a sample.
const _prerelease = {
  RomType.beta,
  RomType.alpha,
  RomType.proto,
  RomType.demo,
  RomType.sample,
};

/// 0 for a finished release, 1 for a prerelease.
int _prereleaseRank(_Candidate candidate) =>
    candidate.meta.romTypes.any(_prerelease.contains) ? 1 : 0;

int _compare(_Candidate a, _Candidate b, Set<String> preferred, List<String> priority) {
  // Ahead of region on purpose: a beta is the wrong game, while a foreign
  // release is the right game in the wrong language. Nothing below can promote
  // a prerelease over a finished release.
  final prerelease = _prereleaseRank(a).compareTo(_prereleaseRank(b));
  if (prerelease != 0) return prerelease;

  final region = _regionRank(a, preferred).compareTo(_regionRank(b, preferred));
  if (region != 0) return region;

  // Inverted on purpose: the higher revision comes first.
  final revision = _compareRevision(b.meta.revision, a.meta.revision);
  if (revision != 0) return revision;

  // `MatchConfidence` is declared most confident first, so the lower index
  // wins.
  final confidence = a.source.confidence.index.compareTo(b.source.confidence.index);
  if (confidence != 0) return confidence;

  final addon = _priorityRank(a, priority).compareTo(_priorityRank(b, priority));
  if (addon != 0) return addon;

  // Final tiebreak is arrival order, because `List.sort` is not stable.
  return a.order.compareTo(b.order);
}

/// 0 is preferred, 1 is not. A candidate with no region in its name does not
/// lose.
int _regionRank(_Candidate candidate, Set<String> preferred) {
  if (preferred.isEmpty) return 0;
  if (candidate.meta.regions.isEmpty) return 0;
  return candidate.meta.regions.any(preferred.contains) ? 0 : 1;
}

/// Positive when [a] is newer than [b].
///
/// Lexical comparison, with a known limitation: `Rev A` beats `Rev 1`, and
/// `1.10` loses to `1.2`. Diverging here would make the grid and the batch
/// disagree.
int _compareRevision(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return -1;
  if (b.isEmpty) return 1;
  return a.compareTo(b);
}

int _priorityRank(_Candidate candidate, List<String> priority) {
  final index = priority.indexOf(candidate.source.sourceId);
  return index < 0 ? priority.length : index;
}

/// The spelled-out reason: the axis on which the winner beat the runner-up.
String _reason(
  _Candidate winner,
  List<_Candidate> ordered,
  Set<String> preferred,
  List<String> priority,
) {
  if (ordered.length == 1) return 'the only source that has this game';
  final runnerUp = ordered[1];

  if (_prereleaseRank(winner) != _prereleaseRank(runnerUp)) {
    return 'the finished release, not a beta or a demo';
  }

  if (_regionRank(winner, preferred) != _regionRank(runnerUp, preferred)) {
    final region = winner.meta.regions.where(preferred.contains).firstOrNull;
    return region == null
        ? 'chosen by your preferred region'
        : 'chosen by your preferred region ($region)';
  }

  // If the revisions differ, the winner's is the higher one, so it can be
  // named without checking again.
  if (_compareRevision(winner.meta.revision, runnerUp.meta.revision) != 0) {
    return 'the newest revision (Rev ${winner.meta.revision})';
  }

  if (winner.source.confidence != runnerUp.source.confidence) {
    return 'the most confident match among the ${ordered.length} sources';
  }

  if (_priorityRank(winner, priority) != _priorityRank(runnerUp, priority)) {
    return 'comes from the higher-priority addon';
  }

  return 'tie among ${ordered.length} sources, kept the first';
}

/// A source with its CRC verdict already resolved.
typedef VerifiedSource = ({MatchedSource source, SourceVerification state});

/// How CRC verification reorganizes a game's sources.
typedef VerificationSplit = ({
  /// Who can contest the highlight: only the confirmed ones when any is
  /// confirmed, otherwise everything not discarded.
  List<VerifiedSource> eligible,

  /// Who left the contest because the CRC contradicted the name.
  List<VerifiedSource> discarded,

  /// Some read still in flight.
  bool verifying,

  /// Some source confirmed by CRC.
  bool confirmed,

  /// Sources remain, none confirmed, and all that remain are impossible to
  /// verify.
  bool noCertainty,
});

/// The verification rule, in order. Pure, so the detail screen only draws.
VerificationSplit splitByVerification(List<VerifiedSource> sources) {
  final ok = <VerifiedSource>[];
  final discarded = <VerifiedSource>[];
  final rest = <VerifiedSource>[];
  var verifying = false;
  var impossible = 0;

  for (final item in sources) {
    switch (item.state) {
      case SourceVerification.crcOk:
        ok.add(item);
      case SourceVerification.crcDiscarded:
        discarded.add(item);
      case SourceVerification.verifying:
        verifying = true;
        rest.add(item);
      case SourceVerification.impossible:
        impossible++;
        rest.add(item);
      case SourceVerification.notVerified:
        rest.add(item);
    }
  }

  return (
    eligible: ok.isNotEmpty ? ok : rest,
    discarded: discarded,
    verifying: verifying,
    confirmed: ok.isNotEmpty,
    // `impossible == rest.length`, not `!verifying`: a source nobody asked
    // about has not given up yet.
    noCertainty: ok.isEmpty && rest.isNotEmpty && impossible == rest.length,
  );
}
