import 'dart:typed_data';

/// Encodes/decodes JKSV's `.nx_save_meta.bin` — the packed `fs::SaveMetaData`
/// struct required inside every JKSV backup for restore. Only `magic` and
/// `applicationId` (title ID) are meaningful for a save produced outside a
/// Switch; the rest are best-effort defaults (see the spec's meta-file risk).
class JksvMeta {
  static const int magic = 0x56534B4A; // "JKSV" little-endian
  static const String fileName = '.nx_save_meta.bin';

  // Packed struct, no padding, little-endian. Field sizes sum to 86 bytes.
  static const int size = 86;

  final bool magicOk;
  final int applicationId;
  final int timestamp;

  const JksvMeta({required this.magicOk, required this.applicationId, required this.timestamp});

  static Uint8List encode({required int applicationId, int revision = 0, int timestamp = 0}) {
    final b = ByteData(size);
    var o = 0;
    b.setUint32(o, magic, Endian.little); o += 4;
    b.setUint8(o, revision); o += 1;
    b.setUint64(o, applicationId, Endian.little); o += 8;
    // accountID (128-bit) — 16 zero bytes
    o += 16;
    b.setUint64(o, 0, Endian.little); o += 8; // systemSaveID
    b.setUint8(o, 0); o += 1; // saveDataType
    b.setUint8(o, 0); o += 1; // saveDataRank
    b.setUint16(o, 0, Endian.little); o += 2; // saveDataIndex
    b.setUint64(o, 0, Endian.little); o += 8; // ownerID
    b.setUint64(o, timestamp, Endian.little); o += 8;
    b.setUint32(o, 0, Endian.little); o += 4; // flags
    b.setInt64(o, 0, Endian.little); o += 8; // saveDataSize
    b.setInt64(o, 0, Endian.little); o += 8; // journalSize
    b.setUint64(o, 0, Endian.little); o += 8; // commitID
    b.setUint8(o, 0); o += 1; // saveDataSpaceID
    assert(o == size);
    return b.buffer.asUint8List();
  }

  static JksvMeta decode(Uint8List bytes) {
    if (bytes.length < size) {
      return const JksvMeta(magicOk: false, applicationId: 0, timestamp: 0);
    }
    final b = ByteData.sublistView(bytes);
    final m = b.getUint32(0, Endian.little);
    final appId = b.getUint64(5, Endian.little);
    final ts = b.getUint64(5 + 8 + 16 + 8 + 1 + 1 + 2 + 8, Endian.little); // timestamp offset
    return JksvMeta(magicOk: m == magic, applicationId: appId, timestamp: ts);
  }
}
