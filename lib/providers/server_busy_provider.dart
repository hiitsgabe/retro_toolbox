import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';

/// True while anything is moving data; the server-mode watchdog reads it via
/// the busy file. Only read in server mode.
// ponytail: FTP server transfers not counted; add a counter in FtpServerService if restarts ever cut one.
final serverBusyProvider = Provider<bool>((ref) {
  return ref.watch(downloadProvider.select((s) => s.downloading)) ||
      ref.watch(taskQueueProvider.select((s) => s.isProcessing)) ||
      ref.watch(extractionProvider.select((s) => s.isExtracting)) ||
      ref.watch(fbiServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(tinfoilServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(fpkgiServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(rtsServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(jdkvServerProvider.select((s) => s.activeTransfers > 0)) ||
      ref.watch(ftpProvider.select((s) => s.transfer != null));
});

/// Creates ([busy]) or removes the busy file. Path defaults to
/// `RETRO_TOOLBOX_BUSY_FILE`; null/empty is a no-op.
Future<void> writeBusyFlag(bool busy, {String? path}) {
  // Serialised so overlapping unawaited calls apply in order.
  return _last = _last.then((_) => _write(busy, path));
}

Future<void> _last = Future.value();

Future<void> _write(bool busy, String? path) async {
  final p = path ?? Platform.environment['RETRO_TOOLBOX_BUSY_FILE'];
  if (p == null || p.isEmpty) return;
  final f = File(p);
  try {
    if (busy) {
      await f.create(recursive: true);
    } else if (await f.exists()) {
      await f.delete();
    }
  } on FileSystemException {
    // Flag is best-effort; never take the app down.
  }
}
