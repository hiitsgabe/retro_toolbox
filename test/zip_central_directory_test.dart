import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

import 'support/zip_fixture.dart';

void main() {
  final uri = Uri.parse('https://example/file.zip');
  final entry = cdEntry('Crystal Vanguard (USA).sfc', 0x2D206BF7);

  test('returns exactly the central directory bytes', () async {
    final server = FakeRangeServer(buildZip([entry]));
    final raw = await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(raw, isNotNull);
    expect(raw, orderedEquals(entry));
  });

  test('makes two requests: the suffix and the exact range', () async {
    final server = FakeRangeServer(buildZip([entry], localBytes: 500));
    await ZipCentralDirectory.readRaw(uri, server.fetch);
    expect(server.asked, [
      'bytes=-256',
      'bytes=500-${500 + entry.length - 1}',
    ]);
  });

  test('finds the EOCD even with a TorrentZip comment after it', () async {
    final server = FakeRangeServer(
        buildZip([entry], comment: 'TORRENTZIPPED-58A7B7DC'));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch),
        orderedEquals(entry));
  });

  test('returns null when the server ignores Range and answers 200', () async {
    final server = FakeRangeServer(buildZip([entry]), status: 200);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('returns null when no Content-Range comes back', () async {
    final server =
        FakeRangeServer(buildZip([entry]), sendContentRange: false);
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('returns null on zip64', () async {
    final server = FakeRangeServer(buildZip([entry], zip64: true));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('returns null when the central directory falls outside the file', () async {
    final server = FakeRangeServer(buildZip([entry], forcedCdOffset: 900000));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
    expect(server.asked, ['bytes=-256']);
  });

  test('returns null when the EOCD does not fit the last 256 bytes', () async {
    final server =
        FakeRangeServer(buildZip([entry], comment: 'x' * 300));
    expect(await ZipCentralDirectory.readRaw(uri, server.fetch), isNull);
  });

  test('returns null when the network throws', () async {
    Future<RangeResponse> explode(Uri uri, String range) async =>
        throw const SocketException('no network');
    expect(await ZipCentralDirectory.readRaw(uri, explode), isNull);
  });

  group('entries', () {
    test('reads name and CRC of one entry', () {
      final entries = ZipCentralDirectory.parse(entry);
      expect(entries, hasLength(1));
      expect(entries!.single.name, 'Crystal Vanguard (USA).sfc');
      expect(entries.single.crc, '2D206BF7');
    });

    test('reads several entries even with extra and comment between them', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001, extraLen: 9))
        ..add(cdEntry('b.sfc', 0x000000FF, commentLen: 5))
        ..add(cdEntry('c.sfc', 0xA31BEAD4));
      final entries = ZipCentralDirectory.parse(blob.toBytes());
      expect(entries?.map((e) => e.name), ['a.sfc', 'b.sfc', 'c.sfc']);
      expect(entries?.map((e) => e.crc),
          ['00000001', '000000FF', 'A31BEAD4']);
    });

    test('crcMatchesRom accepts only the ROM itself', () {
      bool rom(String name) =>
          ZipCentralDirectory.parse(cdEntry(name, 1))!.single.crcMatchesRom;
      expect(rom('Crystal Vanguard (USA).sfc'), isTrue);
      expect(rom('Crystal Vanguard (USA).iso'), isTrue);
      // Container inside container: the CRC is of the archive, not the ROM.
      expect(rom('Crystal Vanguard (USA).zip'), isFalse);
      expect(rom('Crystal Vanguard (USA).7z'), isFalse);
      expect(rom('readme.txt'), isFalse);
    });

    test('stops at garbage and returns what it already read', () {
      final blob = BytesBuilder()
        ..add(cdEntry('a.sfc', 0x00000001))
        ..add(Uint8List.fromList(List.filled(60, 0x41)));
      expect(ZipCentralDirectory.parse(blob.toBytes())?.map((e) => e.name),
          ['a.sfc']);
    });

    test('read joins the two halves and delivers the entries', () async {
      final server = FakeRangeServer(buildZip([
        cdEntry('Super Pixel World (Europe).sfc', 0xA31BEAD4),
        cdEntry('readme.txt', 0x00000009),
      ]));
      final entries = await ZipCentralDirectory.read(uri, server.fetch);
      expect(entries?.map((e) => e.name),
          ['Super Pixel World (Europe).sfc', 'readme.txt']);
      expect(entries?.where((e) => e.crcMatchesRom).single.crc, 'A31BEAD4');
    });
  });
}
