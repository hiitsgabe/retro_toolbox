import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

/// O serviço real, apontando para `<support>/packs`. Os testes sobrescrevem
/// este provider com um serviço de diretório temporário e fetch falso.
final metadataPackServiceProvider =
    FutureProvider<MetadataPackService>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  return MetadataPackService(
    cacheDir: Directory(p.join(supportDir.path, 'packs')),
    fetch: MetadataPackService.httpFetch,
  );
});

/// O index.json da release. Null quando não deu para baixar e não tem cache.
final packIndexProvider = FutureProvider<PackIndex?>((ref) async {
  final service = await ref.watch(metadataPackServiceProvider.future);
  return service.loadIndex();
});

/// O pacote de um console do catálogo. Null quando o console não tem pacote,
/// que é o caso do Nintendo Switch e de qualquer console adicionado à mão que
/// não bata com nenhum alias.
final metadataPackProvider =
    FutureProvider.family<MetadataPack?, PackTarget>((ref, target) async {
  final index = await ref.watch(packIndexProvider.future);
  if (index == null) return null;
  final entry = index.resolve(target);
  if (entry == null) return null;
  final service = await ref.watch(metadataPackServiceProvider.future);
  return service.load(entry.pack);
});
