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

  test('formatCrc produces eight uppercase digits with leading zeros', () {
    expect(formatCrc(0), '00000000');
    expect(formatCrc(0xABCDE), '000ABCDE');
    expect(formatCrc(0xA31BEAD4), 'A31BEAD4');
  });

  test('crc32OfFile matches the CRC of the full file content', () async {
    final bytes = Uint8List.fromList(List.generate(1000, (i) => i % 251));
    final file = File('${tmp.path}/small.sfc')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });

  test('chains correctly on a file large enough to span multiple chunks',
      () async {
    // 512 KB forces openRead to deliver more than one chunk. A broken
    // getCrc32 chain would only be caught here.
    final bytes = Uint8List.fromList(List.generate(512 * 1024, (i) => i % 253));
    final file = File('${tmp.path}/large.iso')..writeAsBytesSync(bytes);
    expect(await crc32OfFile(file), formatCrc(getCrc32(bytes)));
  });
}
