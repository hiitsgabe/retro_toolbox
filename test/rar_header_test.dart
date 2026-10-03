import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/rar_header.dart';

/// RAR5 variable-length integer: 7 bits per byte, high bit = more.
List<int> vint(int v) {
  final out = <int>[];
  do {
    var b = v & 0x7f;
    v >>= 7;
    if (v > 0) b |= 0x80;
    out.add(b);
  } while (v > 0);
  return out;
}

/// One RAR5 header block: CRC (ignored by the reader), size, then [body]
/// (type, flags, ...), followed by [data] bytes of payload.
List<int> rar5Block(List<int> body, {List<int> data = const []}) => [0, 0, 0, 0, ...vint(body.length), ...body, ...data];

List<int> rar5File(int unpacked, List<int> payload, {bool dir = false}) => rar5Block([
      ...vint(2), // type: file
      ...vint(0x0002), // flags: has data size
      ...vint(payload.length), // data size
      ...vint(dir ? 0x0001 : 0), // file flags (0x1 = directory)
      ...vint(unpacked),
      ...vint(0), // attributes
    ], data: payload);

List<int> le16(int v) => [v & 0xff, v >> 8];
List<int> le32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];

/// RAR4 file block: 7-byte base + fixed fields + name, then [packed] payload.
List<int> rar4File(int unpacked, int packed, {int high = 0}) {
  const name = 'f.bin';
  final flags = 0x8000 | (high > 0 ? 0x100 : 0);
  final fields = [
    ...le32(packed), ...le32(unpacked & 0xffffffff), 0, ...le32(0), ...le32(0), 29, 0x30,
    ...le16(name.length), ...le32(0),
    if (high > 0) ...[...le32(0), ...le32(high)],
    ...name.codeUnits,
  ];
  return [...le16(0), 0x74, ...le16(flags), ...le16(7 + fields.length), ...fields, ...List.filled(packed, 0)];
}

String write(List<int> bytes) {
  final f = File('${Directory.systemTemp.createTempSync('rarh').path}/a.rar')..writeAsBytesSync(Uint8List.fromList(bytes));
  return f.path;
}

void main() {
  test('sums the unpacked sizes of a RAR5 archive, skipping payloads and folders', () {
    final path = write([
      0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00,
      ...rar5Block([...vint(1), ...vint(0), ...vint(0)]), // main header
      ...rar5File(5000000000, [1, 2, 3]), // > 4 GB: vint, no 32-bit cap
      ...rar5File(0, [], dir: true),
      ...rar5File(1234, [9, 9]),
      ...rar5Block([...vint(5), ...vint(0), ...vint(0)]), // end of archive
    ]);
    expect(rarUnpackedSize(path), 5000000000 + 1234);
  });

  test('sums the unpacked sizes of a RAR4 archive, including the high 32 bits', () {
    final path = write([
      0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00,
      ...le16(0), 0x73, ...le16(0), ...le16(13), ...List.filled(6, 0), // main header
      ...rar4File(700, 10),
      ...rar4File(0x10, 3, high: 1), // 4 GB + 16
      ...le16(0), 0x7b, ...le16(0), ...le16(7), // end
    ]);
    expect(rarUnpackedSize(path), 700 + 0x100000010);
  });

  test('is null for something that is not a RAR', () {
    expect(rarUnpackedSize(write([1, 2, 3, 4, 5, 6, 7, 8, 9])), isNull);
  });
}
