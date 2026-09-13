import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/services/metadata_pack_service.dart';

/// The real service, pointing at `<support>/packs`.
final metadataPackServiceProvider =
    FutureProvider<MetadataPackService>((ref) async {
  final supportDir = await getApplicationSupportDirectory();
  return MetadataPackService(
    cacheDir: Directory(p.join(supportDir.path, 'packs')),
    fetch: MetadataPackService.httpFetch,
  );
});

/// The release index.json. Null when it could not be fetched and has no cache.
final packIndexProvider = FutureProvider<PackIndex?>((ref) async {
  final service = await ref.watch(metadataPackServiceProvider.future);
  return service.loadIndex();
});

/// A catalog console's pack. Null when the console has no pack, as with the
/// Nintendo Switch and any hand-added console that matches no alias.
final metadataPackProvider =
    FutureProvider.family<MetadataPack?, PackTarget>((ref, target) async {
  final index = await ref.watch(packIndexProvider.future);
  if (index == null) return null;
  final entry = index.resolve(target);
  if (entry == null) return null;
  final service = await ref.watch(metadataPackServiceProvider.future);
  return service.load(entry.pack);
});
