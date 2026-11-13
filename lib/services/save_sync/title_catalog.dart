import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What a console's own id means to a person.
class TitleInfo {
  const TitleInfo(this.name, this.image);

  final String name;

  /// Square art for it, when the catalog carries any.
  final String? image;
}

/// Names for the ids an emulator names its save folders after.
///
/// An emulator keeps one save per game in a folder named with the console's
/// own title id, so a row for one of them reads `0100000000ABC000` and means
/// nothing to the person holding the handheld. The catalog turns that id into
/// a name and a picture. It is a bundled list in the same shape as the box art
/// maps: `[{ "name": ..., "id": ..., "image": ... }]`.
///
/// ponytail: parsed once per process, never refreshed — it ships inside the
/// build, so it is exactly as fresh as the build is. Fetch it instead when a
/// title newer than the installed build has to resolve.
class TitleCatalog {
  static const asset = 'assets/boxarts/nsx.json';

  static Future<Map<String, TitleInfo>>? _once;

  static Future<Map<String, TitleInfo>> load({AssetBundle? bundle}) => _once ??= _load(bundle ?? rootBundle);

  @visibleForTesting
  static void reset() => _once = null;

  static Future<Map<String, TitleInfo>> _load(AssetBundle bundle) async {
    try {
      // Megabytes of JSON: parsed off the UI isolate, like the box art maps.
      return await compute(parseTitles, await bundle.loadString(asset));
    } catch (e) {
      // A build with no catalog, or a broken one. The ids stay as they are,
      // which is what the rows read before any of this existed.
      debugPrint('Title catalog unavailable: $e');
      return const {};
    }
  }
}

/// Keyed upper case, the case the save folders are named in.
@visibleForTesting
Map<String, TitleInfo> parseTitles(String body) {
  final out = <String, TitleInfo>{};
  final decoded = jsonDecode(body);
  if (decoded is! List) return out;
  for (final item in decoded) {
    if (item is! Map) continue;
    final id = (item['id'] as String?)?.toUpperCase() ?? '';
    final name = (item['name'] as String?) ?? '';
    if (id.isEmpty || name.isEmpty) continue;
    final image = item['image'] as String?;
    // First entry wins: a catalog listing a title once per region should not
    // have the last region decide the name.
    out[id] ??= TitleInfo(name, image == null || image.isEmpty ? null : image);
  }
  return out;
}
