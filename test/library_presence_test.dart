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

  test('a file whose real name sanitizeForFat changes is on disk under the name it gives, at its real path', () async {
    File('${dir.path}/Metroid Prime 4: Beyond.chd').writeAsStringSync('x');
    final snap = await LibrarySnapshotNotifier(dir.path).current();
    expect(snap.statusFor('Metroid Prime 4 Beyond.chd'), LibraryPresence.file);
    expect(snap.presentBaseNames(), contains('Metroid Prime 4 Beyond'));
    expect(snap.pathFor('Metroid Prime 4 Beyond.chd'), '${dir.path}/Metroid Prime 4: Beyond.chd');
    expect(snap.pathFor('Beta (USA).gbc'), '${dir.path}/Beta (USA).gbc');
  });

  test('a real file of the name sanitizeForFat gives wins over the file renamed to it', () async {
    File('${dir.path}/Metroid Prime 4: Beyond.chd').writeAsStringSync('x');
    File('${dir.path}/Metroid Prime 4 Beyond.chd').writeAsStringSync('x');
    final snap = await LibrarySnapshotNotifier(dir.path).current();
    expect(snap.pathFor('Metroid Prime 4 Beyond.chd'), '${dir.path}/Metroid Prime 4 Beyond.chd');
  });
}
