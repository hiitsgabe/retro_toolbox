import 'dart:io';
import 'dart:typed_data';

/// Total unpacked size of a RAR archive, read from its headers, or null when
/// it can't be told (not a RAR, encrypted headers, unknown sizes, truncated).
///
/// The `rar` plugin reports no progress, so extraction progress is measured
/// as bytes written against this total. Only headers are read: payloads are
/// skipped by seeking, so a multi-GB archive costs a few reads.
int? rarUnpackedSize(String path) {
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    final sig = f.readSync(8);
    if (sig.length >= 8 && _startsWith(sig, _rar5Sig)) return _rar5(f, 8);
    if (sig.length >= 7 && _startsWith(sig, _rar4Sig)) return _rar4(f, 7);
    return null;
  } catch (_) {
    return null;
  } finally {
    f?.closeSync();
  }
}

const _rar5Sig = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00];
const _rar4Sig = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00];

bool _startsWith(List<int> data, List<int> prefix) {
  for (var i = 0; i < prefix.length; i++) {
    if (data[i] != prefix[i]) return false;
  }
  return true;
}

/// RAR5: each block is CRC32, a vint header size, then that many header bytes
/// (type, flags, optional extra/data sizes, type fields), then the data area.
int? _rar5(RandomAccessFile f, int pos) {
  final length = f.lengthSync();
  var total = 0;
  while (pos + 5 < length) {
    f.setPositionSync(pos + 4); // skip CRC32
    final r = _VintReader(f.readSync(3 + 10 + 10 * 6));
    final headerSize = r.next();
    final headerStart = pos + 4 + r.offset;
    final type = r.next();
    final flags = r.next();
    if (flags & 0x0001 != 0) r.next(); // extra area size
    final dataSize = flags & 0x0002 != 0 ? r.next() : 0;
    if (type == 2) {
      final fileFlags = r.next();
      final unpacked = r.next();
      if (fileFlags & 0x0008 != 0) return null; // size unknown
      if (fileFlags & 0x0001 == 0) total += unpacked; // not a directory
    } else if (type == 4) {
      return null; // encrypted headers: nothing more is readable
    } else if (type == 5) {
      break; // end of archive
    }
    pos = headerStart + headerSize + dataSize;
  }
  return total;
}

/// RAR4: 7-byte block base (CRC16, type, flags, size), then for file blocks
/// packed/unpacked sizes, with high 32 bits when flag 0x100 is set.
int? _rar4(RandomAccessFile f, int pos) {
  final length = f.lengthSync();
  var total = 0;
  while (pos + 7 <= length) {
    f.setPositionSync(pos);
    final h = ByteData.sublistView(Uint8List.fromList(f.readSync(7 + 25 + 8)));
    if (h.lengthInBytes < 7) break;
    final type = h.getUint8(2);
    final flags = h.getUint16(3, Endian.little);
    final headSize = h.getUint16(5, Endian.little);
    if (headSize < 7) return null;
    var addSize = 0;
    if (type == 0x74) {
      if (h.lengthInBytes < 32) return null;
      final highFlag = flags & 0x100 != 0 && h.lengthInBytes >= 40;
      final packed = h.getUint32(7, Endian.little) + (highFlag ? h.getUint32(32, Endian.little) << 32 : 0);
      final unpacked = h.getUint32(11, Endian.little) + (highFlag ? h.getUint32(36, Endian.little) << 32 : 0);
      if (flags & 0xE0 != 0xE0) total += unpacked; // 0xE0 = directory
      addSize = packed;
    } else if (type == 0x7b) {
      break; // end of archive
    } else if (flags & 0x8000 != 0 && h.lengthInBytes >= 11) {
      addSize = h.getUint32(7, Endian.little);
    }
    pos += headSize + addSize;
  }
  return total;
}

class _VintReader {
  final List<int> bytes;
  int offset = 0;
  _VintReader(this.bytes);

  int next() {
    var value = 0, shift = 0;
    while (true) {
      final b = bytes[offset++];
      value |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return value;
      shift += 7;
    }
  }
}
