import 'dart:convert';
import 'dart:io';

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
