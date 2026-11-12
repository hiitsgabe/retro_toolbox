import 'package:retro_toolbox/services/save_sync/gen.dart';

/// What this device had after its last successful sync of a unit.
class Base {
  const Base(this.gen, this.files);

  final String gen;

  /// Relative path to sha256.
  final Map<String, String> files;

  Map<String, dynamic> toJson() => {'gen': gen, 'files': files};

  static Base fromJson(Map<String, dynamic> j) => Base(j['gen'] as String, (j['files'] as Map).cast<String, String>());
}

sealed class UnitPlan {
  const UnitPlan(this.unit);

  final String unit;
}

class UpToDate extends UnitPlan {
  const UpToDate(super.unit, {this.adopt});

  /// A head equal to the local files that should become the base.
  final GenMeta? adopt;
}

class PushPlan extends UnitPlan {
  const PushPlan(super.unit, this.parents);

  final List<String> parents;
}

class PullPlan extends UnitPlan {
  const PullPlan(super.unit, this.gen, {required this.missingLocally});

  final GenMeta gen;

  /// The unit has no files on this device.
  final bool missingLocally;
}

class Diverged extends UnitPlan {
  const Diverged(super.unit, this.heads, {required this.localDiffers});

  /// Newest first.
  final List<GenMeta> heads;

  /// This device has files that match no head.
  final bool localDiffers;
}

class Busy extends UnitPlan {
  const Busy(super.unit);
}

/// The unit cannot sync right now; [reason] is for the user.
class Blocked extends UnitPlan {
  const Blocked(super.unit, this.reason);

  final String reason;
}

/// The spec's decision table for one unit. [local] is empty when the unit has no files here.
UnitPlan planUnit({required String unit, required Map<String, String> local, required bool busy, required Base? base, required List<GenMeta> gens}) {
  if (busy) return Busy(unit);
  final hasLocal = local.isNotEmpty;
  final heads = headsOf(gens);
  final same = hasLocal ? heads.where((h) => sameFiles(local, h.hashes)).firstOrNull : null;
  if (heads.length > 1) return Diverged(unit, heads, localDiffers: hasLocal && same == null);
  if (same != null) return UpToDate(unit, adopt: base?.gen == same.gen ? null : same);
  if (heads.isEmpty) return hasLocal ? PushPlan(unit, const []) : UpToDate(unit);
  final head = heads.single;
  if (!hasLocal) return PullPlan(unit, head, missingLocally: true);
  if (base == null) return Diverged(unit, heads, localDiffers: true);
  final unchanged = sameFiles(local, base.files);
  if (base.gen == head.gen) return unchanged ? UpToDate(unit) : PushPlan(unit, [head.gen]);
  return unchanged ? PullPlan(unit, head, missingLocally: false) : Diverged(unit, heads, localDiffers: true);
}
