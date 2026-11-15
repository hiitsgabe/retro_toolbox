import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/services/sports_service.dart';

/// True while anything is moving data; the server-mode watchdog reads it via
/// the busy file. Only read in server mode.
// ponytail: FTP server transfers not counted (risk accepted: a restart can cut one); add a counter in
// FtpServerService if that ever bites.
final serverBusyProvider = Provider<bool>((ref) {
  return ref.watch(downloadProvider.select((s) => s.downloading)) ||
      ref.watch(taskQueueProvider.select((s) => s.isProcessing)) ||
      ref.watch(extractionProvider.select((s) => s.isExtracting)) ||
      ref.watch(fbiServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(tinfoilServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(fpkgiServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(rtsServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(jdkvServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(ftpProvider.select((s) => s.transfer != null)) ||
      ref.watch(smbProvider.select((s) => s.transfer != null)) ||
      ref.watch(saveSyncProvider.select((s) => s.busyRecipe != null)) ||
      ref.watch(_patchingProvider);
});

/// Bridges [SportsService.patchesInFlight] (a roster patch runs in the wizard's own state).
final _patchingProvider = Provider<bool>((ref) {
  final n = SportsService.patchesInFlight;
  void changed() => ref.invalidateSelf();
  n.addListener(changed);
  ref.onDispose(() => n.removeListener(changed));
  return n.value > 0;
});

/// Creates ([busy]) or removes the busy file. Path defaults to
/// `RETRO_TOOLBOX_BUSY_FILE`; null/empty is a no-op.
Future<void> writeBusyFlag(bool busy, {String? path}) {
  // Serialised so overlapping unawaited calls apply in order; a failed write never blocks the next.
  return _last = _last.then((_) => _write(busy, path)).catchError((Object e) {
    debugPrint('busy flag: $e');
  });
}

Future<void> _last = Future.value();

Future<void> _write(bool busy, String? path) async {
  final p = path ?? Platform.environment['RETRO_TOOLBOX_BUSY_FILE'];
  if (p == null || p.isEmpty) return;
  final f = File(p);
  // Best-effort; errors land in writeBusyFlag's catchError.
  if (busy) {
    await f.create(recursive: true);
  } else if (await f.exists()) {
    await f.delete();
  }
}
