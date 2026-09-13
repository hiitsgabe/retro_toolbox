import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';

typedef PackFetch = Future<List<int>> Function(Uri uri);

/// Downloads, decompresses, and caches the metadata packs.
class MetadataPackService {
  final Directory cacheDir;
  final PackFetch fetch;

  MetadataPackService({required this.cacheDir, required this.fetch});

  /// Fixed-tag release, updated in place by the metadata-packs workflow. A
  /// fixed tag means a stable URL and no GitHub API calls from the app.
  static const releaseBase =
      'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs';

  /// Time cap on the whole future: `connectionTimeout` only bounds connect, so
  /// a connection that accepts then goes mute would hang the read forever.
  static const httpTimeout = Duration(seconds: 180);

  static Future<List<int>> httpFetch(Uri uri,
      {Duration timeout = httpTimeout}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      return await () async {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${response.statusCode}', uri: uri);
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        return bytes;
      }()
          .timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }

  Uri packUri(String packId) => Uri.parse('$releaseBase/$packId.json.gz');
  Uri indexUri() => Uri.parse('$releaseBase/$indexFileName');

  Future<MetadataPack> download(String packId) async {
    final compressed = await fetch(packUri(packId));
    final jsonStr = utf8.decode(gzip.decode(compressed));
    await writeCache(packId, jsonStr);
    return MetadataPack.decode(jsonStr);
  }

  Future<PackIndex> downloadIndex() async {
    final jsonStr = utf8.decode(await fetch(indexUri()));
    await writeCacheIndex(jsonStr);
    return PackIndex.decode(jsonStr);
  }

  /// Cache first, then network, then cache again if the network fails. Null
  /// only when neither exists.
  Future<MetadataPack?> load(String packId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await readCached(packId);
      if (cached != null) return cached;
    }
    try {
      return await download(packId);
    } catch (e) {
      debugPrint('Failed to download pack $packId: $e');
      return readCached(packId);
    }
  }

  Future<PackIndex?> loadIndex({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await readCachedIndex();
      if (cached != null) return cached;
    }
    try {
      return await downloadIndex();
    } catch (e) {
      debugPrint('Failed to download the pack index: $e');
      return readCachedIndex();
    }
  }

  static const indexFileName = 'index.json';

  File packFile(String packId) => File(p.join(cacheDir.path, '$packId.json'));
  File get indexFile => File(p.join(cacheDir.path, indexFileName));

  Future<void> writeCache(String packId, String jsonStr) async {
    final file = packFile(packId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonStr);
  }

  Future<void> writeCacheIndex(String jsonStr) async {
    await indexFile.parent.create(recursive: true);
    await indexFile.writeAsString(jsonStr);
  }

  Future<MetadataPack?> readCached(String packId) async {
    final file = packFile(packId);
    if (!await file.exists()) return null;
    try {
      return MetadataPack.decode(await file.readAsString());
    } catch (e) {
      debugPrint('Pack $packId corrupt on disk, discarding: $e');
      await file.delete();
      return null;
    }
  }

  Future<PackIndex?> readCachedIndex() async {
    if (!await indexFile.exists()) return null;
    try {
      return PackIndex.decode(await indexFile.readAsString());
    } catch (e) {
      debugPrint('Pack index corrupt on disk, discarding: $e');
      await indexFile.delete();
      return null;
    }
  }

  /// Ids of the packs on disk. index.json does not count.
  Future<List<String>> cachedPacks() async {
    if (!await cacheDir.exists()) return [];
    final ids = <String>[];
    await for (final entity in cacheDir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == indexFileName || !name.endsWith('.json')) continue;
      ids.add(name.substring(0, name.length - '.json'.length));
    }
    return ids;
  }

  Future<void> evict(String packId) async {
    final file = packFile(packId);
    if (await file.exists()) await file.delete();
  }
}
