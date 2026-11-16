import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// background_downloader stages every download in the app's private storage
/// under this name plus a random int, and only moves it out on success.
const downloaderTempPrefix = 'com.bbflight.background_downloader';

/// Deletes downloader staging files in [dirs] older than [minAge], returning
/// the bytes freed. A crash or kill mid-download leaves the staging file
/// behind and a restarted task picks a new name, so nothing else reclaims it.
/// Only call it while the downloader has no task: a live one is writing to
/// (or copying out of) one of these files. [minAge] covers a task enqueued
/// between that check and the sweep.
Future<int> sweepDownloaderTemps(Iterable<String> dirs, {DateTime? now, Duration minAge = const Duration(minutes: 2)}) async {
  final cutoff = (now ?? DateTime.now()).subtract(minAge);
  var freed = 0;
  for (final dir in dirs) {
    final directory = Directory(dir);
    if (!await directory.exists()) continue;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !p.basename(entity.path).startsWith(downloaderTempPrefix)) continue;
      try {
        final stat = await entity.stat();
        if (!stat.modified.isBefore(cutoff)) continue;
        await entity.delete();
        freed += stat.size;
      } catch (e) {
        debugPrint('Could not delete downloader staging file ${entity.path}: $e');
      }
    }
  }
  return freed;
}

/// The copy progress while the downloader moves a finished download out of
/// staging, or null when it is not doing that. Staging lives in internal
/// storage, so moving it to external storage or an SD card is a byte copy
/// that grows [destLength] up to [expectedSize]. The downloader caps its own
/// progress just short of 100% and reports nothing during the copy.
double? movingFraction({required int expectedSize, required int? destLength}) {
  if (expectedSize <= 0 || destLength == null || destLength >= expectedSize) return null;
  return destLength / expectedSize;
}
