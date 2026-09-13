import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// A raw file from a source, before the matcher opines on it.
typedef SourceFile = ({String filename, String sourceId, int size, String? url});

/// Inverted index: given a `PackGame` id, which files exist.
///
/// The `PackMatcher` answers "which game is this file"; this answers "which
/// files are this game". Build once per console, not inside a widget `build`:
/// it is thousands of `match` calls at a time.
class SourceIndex {
  final Map<String, List<MatchedSource>> _byGameId;

  /// Names with a ROM extension the matcher assigned to no game. Non-ROM names
  /// never enter here.
  final List<String> unmatched;

  const SourceIndex._(this._byGameId, this.unmatched);

  static SourceIndex build(PackMatcher matcher, List<SourceFile> files) {
    final byGameId = <String, List<MatchedSource>>{};
    final unmatched = <String>[];

    for (final file in files) {
      if (!hasRomExtension(file.filename)) continue;
      final match = matcher.match(file.filename);
      if (match == null) {
        unmatched.add(file.filename);
        continue;
      }
      byGameId.putIfAbsent(match.game.id, () => <MatchedSource>[]).add(MatchedSource(
            filename: file.filename,
            sourceId: file.sourceId,
            confidence: match.confidence,
            size: file.size,
            url: file.url,
          ));
    }

    return SourceIndex._(byGameId, unmatched);
  }

  /// That game's sources, in listing order. Ordering by preference is the
  /// pick rule's job, not the index's.
  List<MatchedSource> sourcesFor(String gameId) => _byGameId[gameId] ?? const [];

  bool hasSource(String gameId) => _byGameId.containsKey(gameId);

  /// How many pack games have at least one source.
  int get matchedGameCount => _byGameId.length;
}
