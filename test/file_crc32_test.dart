import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/utils/file_crc32.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('file_crc32_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('formatCrc dá oito dígitos em maiúsculas com zero à esquerda', () {
    expect(formatCrc(0), '00000000');
    expect(formatCrc(0xABCDE), '000ABCDE');
    expect(formatCrc(0xA31BEAD4), 'A31BEAD4');
  });

  test('crc32OfFile bate com o CRC do conteúdo inteiro', () async {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final file = File('${tmp.path}/pequeno.sfc')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });

  test('encadeia certo em arquivo grande o bastante para virar vários pedaços',
      () async {
    // 512 KB força o openRead a entregar mais de um chunk. Se o encadeamento
    // do getCrc32 estivesse errado, este teste seria o único a pegar.
    final bytes = Uint8List.fromList(List.generate(512 * 1024, (i) => i % 253));
    final file = File('${tmp.path}/grande.iso')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });
}
