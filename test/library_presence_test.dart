import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('presence');
    File('${dir.path}/Alpha Title.nsp').writeAsStringSync('x'); // a decompressed .nsz
    File('${dir.path}/Beta (USA).gbc').writeAsStringSync('x'); // an unzipped .zip
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // Settings may store the folder with or without a trailing slash.
  for (final slash in ['', '/']) {
    test('the unpacked file counts as downloaded (folder "...$slash")', () async {
      final snap = LibrarySnapshotNotifier('${dir.path}$slash');
      expect(await snap.getStatus('Alpha Title.nsz'), LibraryPresence.extracted);
      expect(await snap.getStatus('Beta (USA).zip'), LibraryPresence.extracted);
      expect(await snap.getStatus('Gamma.zip'), LibraryPresence.none);
    });
  }
}
