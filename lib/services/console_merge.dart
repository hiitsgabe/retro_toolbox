import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/console_model.dart';

/// A catalog url, with which addon it came from and which auth it speaks.
///
/// Auth belongs to the url, not the console: two addons can serve the same
/// console with different credentials.
@immutable
class ConsoleSource {
  final String addonId;
  final String url;
  final Map<String, dynamic>? auth;

  const ConsoleSource({required this.addonId, required this.url, this.auth});
}

/// The app catalog: the consoles the screen draws and, per console, where each
/// url came from.
///
/// Invariant: for every id, `sources[id]!.map((s) => s.url)` equals
/// `consoles[id]!.urls`, in the same order.
@immutable
class MergedCatalog {
  final Map<String, Console> consoles;
  final Map<String, List<ConsoleSource>> sources;

  const MergedCatalog({this.consoles = const {}, this.sources = const {}});

  bool get isEmpty => consoles.isEmpty;

  /// From each addon to what it covers.
  ///
  /// An addon serving no console is absent from the map; readers treat absent
  /// as zero coverage.
  Map<String, AddonCoverage> coverage() {
    final byAddon = <String, List<String>>{};
    final withAccount = <String, List<String>>{};

    for (final entry in sources.entries) {
      final seen = <String>{};
      for (final source in entry.value) {
        if (!seen.add(source.addonId)) continue;
        byAddon.putIfAbsent(source.addonId, () => <String>[]).add(entry.key);
        if (authNeedsToken(source.auth)) {
          withAccount.putIfAbsent(source.addonId, () => <String>[]).add(entry.key);
        }
      }
    }

    return {
      for (final entry in byAddon.entries)
        entry.key: (consoles: entry.value, authConsoles: withAccount[entry.key] ?? const <String>[]),
    };
  }
}

/// An addon's catalog, already parsed.
typedef AddonCatalog = ({String addonId, Map<String, Console> consoles});

/// The auth [addonId] speaks in this console, or `null` if it doesn't serve
/// it. Not serving and serving without auth both return `null`.
Map<String, dynamic>? authForAddon(List<ConsoleSource> sources, String addonId) {
  for (final source in sources) {
    if (source.addonId == addonId) return source.auth;
  }
  return null;
}

/// What an addon covers: the consoles it serves, and which of them need auth.
typedef AddonCoverage = ({List<String> consoles, List<String> authConsoles});

/// Merges the catalogs in the order they arrive, which is the user's addon
/// priority order.
///
/// - console metadata (name, regex, boxarts, formats) comes from the first
///   addon that declared it; later addons only add urls.
/// - urls concatenate in addon order.
/// - a repeated url enters once, from where it first appeared.
MergedCatalog mergeCatalogs(List<AddonCatalog> catalogs) {
  final consoles = <String, Console>{};
  final sources = <String, List<ConsoleSource>>{};

  for (final catalog in catalogs) {
    for (final entry in catalog.consoles.entries) {
      final id = entry.key;
      final console = entry.value;
      final existing = sources.putIfAbsent(id, () => <ConsoleSource>[]);
      final seenUrls = existing.map((f) => f.url).toSet();
      for (final url in console.urls) {
        if (!seenUrls.add(url)) continue;
        existing.add(ConsoleSource(addonId: catalog.addonId, url: url, auth: console.auth));
      }
      consoles[id] = (consoles[id] ?? console).withUrls([for (final f in existing) f.url]);
    }
  }

  return MergedCatalog(consoles: consoles, sources: sources);
}
