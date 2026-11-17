import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';

/// What the app's caches take on disk, in bytes.
class StorageUsage {
  const StorageUsage({required this.catalog, required this.launchbox, required this.sports, this.consoles = const {}});

  /// Every console's game list plus the box art listings.
  final int catalog;

  /// The imported LaunchBox metadata.
  final int launchbox;

  /// Saved formations and downloaded rosters.
  final int sports;

  /// Console id to its own game list's size.
  final Map<String, int> consoles;

  int get total => catalog + launchbox + sports;
}

int _fileSize(String path) {
  try {
    final f = File(path);
    return f.existsSync() ? f.lengthSync() : 0;
  } catch (_) {
    return 0;
  }
}

int _dirSize(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return 0;
  var total = 0;
  try {
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is File) total += _fileSize(e.path);
    }
  } catch (_) {}
  return total;
}

/// Walks the cache folders. [cacheDir] holds the game lists and box art
/// listings, [supportDir] LaunchBox and the sports data; [consoleFiles] is
/// console id to its game list's file name. Blocking: run it off the UI
/// isolate ([measureStorageUsage]).
StorageUsage measureStorage({required String cacheDir, required String supportDir, Map<String, String> consoleFiles = const {}}) {
  var catalog = 0;
  final dir = Directory(cacheDir);
  if (dir.existsSync()) {
    try {
      for (final e in dir.listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (e is File && (name.startsWith('catalog_v2_') || name.startsWith('boxarts_'))) catalog += _fileSize(e.path);
      }
    } catch (_) {}
  }
  return StorageUsage(
    catalog: catalog,
    launchbox: _dirSize(p.join(supportDir, 'launchbox')),
    sports: _fileSize(p.join(supportDir, 'sports_formations.json')) + _dirSize(p.join(supportDir, 'rrp_cache')),
    consoles: {for (final e in consoleFiles.entries) e.key: _fileSize(p.join(cacheDir, e.value))},
  );
}

/// [measureStorage] on a background isolate, for the app's own folders.
Future<StorageUsage> measureStorageUsage(Map<String, String> consoleFiles) async {
  final cache = (await getApplicationCacheDirectory()).path;
  final support = (await getApplicationSupportDirectory()).path;
  return Isolate.run(() => measureStorage(cacheDir: cache, supportDir: support, consoleFiles: consoleFiles));
}

/// The caches' sizes, measured when first asked and after an invalidate
/// (each Clear does one). Errors and a missing platform leave it unknown.
final storageUsageProvider = FutureProvider<StorageUsage>((ref) {
  // A finished or removed import changes LaunchBox's share.
  ref.watch(launchboxVersionProvider);
  final consoles = ref.watch(appStateProvider.select((s) => s.consolesList));
  return measureStorageUsage({for (final c in consoles) c.id: c.cacheFile});
});

/// "18 MB", "640 KB": sizes as the settings rows say them.
String storageSize(int bytes) {
  if (bytes < 1024 * 1024) {
    final kb = (bytes / 1024).ceil();
    return '$kb KB';
  }
  final mb = bytes / (1024 * 1024);
  return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
}
