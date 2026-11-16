import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Where recipes are published when nothing else says otherwise: the repo's
/// own folder, read raw from main.
const defaultCatalogBase = 'https://raw.githubusercontent.com/hiitsgabe/retro_toolbox/main/save_recipes/';

/// [raw] as a catalog base: trimmed, https only, no query or fragment, ending
/// in a slash. Null when it cannot be one, so an invalid value is never
/// stored or used.
String? normalizeCatalogUrl(String raw) {
  final t = raw.trim();
  final u = Uri.tryParse(t);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  // `<id>.json` is appended to the base, so a query or a fragment would
  // swallow the file name.
  if (u.hasQuery || u.hasFragment) return null;
  return t.endsWith('/') ? t : '$t/';
}

/// The base recipes are read from: the owner's setting, then the build's
/// `SAVE_SYNC_CATALOG_URL`, then [defaultCatalogBase].
String resolveCatalogBase({String? setting, String define = ''}) {
  for (final candidate in [setting ?? '', define]) {
    final n = normalizeCatalogUrl(candidate);
    if (n != null) return n;
  }
  return defaultCatalogBase;
}

/// One cache folder per base, so switching sources never mixes two catalogs.
Directory catalogCacheDir(String supportDir, String base) =>
    Directory('$supportDir/save_sync/catalog/${sha256.convert(utf8.encode(base)).toString().substring(0, 16)}');
