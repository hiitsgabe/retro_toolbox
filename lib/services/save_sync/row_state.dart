import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';

/// Why a row cannot act. A condition of this device, never an incident: an
/// incident is [RowFailed], and the two never share a shape on screen.
enum BlockReason {
  /// The saves live where only root goes, on any device.
  needsRoot,

  /// This device cannot open this app's folder, though the same app opens
  /// fine on another handheld. Telling the owner to root would be a lie.
  notOpenableHere,

  /// The app has not made its save folder yet.
  folderMissing,

  /// More than one place could hold the saves and none has any yet.
  locationUnknown,

  /// Nothing is reachable from this device at all. The remedy lives once in
  /// the header, not on fifty rows.
  noAccess,

  /// The app carries its own cloud, so saves only travel one way.
  backupOnly,
}

/// Every way a row can read. Closed on purpose: the screen cannot invent a
/// ninth state out of an exception string.
sealed class RowState {
  const RowState();
}

class RowUpToDate extends RowState {
  const RowUpToDate(this.at);

  /// When the hub copy this matches was made, for the relative time.
  final DateTime? at;
}

class RowNeedsPush extends RowState {
  const RowNeedsPush(this.at);

  final DateTime? at;
}

class RowNeedsPull extends RowState {
  const RowNeedsPull(this.at, this.fromDevice);

  final DateTime? at;

  /// The handheld whose copy is newer, named rather than implied.
  final String fromDevice;
}

class RowConflict extends RowState {
  const RowConflict();
}

class RowNeedsConfirm extends RowState {
  const RowNeedsConfirm(this.bind);

  final NeedsConfirm bind;
}

class RowBlocked extends RowState {
  const RowBlocked(this.reason, {this.bind});

  final BlockReason reason;

  /// Kept so a row that only needs the place confirmed can still offer it.
  final NeedsConfirm? bind;
}

class RowNotInstalled extends RowState {
  const RowNotInstalled();
}

/// An action this device tried and could not finish. Shown apart from
/// [RowBlocked], because a thing that failed may be worth trying again and a
/// thing that is blocked never is.
class RowFailed extends RowState {
  const RowFailed(this.message);

  final String message;
}

/// The one place a [GameStatus] turns into something the screen can draw.
RowState rowStateFor(GameStatus g, {required bool hasAccess}) {
  switch (g.bind) {
    case NotInstalled():
      return const RowNotInstalled();
    case NeedsRoot(:final reason):
      return RowBlocked(reason == NeedsRoot.refused ? BlockReason.notOpenableHere : BlockReason.needsRoot);
    case FolderMissing():
      return const RowBlocked(BlockReason.folderMissing);
    case NeedsDiscovery():
      return RowBlocked(BlockReason.locationUnknown, bind: null);
    case NeedsConfirm(:final binding, :final files):
      return RowNeedsConfirm(NeedsConfirm(binding, files));
    case Bound():
      break;
  }
  if (!hasAccess) return const RowBlocked(BlockReason.noAccess);
  if (g.error != null) return RowFailed(g.error!);
  if (g.backupOnly) return const RowBlocked(BlockReason.backupOnly);

  // One row stands for every unit of the game, so the most urgent unit wins:
  // a conflict is a task, a pending direction is a chore, and only when every
  // unit is settled does the row read as up to date.
  final plans = [for (final u in g.units.values) u.plan];
  if (plans.any((p) => p is Diverged)) return const RowConflict();
  final newest = _newest(g);
  if (plans.any((p) => p is PullPlan)) {
    final from = g.units.values.map((u) => u.newest).whereType<GenMeta>().toList();
    from.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return RowNeedsPull(newest, from.isEmpty ? 'another device' : from.first.deviceName);
  }
  if (plans.any((p) => p is PushPlan)) return RowNeedsPush(newest);
  return RowUpToDate(newest);
}

DateTime? _newest(GameStatus g) {
  final times = [for (final u in g.units.values) u.newest?.createdAt].whereType<DateTime>().toList();
  if (times.isEmpty) return null;
  times.sort();
  return times.last;
}

/// Where a row sits in the list. Settled once in the provider, never in build.
int rowRank(RowState s) => switch (s) {
      RowConflict() => 0,
      RowNeedsConfirm() => 1,
      RowFailed() => 2,
      RowNeedsPull() => 3,
      RowNeedsPush() => 4,
      RowUpToDate() => 5,
      RowBlocked() => 6,
      RowNotInstalled() => 7,
    };
