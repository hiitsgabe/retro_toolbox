import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// One recipe as the published index describes it. The body is not here: an
/// index of a few KB stays instant for hundreds of entries, and a body is
/// fetched only for an app somebody chose.
class IndexEntry {
  const IndexEntry({required this.id, required this.packages, required this.status, this.sha256});

  final String id;
  final List<String> packages;
  final String status;

  /// Of the recipe file's bytes. A kept body with this hash is current; null
  /// for an index written before hashes, which never trusts a kept body.
  final String? sha256;

  static IndexEntry? parse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final packages = j['packages'];
    if (id is! String || packages is! List) return null;
    return IndexEntry(
      id: id,
      packages: [for (final p in packages) if (p is String) p],
      status: j['status'] is String ? j['status'] as String : 'draft',
      sha256: j['sha256'] is String ? j['sha256'] as String : null,
    );
  }
}

/// The published index, already fanned out by package.
class RecipeCatalog {
  RecipeCatalog(this.entries, {this.fetchedAt, this.fromCache = false})
      : byPackage = {
          for (final e in entries)
            for (final p in e.packages) p: e,
        };

  static final empty = RecipeCatalog(const []);

  final List<IndexEntry> entries;

  /// Lookup is exact, by package id. No matcher, no fuzzy score, so a
  /// near-miss can never quietly pick the wrong recipe, and one unmatched app
  /// never blocks the others.
  final Map<String, IndexEntry> byPackage;

  /// When this copy was fetched, for the quiet age line.
  final DateTime? fetchedAt;

  /// True when the network could not be reached and this is what was kept.
  final bool fromCache;

  bool get isEmpty => entries.isEmpty;
}

/// Reads a published catalog of recipes: `index.json` and one `<id>.json`
/// per recipe beside it, plain files over HTTPS. No API, no auth, no rate
/// limit, and it works from its cache with no network at all.
///
/// Never a precondition: setup, adopting a hub, the list, uploads and
/// downloads all work with this unreachable, because the hub carries the
/// recipe bodies another device needs.
class RecipeIndex {
  RecipeIndex({required this.baseUrl, required this.cacheDir, HttpClient Function()? client})
      : _client = client ?? (() => HttpClient()..connectionTimeout = const Duration(seconds: 10));

  /// Where the catalog is published.
  final String baseUrl;

  /// Holds this one catalog's index and bodies; another base gets another folder.
  final Directory cacheDir;
  final HttpClient Function() _client;

  File get _indexFile => File('${cacheDir.path}/index.json');
  File get _etagFile => File('${cacheDir.path}/index.etag');

  /// The catalog. Every call asks, conditionally, so an unchanged catalog is
  /// a 304 with no body and a fix is seen at once. A fetch that fails falls
  /// back to the cache rather than to an error: stale but known beats
  /// confidently wrong, and nothing on screen turns red because the network
  /// is down.
  Future<RecipeCatalog> load({DateTime? now}) async {
    final cached = await _readCache();
    try {
      final (body, etag) = await _fetch('index.json', etag: cached == null ? null : await _readEtag());
      if (body == null) {
        // 304: what is cached is still current.
        await _touch();
        return _parse(cached?.$1 ?? '{}', fetchedAt: now ?? DateTime.now(), fromCache: false);
      }
      await cacheDir.create(recursive: true);
      await _indexFile.writeAsString(body);
      if (etag != null) await _etagFile.writeAsString(etag);
      return _parse(body, fetchedAt: now ?? DateTime.now(), fromCache: false);
    } catch (_) {
      if (cached == null) return RecipeCatalog.empty;
      return _parse(cached.$1, fetchedAt: cached.$2, fromCache: true);
    }
  }

  /// [entry]'s recipe body as the index describes it. A kept copy with the
  /// index's sha256 is used without asking. Otherwise the body is downloaded,
  /// and kept only when its sha256 matches: a CDN still serving the old file
  /// never replaces a good copy. Unreachable or mismatched falls back to
  /// whatever was kept; null when nothing was.
  Future<Map<String, dynamic>?> ensureBody(IndexEntry entry) async {
    final file = File('${cacheDir.path}/${entry.id}.json');
    final kept = await file.exists() ? await file.readAsString() : null;
    if (kept != null && entry.sha256 != null && _sha(kept) == entry.sha256) return _object(kept);
    try {
      final (body, _) = await _fetch('${entry.id}.json');
      if (body != null && (entry.sha256 == null || _sha(body) == entry.sha256)) {
        await cacheDir.create(recursive: true);
        await file.writeAsString(body);
        return _object(body);
      }
    } catch (_) {
      // Falls through to whatever was kept.
    }
    return kept == null ? null : _object(kept);
  }

  static String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

  static Map<String, dynamic>? _object(String text) {
    try {
      final j = jsonDecode(text);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Body text, or null for a 304. Throws when the fetch itself fails.
  Future<(String?, String?)> _fetch(String path, {String? etag}) async {
    final client = _client();
    try {
      final request = await client.getUrl(Uri.parse('${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}$path'));
      if (etag != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, etag);
      final response = await request.close();
      if (response.statusCode == HttpStatus.notModified) {
        await response.drain<void>();
        return (null, etag);
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('${response.statusCode} for $path');
      }
      return (await response.transform(utf8.decoder).join(), response.headers.value(HttpHeaders.etagHeader));
    } finally {
      client.close(force: true);
    }
  }

  Future<(String, DateTime)?> _readCache() async {
    if (!await _indexFile.exists()) return null;
    return (await _indexFile.readAsString(), await _indexFile.lastModified());
  }

  Future<String?> _readEtag() async => await _etagFile.exists() ? _etagFile.readAsString() : null;

  Future<void> _touch() async {
    if (await _indexFile.exists()) await _indexFile.setLastModified(DateTime.now());
  }

  RecipeCatalog _parse(String body, {DateTime? fetchedAt, required bool fromCache}) {
    try {
      final j = jsonDecode(body);
      final list = j is Map ? j['recipes'] : null;
      if (list is! List) return RecipeCatalog(const [], fetchedAt: fetchedAt, fromCache: fromCache);
      return RecipeCatalog(
        [for (final e in list) if (IndexEntry.parse(e) case final parsed?) parsed],
        fetchedAt: fetchedAt,
        fromCache: fromCache,
      );
    } catch (_) {
      return RecipeCatalog(const [], fetchedAt: fetchedAt, fromCache: fromCache);
    }
  }
}
