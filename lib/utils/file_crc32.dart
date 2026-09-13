import 'dart:io';

import 'package:archive/archive.dart';

/// CRC32 of a local file, read in chunks so the whole file never needs to be
/// held in memory.
Future<String> crc32OfFile(File file) async {
  var crc = 0;
  await for (final chunk in file.openRead()) {
    crc = getCrc32(chunk, crc);
  }
  return formatCrc(crc);
}

/// Eight uppercase hex digits, matching how the DAT and `PackDump.crc` store
/// it. Warning: without this the comparison becomes case-dependent.
String formatCrc(int crc) =>
    (crc & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0');
