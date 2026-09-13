import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Search and sort for the PACK MODE grid.
///
/// Does not filter by region, revision, dump quality, or availability: the
/// grid shows the whole pack and marks the exceptions.
List<PackGridEntry> filterPackEntries(List<PackGridEntry> entries, String query) {
  final needle = norm(query);
  final out = needle.isEmpty
      ? [...entries]
      : entries.where((entry) => norm(entry.game.title).contains(needle)).toList();

  out.sort((a, b) {
    final byTitle = norm(a.game.title).compareTo(norm(b.game.title));
    // Stable tiebreak by id: two games can share a title, and without this the
    // grid order would shift between rebuilds.
    return byTitle != 0 ? byTitle : a.game.id.compareTo(b.game.id);
  });
  return out;
}

/// The entries the user selected, in the order [entries] arrived. Unknown keys
/// are ignored silently.
List<PackGridEntry> entriesForSelection(List<PackGridEntry> entries, Set<String> keys) =>
    [for (final entry in entries) if (keys.contains(entry.selectionKey)) entry];

/// The selection keys that belong to the current mode.
///
/// The selection is one `Set<String>` shared by both modes, and both can
/// briefly coexist in the same console. Does not clear the other mode's
/// selection: if the pack fails and the mode falls back to SOURCE, the user's
/// marks are still there.
Set<String> selectionKeysFor(Set<String> keys, {required bool pack}) =>
    {for (final key in keys) if (key.startsWith(kPackSelectionPrefix) == pack) key};
