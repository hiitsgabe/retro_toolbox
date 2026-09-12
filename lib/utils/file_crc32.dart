import 'dart:io';

import 'package:archive/archive.dart';

/// CRC32 de um arquivo local, lido em pedaços.
///
/// O `getCrc32` recebe o CRC anterior como segundo argumento e continua de
/// onde parou, então nunca precisamos do arquivo inteiro na memória.
Future<String> crc32OfFile(File file) async {
  var crc = 0;
  await for (final chunk in file.openRead()) {
    crc = getCrc32(chunk, crc);
  }
  return formatCrc(crc);
}

/// Oito dígitos hexadecimais em maiúsculas, que é como o DAT escreve e como o
/// `PackDump.crc` guarda. Sem isso a comparação vira uma loteria de caixa.
String formatCrc(int crc) =>
    (crc & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0');
