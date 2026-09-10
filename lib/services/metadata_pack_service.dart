import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';

typedef PackFetch = Future<List<int>> Function(Uri uri);

/// Baixa, descompacta e cacheia os metadata packs. Recebe o diretório e a
/// função de rede por construtor para os testes rodarem sem disco de usuário
/// e sem rede.
class MetadataPackService {
  final Directory cacheDir;
  final PackFetch fetch;

  MetadataPackService({required this.cacheDir, required this.fetch});

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
      debugPrint('Pacote $packId corrompido em disco, descartando: $e');
      await file.delete();
      return null;
    }
  }

  Future<PackIndex?> readCachedIndex() async {
    if (!await indexFile.exists()) return null;
    try {
      return PackIndex.decode(await indexFile.readAsString());
    } catch (e) {
      debugPrint('Indice de pacotes corrompido em disco, descartando: $e');
      await indexFile.delete();
      return null;
    }
  }

  /// Ids dos pacotes em disco. O index.json não conta.
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
