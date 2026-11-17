import 'dart:math' as math;

import 'package:retro_toolbox/models/game_metadata_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/utils/title_metadata_parser.dart';

/// The regions a main version is looked for in when no region filter is on.
const defaultRegionOrder = ['USA', 'World', 'Europe', 'Japan'];

/// One version of a game: a region set, languages, revision and edition,
/// with its discs (one for a single-disc game).
class GameVersion {
  GameVersion({required this.discs, required this.tags});

  /// By disc number; never empty.
  final List<Game> discs;

  /// The name tags every disc shares ("USA", "Rev 1", "Premium Package").
  final List<String> tags;

  Game get first => discs.first;

  late final GameMetadata metadata = first.metadata ?? TitleMetadataParser.parseRomTitle(first.title);

  List<String> get regions => metadata.regions;
  String get revision => metadata.revision;
  bool get isAlt => tags.contains('Alt');

  /// What the list shows for this version: its first disc, carrying the set
  /// when it has two or more.
  Game get entry => discs.length >= 2 ? first.copyWith(discs: discs) : first;

  /// "USA · Rev 1 · 2 discs".
  String get label => [...tags, if (discs.length >= 2) '${discs.length} discs'].join(' · ');
}

/// A game with everything the catalog has of it: its versions and extras
/// (demos, betas, bonus discs), or for a box set, the games in the box.
class GameGroup {
  GameGroup({required this.title, this.versions = const [], this.extras = const [], this.members = const []});

  final String title;
  final List<GameVersion> versions;
  final List<Game> extras;

  /// A box set's games, each a group of its own; empty otherwise.
  final List<GameGroup> members;

  bool get isBoxSet => members.isNotEmpty;

  /// Every file of the group, the members' included.
  Iterable<Game> get files => [
        for (final v in versions) ...v.discs,
        ...extras,
        for (final m in members) ...m.files,
      ];
}

/// The version to show and download: the first of [regions] it is in, then
/// the newest revision, then a plain version before an Alt, then the shortest
/// name. Null when there is none.
GameVersion? pickMainVersion(List<GameVersion> versions, List<String> regions) {
  if (versions.isEmpty) return null;
  int rank(GameVersion v) {
    for (var i = 0; i < regions.length; i++) {
      if (v.regions.contains(regions[i])) return i;
    }
    return regions.length;
  }

  final sorted = [...versions]..sort((a, b) {
      final byRegion = rank(a).compareTo(rank(b));
      if (byRegion != 0) return byRegion;
      final byRevision = compareRevisions(b.revision, a.revision);
      if (byRevision != 0) return byRevision;
      if (a.isAlt != b.isAlt) return a.isAlt ? 1 : -1;
      final byLength = a.first.title.length.compareTo(b.first.title.length);
      return byLength != 0 ? byLength : a.first.title.compareTo(b.first.title);
    });
  return sorted.first;
}

/// Orders two revisions ("" < "1" < "2" < "10", "A" < "B", "1.1" < "1.10").
int compareRevisions(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return -1;
  if (b.isEmpty) return 1;
  final pa = a.split('.'), pb = b.split('.');
  for (var i = 0; i < math.max(pa.length, pb.length); i++) {
    final x = i < pa.length ? pa[i] : '0', y = i < pb.length ? pb[i] : '0';
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return 0;
}
