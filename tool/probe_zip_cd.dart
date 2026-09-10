// Lê o diretório central de um ZIP remoto por Range e imprime as entradas.
// Roda fora do Flutter:
//   dart run tool/probe_zip_cd.dart <url>
import 'dart:io';

import 'package:roms_downloader/services/zip_central_directory.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('uso: dart run tool/probe_zip_cd.dart <url>');
    exitCode = 64;
    return;
  }
  final uri = Uri.parse(args.single);
  final entries =
      await ZipCentralDirectory.read(uri, ZipCentralDirectory.httpRangeFetch);
  if (entries == null) {
    stderr.writeln('nao deu para ler o diretorio central de $uri');
    exitCode = 1;
    return;
  }
  for (final entry in entries) {
    final marca = entry.crcMatchesRom ? 'ROM ' : '    ';
    print('$marca${entry.crc}  ${entry.name}');
  }
}
