import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_model.dart';

/// A chosen version for a game, with the reason spelled out. The reason is
/// required: it separates "the app chose for you" from "the app chose at random".
@immutable
class SourcePick {
  /// The game's selection key: `Game.gameId` in SOURCE mode, `'pack:${id}'`
  /// in PACK mode. The sheet need not know which.
  final String gameId;
  final String title;
  final String filename;

  /// Bytes. Zero when the source declares no size, and then the sheet shows
  /// the total as approximate.
  final int size;

  /// Which addon it came from, by [Addon] id. Comes from `Game.sourceId`.
  final String sourceId;
  final String reason;

  /// `true` when the match confidence is `guess`. The batch does not verify
  /// CRC before enqueueing.
  final bool uncertain;

  /// What actually goes to the queue. The sheet never reads this field.
  final Game game;

  const SourcePick({
    required this.gameId,
    required this.title,
    required this.filename,
    required this.size,
    required this.sourceId,
    required this.reason,
    required this.game,
    this.uncertain = false,
  });
}

/// A selected game that will not go to the queue, with the reason.
@immutable
class PickFailure {
  final String gameId;
  final String title;
  final String reason;

  const PickFailure({
    required this.gameId,
    required this.title,
    required this.reason,
  });
}

/// What the confirmation sheet draws: what goes and what does not.
@immutable
class BatchPlan {
  final List<SourcePick> picks;
  final List<PickFailure> failures;

  const BatchPlan({this.picks = const [], this.failures = const []});

  int get totalBytes => picks.fold(0, (sum, pick) => sum + pick.size);

  int get uncertainCount => picks.where((pick) => pick.uncertain).length;

  /// Truly empty: nothing to download and nothing to explain. A failures-only
  /// plan is not empty, because the sheet must open to say why.
  bool get isEmpty => picks.isEmpty && failures.isEmpty;

  /// Removes an item from the batch. Returns a new plan; the original is unchanged.
  BatchPlan withoutPick(String gameId) => BatchPlan(
        picks: picks.where((pick) => pick.gameId != gameId).toList(),
        failures: failures,
      );
}
