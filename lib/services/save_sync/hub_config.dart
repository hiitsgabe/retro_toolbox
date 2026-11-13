import 'dart:convert';

/// What the owner decided about one app, as it travels between devices.
///
/// Keyed by package everywhere: that is what the owner picks from a list of
/// installed apps, what Android resolves an icon and a label from, and the
/// only key that can exist before any recipe does.
class ConfigEntry {
  const ConfigEntry({required this.updatedAt, required this.by, this.recipe, this.removed = false});

  /// The recipe this app syncs with, or null for "wanted, nothing resolves
  /// yet" — an app the owner added before a recipe for it existed anywhere.
  final String? recipe;

  /// A tombstone: the owner took this app out. Kept rather than deleted, so a
  /// device holding a stale copy cannot bring it back.
  final bool removed;

  final DateTime updatedAt;

  /// The device that made this decision, and the tiebreak when two devices
  /// decided at the very same moment.
  final String by;

  Map<String, dynamic> toJson() => {
        if (removed) 'removed': true else 'recipe': recipe,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'by': by,
      };

  static ConfigEntry? parse(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse('${j['updatedAt']}');
    final by = j['by'];
    if (at == null || by is! String) return null;
    final recipe = j['recipe'];
    return ConfigEntry(
      recipe: recipe is String ? recipe : null,
      removed: j['removed'] == true,
      updatedAt: at,
      by: by,
    );
  }
}

/// Every app the owner chose, merged from the files each device wrote.
class HubConfig {
  const HubConfig(this.entries);

  static const empty = HubConfig({});

  /// Package to the decision that won, tombstones included.
  final Map<String, ConfigEntry> entries;

  /// The packages that should sync, tombstones left out.
  Iterable<String> get packages => [
        for (final e in entries.entries)
          if (!e.value.removed) e.key,
      ];

  /// How many apps the configuration covers, for the line that greets a device
  /// adopting it.
  int get count => packages.length;

  bool get isEmpty => entries.isEmpty;
}

/// The regex a package has to match, the same one recipes are held to.
final _packageRe = RegExp(r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$');

/// One written file: only what that device changed, never a merged snapshot.
/// Two devices editing different apps therefore cannot collide, with no
/// revision counter and no compare-and-set anywhere.
List<int> encodeConfigFile(Map<String, ConfigEntry> changed, {required String deviceId, required DateTime writtenAt}) =>
    utf8.encode(jsonEncode({
      'format': 1,
      'device': deviceId,
      'writtenAt': writtenAt.toUtc().toIso8601String(),
      'entries': {for (final e in changed.entries) e.key: e.value.toJson()},
    }));

/// Folds the files into one configuration. Per package the newest decision
/// wins; a tie goes to the greater device id, so every device folds the same
/// files into the same answer. A file that will not parse is skipped, the way
/// an unreadable recipe already is.
HubConfig mergeConfigFiles(Iterable<List<int>> files) {
  final out = <String, ConfigEntry>{};
  for (final bytes in files) {
    Map<String, dynamic> j;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) continue;
      j = decoded;
    } catch (_) {
      continue;
    }
    final entries = j['entries'];
    if (entries is! Map) continue;
    for (final e in entries.entries) {
      final package = '${e.key}';
      if (!_packageRe.hasMatch(package)) continue;
      final parsed = ConfigEntry.parse(e.value);
      if (parsed == null) continue;
      final held = out[package];
      if (held == null || _wins(parsed, held)) out[package] = parsed;
    }
  }
  return HubConfig(out);
}

bool _wins(ConfigEntry candidate, ConfigEntry held) {
  final byTime = candidate.updatedAt.compareTo(held.updatedAt);
  return byTime != 0 ? byTime > 0 : candidate.by.compareTo(held.by) > 0;
}
