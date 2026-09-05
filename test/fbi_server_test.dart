import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/fbi_server_service.dart';

void main() {
  test('buildPushPayload = 4-byte big-endian length + newline-joined URLs', () {
    final payload = FbiServerService.buildPushPayload(['http://a/1.cia', 'http://a/2.cia']);
    const body = 'http://a/1.cia\nhttp://a/2.cia';
    // Header: big-endian u32 of the body length.
    final len = ByteData.sublistView(Uint8List.fromList(payload.sublist(0, 4))).getUint32(0, Endian.big);
    expect(len, body.length);
    expect(String.fromCharCodes(payload.sublist(4)), body);
  });

  test('single URL payload', () {
    final payload = FbiServerService.buildPushPayload(['http://x/g.cia']);
    expect(ByteData.sublistView(Uint8List.fromList(payload.sublist(0, 4))).getUint32(0, Endian.big), 'http://x/g.cia'.length);
  });
}
