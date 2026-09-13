import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Where the selected console's library sits on disk.
final libraryDirProvider = Provider<String?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  // Watch the state, call on the notifier: the pair recomputes this provider
  // when the user changes the download folder.
  ref.watch(settingsProvider);
  final dir = ref.read(settingsProvider.notifier).getDownloadDir(target.consoleId);
  return dir.isEmpty ? null : dir;
});

/// The `PackGame.id`s that already have some version on disk. One scan per
/// console, never per tile: `identify` may compute CRC.
final ownedGameIdsProvider = FutureProvider<Set<String>>((ref) async {
  final target = ref.watch(packTargetProvider);
  final dir = ref.watch(libraryDirProvider);
  if (target == null || dir == null) return const <String>{};

  final identity = await ref.watch(localIdentityServiceProvider(target).future);
  if (identity == null) return const <String>{};

  final owned = <String>{};
  for (final file in await _libraryFiles(dir)) {
    if (!hasRomExtension(p.basename(file.path))) continue;
    final match = await identity.identify(file);
    // Skip the `guess` tier: a wrong border is worse than a missing one, so
    // only exact name, canonical title and CRC draw.
    if (match == null || match.confidence == MatchConfidence.guess) continue;
    owned.add(match.game.id);
  }
  return owned;
});

/// The files in the folder and one level below it. The extra level matches
/// `extractToFolder`, which puts an extracted ROM in `<folder>/<game name>/`.
Future<List<File>> _libraryFiles(String dir) async {
  final root = Directory(dir);
  if (!await root.exists()) return const [];

  final files = <File>[];
  try {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        try {
          await for (final sub in entity.list(followLinks: false)) {
            if (sub is File) files.add(sub);
          }
        } catch (_) {}
      }
    }
  } catch (_) {}
  return files;
}
