import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What Android itself shows for an installed package.
class AppInfo {
  const AppInfo(this.label, this.icon);

  final String label;

  /// PNG bytes, or null when the icon could not be read. The same instance is
  /// handed out every time so the image decodes once for the whole list.
  final Uint8List? icon;
}

/// The apps installed on this device, as `retrotoolbox/native` reports them:
/// Save Sync's picker and rows, and the app drawer of the home screen.
/// Silent where there is no platform side, so widget tests see nothing
/// instead of an error.
class InstalledApps {
  const InstalledApps([this._channel = const MethodChannel('retrotoolbox/native')]);

  final MethodChannel _channel;

  /// Icons and labels for this process's life, shared by every caller. The
  /// same [AppInfo] instance is handed back every time, so a list decodes
  /// each PNG once instead of once per rebuild. Packages that answered with
  /// nothing are remembered too, so one the device cannot show is not asked
  /// about on every refresh.
  static final _cache = <String, AppInfo?>{};

  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// Every app with a launcher entry but this one, by label. Icons come
  /// along, since the same call already has the package manager open.
  Future<List<({String package, AppInfo info})>> launchable() async {
    try {
      final got = await _channel.invokeListMethod<Object?>('launchableApps');
      final out = <({String package, AppInfo info})>[];
      for (final e in got ?? const []) {
        if (e is! Map) continue;
        final package = e['package'];
        if (package is! String) continue;
        final info = AppInfo((e['label'] as String?) ?? package, e['icon'] is Uint8List ? e['icon'] as Uint8List : null);
        _cache[package] = info;
        out.add((package: package, info: info));
      }
      out.sort((a, b) => a.info.label.toLowerCase().compareTo(b.info.label.toLowerCase()));
      return out;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// The icon and label of each of [packages] Android can show. One call for
  /// every package not asked about yet.
  Future<Map<String, AppInfo>> info(Iterable<String> packages) async {
    final wanted = {for (final p in packages) p};
    final missing = [for (final p in wanted) if (!_cache.containsKey(p)) p];
    if (missing.isNotEmpty) {
      try {
        final got = await _channel.invokeMapMethod<String, dynamic>('appInfo', {'packages': missing});
        for (final p in missing) {
          final e = got?[p];
          _cache[p] = e is Map ? AppInfo((e['label'] as String?) ?? '', e['icon'] is Uint8List ? e['icon'] as Uint8List : null) : null;
        }
      } on MissingPluginException {
        for (final p in missing) {
          _cache[p] = null;
        }
      } on PlatformException {
        for (final p in missing) {
          _cache[p] = null;
        }
      }
    }
    return {
      for (final p in wanted)
        if (_cache[p] != null) p: _cache[p]!,
    };
  }
}

final installedAppsProvider = Provider<InstalledApps>((ref) => const InstalledApps());
