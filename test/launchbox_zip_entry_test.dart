import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launchbox/zip_entry_stream.dart';

/// A few hundred KB of text that repeats loosely, so deflate shrinks it but
/// not to nothing.
List<int> sampleText() {
  final b = StringBuffer();
  for (var i = 0; i < 12000; i++) {
    b.writeln('<Game><Name>Game number $i</Name><DatabaseID>${i * 7919 % 100003}</DatabaseID></Game>');
  }
  return utf8.encode(b.toString());
}

Future<List<int>> readAll(Stream<List<int>> s) async => [for (final chunk in await s.toList()) ...chunk];

/// A one-entry stored zip, packed by hand because ZipEncoder always writes
/// the same extra field in both headers and never sets flag bit 3. Here the
/// local header has 9 extra bytes the central directory does not, and its
/// sizes are 0, with the real ones in a data descriptor after the data.
/// [centralNameLength] lets a test claim a name longer than what is there.
List<int> handPackedZip(String name, List<int> data, {int? centralNameLength}) {
  final nameBytes = utf8.encode(name);
  final b = BytesBuilder();
  void u16(int v) => b.add([v & 0xff, v >> 8 & 0xff]);
  void u32(int v) => b.add([v & 0xff, v >> 8 & 0xff, v >> 16 & 0xff, v >> 24 & 0xff]);

  // Local header: version, flags (bit 3), stored, time, date, then crc and
  // both sizes left at 0 for the descriptor.
  u32(0x04034b50);
  [20, 0x0008, 0, 0, 0].forEach(u16);
  [0, 0, 0].forEach(u32);
  u16(nameBytes.length);
  u16(9);
  b.add(nameBytes);
  b.add([0xfe, 0xca, 5, 0, 1, 2, 3, 4, 5]);
  b.add(data);
  [0x08074b50, 0, data.length, data.length].forEach(u32);

  // Central record: made by, needed, flags, method, time, date, crc, sizes,
  // then name, extra, comment, disk, internal and external attributes and
  // the local header offset.
  final dirOffset = b.length;
  u32(0x02014b50);
  [20, 20, 0x0008, 0, 0, 0].forEach(u16);
  [0, data.length, data.length].forEach(u32);
  [centralNameLength ?? nameBytes.length, 0, 0, 0, 0].forEach(u16);
  [0, 0].forEach(u32);
  b.add(nameBytes);
  final dirSize = b.length - dirOffset;

  u32(0x06054b50);
  [0, 0, 1, 1].forEach(u16);
  u32(dirSize);
  u32(dirOffset);
  u16(0);
  return b.takeBytes();
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('lb_zip_'));
  tearDown(() => dir.deleteSync(recursive: true));

  String writeZip(List<ArchiveFile> files) {
    final archive = Archive();
    files.forEach(archive.addFile);
    final path = '${dir.path}/test.zip';
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return path;
  }

  test('a deflated entry streams back byte-identical', () async {
    final data = sampleText();
    final zip = writeZip([ArchiveFile('Metadata.xml', data.length, data)]);
    final entry = await findZipEntry(zip, 'Metadata.xml');
    expect(entry.method, 8);
    expect(entry.compressedSize, lessThan(data.length));
    expect(entry.uncompressedSize, data.length);
    expect(await readAll(zipEntryStream(zip, entry)), data);
  });

  test('a stored entry streams back identical', () async {
    final data = sampleText();
    final zip = writeZip([ArchiveFile.noCompress('Metadata.xml', data.length, data)]);
    final entry = await findZipEntry(zip, 'Metadata.xml');
    expect(entry.method, 0);
    expect(entry.compressedSize, data.length);
    expect(await readAll(zipEntryStream(zip, entry)), data);
  });

  test('the second of three entries is found by name', () async {
    List<int> bytes(String s) => utf8.encode(s * 50);
    final zip = writeZip([
      ArchiveFile('a.txt', 50, bytes('a')),
      ArchiveFile('Metadata.xml', 150, bytes('mid')),
      ArchiveFile('c.txt', 50, bytes('c')),
    ]);
    final entry = await findZipEntry(zip, 'Metadata.xml');
    expect(utf8.decode(await readAll(zipEntryStream(zip, entry))), 'mid' * 50);
  });

  test('a missing name throws FormatException', () async {
    final zip = writeZip([ArchiveFile('a.txt', 1, [0x41])]);
    await expectLater(findZipEntry(zip, 'Metadata.xml'), throwsFormatException);
  });

  test('a non-zip file throws FormatException', () async {
    final path = '${dir.path}/not.zip';
    File(path).writeAsBytesSync(utf8.encode('just some text, no zip here' * 100));
    await expectLater(findZipEntry(path, 'Metadata.xml'), throwsFormatException);
  });

  test('data offset comes from the local header, sizes from the central directory', () async {
    final data = utf8.encode('stored behind a data descriptor ' * 40);
    final path = '${dir.path}/hand.zip';
    File(path).writeAsBytesSync(handPackedZip('Metadata.xml', data));
    final entry = await findZipEntry(path, 'Metadata.xml');
    expect(entry.compressedSize, data.length);
    expect(await readAll(zipEntryStream(path, entry)), data);
  });

  test('a name running past the directory throws FormatException', () async {
    final path = '${dir.path}/hand.zip';
    File(path).writeAsBytesSync(handPackedZip('Metadata.xml', [1, 2, 3], centralNameLength: 400));
    await expectLater(findZipEntry(path, 'Metadata.xml'), throwsFormatException);
  });

  test('a deflate stream cut short throws FormatException', () async {
    final data = sampleText();
    final zip = writeZip([ArchiveFile('Metadata.xml', data.length, data)]);
    final entry = await findZipEntry(zip, 'Metadata.xml');
    final cut = ZipEntryInfo(
      dataOffset: entry.dataOffset,
      compressedSize: entry.compressedSize ~/ 2,
      uncompressedSize: entry.uncompressedSize,
      method: entry.method,
    );
    await expectLater(readAll(zipEntryStream(zip, cut)), throwsFormatException);
  });

  test('onCompressedRead ends at compressedSize', () async {
    final data = sampleText();
    final zip = writeZip([ArchiveFile('Metadata.xml', data.length, data)]);
    final entry = await findZipEntry(zip, 'Metadata.xml');
    final counts = <int>[];
    await readAll(zipEntryStream(zip, entry, onCompressedRead: counts.add));
    expect(counts, isNotEmpty);
    expect(counts.last, entry.compressedSize);
  });
}
