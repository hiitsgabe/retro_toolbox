import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// Where one zip entry's data sits in the file and how it is compressed.
class ZipEntryInfo {
  const ZipEntryInfo({required this.dataOffset, required this.compressedSize, required this.uncompressedSize, required this.method});
  final int dataOffset, compressedSize, uncompressedSize, method;
}

/// Finds [name] in the zip's central directory and where its data starts.
/// Throws FormatException for a non-zip, a missing entry, zip64 sizes or
/// offsets (0xFFFFFFFF), or a compression method other than stored (0) or
/// deflate (8).
///
/// `package:archive` would read the whole entry into memory; LaunchBox's
/// Metadata.xml is 520 MB, so only the directory is read here and the data
/// is streamed by [zipEntryStream].
Future<ZipEntryInfo> findZipEntry(String zipPath, String name) async {
  final f = await File(zipPath).open();
  try {
    final length = await f.length();
    final tailSize = min(length, 66000);
    await f.setPosition(length - tailSize);
    final tail = _le(await f.read(tailSize));

    // End of central directory: 22 bytes plus a comment of up to 64 KB.
    var eocd = -1;
    for (var i = tailSize - 22; i >= 0; i--) {
      if (tail.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw FormatException('Not a zip file', zipPath);
    final count = tail.getUint16(eocd + 10, Endian.little);
    final dirSize = tail.getUint32(eocd + 12, Endian.little);
    final dirOffset = tail.getUint32(eocd + 16, Endian.little);
    if (dirSize == 0xFFFFFFFF || dirOffset == 0xFFFFFFFF || dirOffset + dirSize > length) {
      throw FormatException('Unsupported or broken zip directory', zipPath);
    }

    await f.setPosition(dirOffset);
    final dirBytes = await f.read(dirSize);
    final dir = _le(dirBytes);
    var p = 0;
    for (var n = 0; n < count && p + 46 <= dirSize; n++) {
      if (dir.getUint32(p, Endian.little) != 0x02014b50) throw FormatException('Broken zip directory', zipPath);
      final method = dir.getUint16(p + 10, Endian.little);
      final compressed = dir.getUint32(p + 20, Endian.little);
      final uncompressed = dir.getUint32(p + 24, Endian.little);
      final nameLen = dir.getUint16(p + 28, Endian.little);
      final extraLen = dir.getUint16(p + 30, Endian.little);
      final commentLen = dir.getUint16(p + 32, Endian.little);
      final local = dir.getUint32(p + 42, Endian.little);
      if (p + 46 + nameLen > dirSize) throw FormatException('Broken zip directory', zipPath);
      final entryName = utf8.decode(dirBytes.sublist(p + 46, p + 46 + nameLen), allowMalformed: true);
      p += 46 + nameLen + extraLen + commentLen;
      if (entryName != name) continue;

      if (compressed == 0xFFFFFFFF || uncompressed == 0xFFFFFFFF || local == 0xFFFFFFFF) {
        throw FormatException('Zip64 entries are not supported', name);
      }
      if (method != 0 && method != 8) throw FormatException('Unsupported compression method $method', name);
      // The local header's name and extra lengths can differ from the central
      // directory's, so the data offset comes from the local header itself.
      await f.setPosition(local);
      final header = _le(await f.read(30));
      if (header.lengthInBytes < 30 || header.getUint32(0, Endian.little) != 0x04034b50) {
        throw FormatException('Broken local header', name);
      }
      final dataOffset = local + 30 + header.getUint16(26, Endian.little) + header.getUint16(28, Endian.little);
      return ZipEntryInfo(dataOffset: dataOffset, compressedSize: compressed, uncompressedSize: uncompressed, method: method);
    }
    throw FormatException('No such entry in the zip', name);
  } finally {
    await f.close();
  }
}

/// The entry's uncompressed bytes as a stream. [onCompressedRead] gets the
/// running count of compressed bytes read, for progress.
///
/// Ends with a FormatException when the output is not exactly
/// [ZipEntryInfo.uncompressedSize] bytes: a cut deflate stream just stops
/// early, and a short file would otherwise pass as a smaller one.
Stream<List<int>> zipEntryStream(String zipPath, ZipEntryInfo entry, {void Function(int read)? onCompressedRead}) async* {
  var read = 0;
  final raw = File(zipPath).openRead(entry.dataOffset, entry.dataOffset + entry.compressedSize).map((chunk) {
    read += chunk.length;
    onCompressedRead?.call(read);
    return chunk;
  });
  var written = 0;
  await for (final chunk in entry.method == 8 ? raw.transform(ZLibDecoder(raw: true)) : raw) {
    written += chunk.length;
    yield chunk;
  }
  if (written != entry.uncompressedSize) {
    throw FormatException('Zip entry gave $written bytes, expected ${entry.uncompressedSize}', zipPath);
  }
}

ByteData _le(Uint8List bytes) => ByteData.sublistView(bytes);
