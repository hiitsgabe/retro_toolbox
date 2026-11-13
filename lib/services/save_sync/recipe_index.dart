import 'dart:convert';
import 'dart:io';

/// One recipe as the published index describes it. The body is not here: an
/// index of a few KB stays instant for hundreds of entries, and a body is
/// fetched only when a row is previewed or added.
class IndexEntry {
  const IndexEntry({required this.id, required this.packages, required this.status, required this.updated});

  final String id;
  final List<String> packages;
  final String status;
  final DateTime? updated;

  static IndexEntry? parse(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    final packages = j['packages'];
    if (id is! String || packages is! List) return null;
    return IndexEntry(
      id: id,
      packages: [for (final p in packages) if (p is String) p],
      status: j['status'] is String ? j['status'] as String : 'draft',
      updated: DateTime.tryParse('${j['updated']}'),
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

/// Reads a published catalog of recipes: one static index and one file per
/// recipe, plain files over HTTPS. No API, no auth, no rate limit, and it
/// works from its cache with no network at all.
///
/// Never a precondition: setup, adopting a hub, the list, uploads and
/// downloads all work with this unreachable, because the hub carries the
/// recipe bodies another device needs.
class RecipeIndex {
  RecipeIndex({required this.baseUrl, required this.cacheDir, HttpClient Function()? client})
      : _client = client ?? (() => HttpClient()..connectionTimeout = const Duration(seconds: 10));

  /// Where the catalog is published. Never committed: it is seeded from a
  /// build's own ignored asset or set by the owner.
  final String baseUrl;

  final Directory cacheDir;
  final HttpClient Function() _client;

  /// How long a copy is used before another fetch is even attempted.
  static const maxAge = Duration(hours: 24);

  File get _indexFile => File('${cacheDir.path}/index.json');
  File get _etagFile => File('${cacheDir.path}/index.etag');

  /// The catalog, fetched when the cached copy is older than [maxAge] or
  /// [force] says so. A fetch that fails falls back to the cache rather than
  /// to an error: stale but known beats confidently wrong, and nothing on
  /// screen turns red because the network is down.
  Future<RecipeCatalog> load({bool force = false, DateTime? now}) async {
    final cached = await _readCache();
    final at = cached?.$2;
    final fresh = at != null && (now ?? DateTime.now()).difference(at) < maxAge;
    if (!force && fresh) return _parse(cached!.$1, fetchedAt: at, fromCache: false);

    try {
      final (body, etag) = await _fetch('index.json', etag: await _readEtag());
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
      return _parse(cached.$1, fetchedAt: at, fromCache: true);
    }
  }

  /// One recipe's body, from the cache when it is there. Returns null when the
  /// catalog has nothing for that id and could not be reached.
  Future<Map<String, dynamic>?> body(String id) async {
    final file = File('${cacheDir.path}/recipes/$id.json');
    try {
      final (body, _) = await _fetch('recipes/$id.json');
      if (body != null) {
        await file.parent.create(recursive: true);
        await file.writeAsString(body);
        final j = jsonDecode(body);
        return j is Map<String, dynamic> ? j : null;
      }
    } catch (_) {
      // Falls through to whatever was kept.
    }
    if (!await file.exists()) return null;
    try {
      final j = jsonDecode(await file.readAsString());
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
