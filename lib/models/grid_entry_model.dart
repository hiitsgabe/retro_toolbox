import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

/// A source file the matcher paired with a `PackGame`. Size comes from the
/// listing, not the matcher.
@immutable
class MatchedSource {
  final String filename;

  /// Which source it came from, by addon id.
  final String sourceId;
  final MatchConfidence confidence;

  /// Bytes, or zero when the listing declares no size.
  final int size;

  /// The download URL. Null when the source does not provide it up front.
  final String? url;

  const MatchedSource({
    required this.filename,
    required this.sourceId,
    required this.confidence,
    required this.size,
    this.url,
  });
}

/// The PACK-mode selection key prefix. `:` cannot appear in a `_nameToId` id,
/// so a key with this prefix never collides with a `Game.gameId`.
const kPackSelectionPrefix = 'pack:';

/// A PACK-mode grid entry: a canonical game and its sources. The grid draws
/// this, not `Game`.
@immutable
class PackGridEntry {
  final PackGame game;
  final List<MatchedSource> sources;

  const PackGridEntry({required this.game, this.sources = const []});

  /// The only axis the tile paints: availability, never confidence.
  bool get hasSource => sources.isNotEmpty;

  int get sourceCount => sources.length;

  /// The PACK-mode selection key; the `pack:` prefix keeps it disjoint from
  /// `Game.gameId`.
  String get selectionKey => '$kPackSelectionPrefix${game.id}';
}
