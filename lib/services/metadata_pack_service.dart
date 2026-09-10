import 'dart:convert';
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

  /// Release de tag fixa, atualizada no lugar pelo workflow metadata-packs.
  /// Tag fixa significa URL estável e zero chamadas à API do GitHub no app.
  static const releaseBase =
      'https://github.com/hiitsgabe/retro_toolbox/releases/download/packs';

  /// Fetch padrão de produção. Segue redirect, que a release do GitHub sempre
  /// devolve.
  ///
  /// Teto de tempo igual ao lado Python (`timeout=180`). O `connectionTimeout`
  /// limita só a fase de connect; o `.timeout` no futuro inteiro é que segura
  /// uma conexão que aceita e depois emudece, senão o `await for` da leitura
  /// penduraria para sempre. Numa primeira carga sem cache isso travaria a
  /// tela; com o teto, vira exceção e `load` cai no cache.
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

  /// Cache primeiro, rede depois, cache de novo se a rede falhar. Null só
  /// quando não existe nem uma coisa nem a outra.
  Future<MetadataPack?> load(String packId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = await readCached(packId);
      if (cached != null) return cached;
    }
    try {
      return await download(packId);
    } catch (e) {
      debugPrint('Falha ao baixar o pacote $packId: $e');
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
      debugPrint('Falha ao baixar o indice de pacotes: $e');
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
