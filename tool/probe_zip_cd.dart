// Reads the central directory of a remote ZIP over Range and prints the
// entries. Runs outside Flutter:
//   dart run tool/probe_zip_cd.dart <url>
import 'dart:io';

import 'package:roms_downloader/services/zip_central_directory.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('usage: dart run tool/probe_zip_cd.dart <url>');
    exitCode = 64;
    return;
  }
  final uri = Uri.parse(args.single);
  final entries =
      await ZipCentralDirectory.read(uri, ZipCentralDirectory.httpRangeFetch);
  if (entries == null) {
    stderr.writeln('could not read the central directory of $uri');
    exitCode = 1;
    return;
  }
  for (final entry in entries) {
    final mark = entry.crcMatchesRom ? 'ROM ' : '    ';
    print('$mark${entry.crc}  ${entry.name}');
  }
}
