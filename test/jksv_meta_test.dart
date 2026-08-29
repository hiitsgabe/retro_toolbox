import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/jksv_meta.dart';

void main() {
  test('encode produces the 86-byte packed struct with JKSV magic', () {
    final bytes = JksvMeta.encode(applicationId: 0x010043600B6A6000, timestamp: 0x1122334455667788);
    expect(bytes.length, JksvMeta.size);
    // magic 0x56534B4A little-endian => 4A 4B 53 56 ("JKSV")
    expect(bytes.sublist(0, 4), [0x4A, 0x4B, 0x53, 0x56]);
  });

  test('round-trips applicationId and timestamp', () {
    final bytes = JksvMeta.encode(applicationId: 0x0100152000022000, timestamp: 42);
    final meta = JksvMeta.decode(bytes);
    expect(meta.magicOk, isTrue);
    expect(meta.applicationId, 0x0100152000022000);
    expect(meta.timestamp, 42);
  });

  test('decode rejects wrong magic', () {
    final bytes = JksvMeta.encode(applicationId: 1);
    bytes[0] = 0x00;
    expect(JksvMeta.decode(bytes).magicOk, isFalse);
  });
}
