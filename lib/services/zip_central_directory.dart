import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:roms_downloader/utils/file_crc32.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// A `Range` response, reduced to what the parser needs.
class RangeResponse {
  final int statusCode;
  final String? contentRange;
  final Uint8List bytes;

  const RangeResponse({
    required this.statusCode,
    required this.bytes,
    this.contentRange,
  });
}

/// Fetches a byte range. [range] arrives in header form: `bytes=-256` or
/// `bytes=100-199`.
typedef RangeFetch = Future<RangeResponse> Function(Uri uri, String range);

/// A central directory entry. [crc] uppercase, eight digits, same format as
/// `PackDump.crc`.
class ZipEntry {
  final String name;
  final String crc;

  const ZipEntry({required this.name, required this.crc});

  /// True when this CRC can be compared against a pack dump's. A zip inside a
  /// zip has its own CRC (the compressed file's, not the ROM's), which could
  /// match by accident.
  bool get crcMatchesRom => hasRomExtension(name) && !hasArchiveExtension(name);

  @override
  String toString() => 'ZipEntry($name, $crc)';
}

/// Reads the central directory of a remote ZIP in two short requests.
///
/// Pure Dart on purpose: `tool/probe_zip_cd.dart` runs this outside Flutter.
/// Do not add a `package:flutter` import.
class ZipCentralDirectory {
  /// How many trailing bytes to fetch to find the EOCD. 256 covers the 22-byte
  /// EOCD plus a short comment.
  static const tailBytes = 256;

  /// Cap on what we buffer, so a hostile server cannot fill the app's memory.
  static const maxDirectoryBytes = 8 * 1024 * 1024;

  /// The raw central directory bytes, or null when it did not work. Never
  /// throws: null just leaves the caller with the name guess.
  static Future<Uint8List?> readRaw(Uri uri, RangeFetch fetch) async {
    final RangeResponse tail;
    try {
      tail = await fetch(uri, 'bytes=-$tailBytes');
    } catch (_) {
      return null;
    }
    final total = _totalFrom(tail);
    if (total == null) return null;

    final eocd = _findEocd(tail.bytes);
    if (eocd == null) return null;

    final view = ByteData.sublistView(tail.bytes);
    final size = view.getUint32(eocd + 12, Endian.little);
    final offset = view.getUint32(eocd + 16, Endian.little);

    // 0xFFFFFFFF in both fields is the zip64 marker. No ROM source serves
    // zip64, so this is dead code if implemented.
    if (size == 0xFFFFFFFF || offset == 0xFFFFFFFF) return null;
    if (size == 0 || size > maxDirectoryBytes) return null;
    if (offset + size > total) return null;

    final RangeResponse body;
    try {
      body = await fetch(uri, 'bytes=$offset-${offset + size - 1}');
    } catch (_) {
      return null;
    }
    if (_totalFrom(body) == null) return null;
    if (body.bytes.length != size) return null;
    return body.bytes;
  }

  /// The entries of a remote ZIP, or null when it could not be read.
  static Future<List<ZipEntry>?> read(Uri uri, RangeFetch fetch) async {
    final raw = await readRaw(uri, fetch);
    if (raw == null) return null;
    return parse(raw);
  }

  /// Breaks the central directory bytes into entries. Stops at the first record
  /// not starting with `PK\x01\x02` and returns what it read.
  static List<ZipEntry>? parse(Uint8List directory) {
    final view = ByteData.sublistView(directory);
    final entries = <ZipEntry>[];
    var pos = 0;
    while (pos + 46 <= directory.length) {
      if (view.getUint32(pos, Endian.little) != 0x02014b50) break;
      final crc = view.getUint32(pos + 16, Endian.little);
      final nameLen = view.getUint16(pos + 28, Endian.little);
      final extraLen = view.getUint16(pos + 30, Endian.little);
      final commentLen = view.getUint16(pos + 32, Endian.little);
      final nameEnd = pos + 46 + nameLen;
      if (nameEnd > directory.length) break;
      entries.add(ZipEntry(
        // The name may be CP437 or UTF-8, distinguished only by a flag bit
        // few writers set right. `allowMalformed` turns bad bytes into U+FFFD
        // instead of throwing.
        name: utf8.decode(directory.sublist(pos + 46, nameEnd),
            allowMalformed: true),
        crc: formatCrc(crc),
      ));
      pos = nameEnd + extraLen + commentLen;
    }
    return entries.isEmpty ? null : entries;
  }

  /// The total file size from `Content-Range`, or null if the response is not a
  /// real partial response. A `200` means the server ignored the `Range`.
  static int? _totalFrom(RangeResponse response) {
    if (response.statusCode != HttpStatus.partialContent) return null;
    final header = response.contentRange;
    if (header == null) return null;
    final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(header.trim());
    if (m == null) return null;
    return int.parse(m.group(3)!);
  }

  /// Scans backward for `PK\x05\x06`: the EOCD is the last record, but the
  /// comment can come after it.
  static int? _findEocd(Uint8List bytes) {
    if (bytes.length < 22) return null;
    for (var i = bytes.length - 22; i >= 0; i--) {
      if (bytes[i] == 0x50 &&
          bytes[i + 1] == 0x4b &&
          bytes[i + 2] == 0x05 &&
          bytes[i + 3] == 0x06) {
        return i;
      }
    }
    return null;
  }

  /// The production fetch.
  ///
  /// Check the status before consuming the body: reading first would download
  /// the whole file, which is what the Range read exists to avoid.
  static Future<RangeResponse> httpRangeFetch(Uri uri, String range) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.rangeHeader, range);
      final response = await request.close();
      if (response.statusCode != HttpStatus.partialContent) {
        await response.drain<void>();
        return RangeResponse(
          statusCode: response.statusCode,
          bytes: Uint8List(0),
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > maxDirectoryBytes) {
          throw HttpException(
              'partial response over $maxDirectoryBytes bytes',
              uri: uri);
        }
      }
      return RangeResponse(
        statusCode: response.statusCode,
        contentRange: response.headers.value(HttpHeaders.contentRangeHeader),
        bytes: builder.toBytes(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
