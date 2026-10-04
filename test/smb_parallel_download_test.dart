import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/smb_service.dart';

/// Needs a real SMB server; skipped unless SMB_TEST_HOST is set, e.g.
///   docker run -d --name rt-smb dperson/samba -u "tester;secret" -s "share;/share;yes;no;no;tester"
///   docker exec rt-smb sh -c 'mkdir -p /share/t && head -c 9000000 /dev/urandom > /share/t/big.bin &&
///     for i in 1 2 3; do head -c 100000 /dev/urandom > /share/t/s$i.bin; done && chown -R tester /share'
///   SMB_TEST_HOST=<container ip> flutter test test/smb_parallel_download_test.dart
void main() {
  final host = Platform.environment['SMB_TEST_HOST'];

  test('parallel download matches the sequential one byte for byte, big files in slices', () async {
    final s = SmbService();
    await s.connect(host: host!, username: 'tester', password: 'secret');
    final out = Directory.systemTemp.createTempSync('smbpar');
    final remote = (await s.list('/share/t')).where((f) => !f.isDirectory()).toList();

    int? last;
    // 1 MB chunks so the 9 MB file is split across the connections.
    await s.downloadParallel(
      [for (final f in remote) (file: f, localPath: p.join(out.path, 'par', f.name))],
      (d, t) => last = d,
      connections: 3,
      chunkSize: 1 << 20,
    );
    expect(last, remote.fold<int>(0, (a, f) => a + f.size));

    await Directory(p.join(out.path, 'seq')).create();
    for (final f in remote) {
      await s.download(f, p.join(out.path, 'seq', f.name), (_, __) {});
      String hash(String dir) => sha1.convert(File(p.join(out.path, dir, f.name)).readAsBytesSync()).toString();
      expect(hash('par'), hash('seq'), reason: f.name);
    }
    await s.disconnect();
  }, skip: host == null ? 'set SMB_TEST_HOST to run against a real server' : false);
}
