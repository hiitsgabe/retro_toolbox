import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/drive_transport.dart';

import 'save_sync_fake_drive.dart';

void main() {
  late FakeDrive drive;
  late FakeTokens tokens;
  late List<Duration> slept;

  DriveApi api({int multipartLimit = 5000000}) =>
      DriveApi(drive, tokens, sleep: (d) async => slept.add(d), random: Random(7), multipartLimit: multipartLimit);

  setUp(() {
    drive = FakeDrive();
    tokens = FakeTokens(['token-1']);
    slept = [];
  });

  test('children reads every page and leaves out the trash', () async {
    drive = FakeDrive(pageSize: 2);
    final hub = drive.add('Retro Toolbox Saves');
    for (var i = 0; i < 5; i++) {
      drive.add('g$i.json', parent: hub.id, bytes: [i]);
    }
    drive.add('gone.json', parent: hub.id, bytes: [9]).trashed = true;
    final names = (await api().children(hub.id)).map((f) => f.name).toList()..sort();
    expect(names, ['g0.json', 'g1.json', 'g2.json', 'g3.json', 'g4.json']);
    expect(drive.log.where((l) => l == 'GET /drive/v3/files'), hasLength(3));
  });

  test('createFolder and createFile put things where asked, bytes intact, with the checksum Drive reports', () async {
    final a = api();
    final folder = await a.createFolder('units', 'root');
    final bytes = [0, 1, 2, 255, 13, 10, 45, 45];
    final f = await a.createFile('20261110T224107Z-thor-7f3a-9f2c01e1.zip', folder.id, bytes);
    expect(folder.isFolder, isTrue);
    expect(drive.at('units/20261110T224107Z-thor-7f3a-9f2c01e1.zip')!.bytes, bytes);
    expect(drive.files[f.id]!.mimeType, 'application/zip');
    expect(f.sha256, sha256.convert(bytes).toString());
    expect(f.size, 8);
    expect(drive.log, ['POST /drive/v3/files', 'POST /upload/drive/v3/files']);
  });

  test('a body over the multipart limit goes up through a resumable session', () async {
    final bytes = List.generate(20, (i) => i);
    final f = await api(multipartLimit: 8).createFile('big.zip', 'root', bytes);
    expect(drive.files[f.id]!.bytes, bytes);
    expect(drive.log, ['POST /upload/drive/v3/files', 'PUT /upload/drive/v3/files']);
  });

  test('a resumable PUT that fails starts a new session after a pause', () async {
    drive.fail(500, match: (r) => r.method == 'PUT');
    final f = await api(multipartLimit: 8).createFile('big.zip', 'root', List.filled(20, 7));
    expect(drive.files[f.id]!.bytes, List.filled(20, 7));
    expect(drive.log, ['POST /upload/drive/v3/files', 'PUT /upload/drive/v3/files', 'POST /upload/drive/v3/files', 'PUT /upload/drive/v3/files']);
    expect(slept, hasLength(1));
    expect(drive.files.values.where((x) => x.name == 'big.zip'), hasLength(1));
  });

  test('a resumable PUT whose connection drops starts a new session after a pause', () async {
    drive.drop(match: (r) => r.method == 'PUT');
    final f = await api(multipartLimit: 8).createFile('big.zip', 'root', List.filled(20, 7));
    expect(drive.files[f.id]!.bytes, List.filled(20, 7));
    expect(drive.log, ['POST /upload/drive/v3/files', 'PUT /upload/drive/v3/files', 'POST /upload/drive/v3/files', 'PUT /upload/drive/v3/files']);
    expect(slept, hasLength(1));
    expect(drive.files.values.where((x) => x.name == 'big.zip'), hasLength(1));
  });

  test('updateFile replaces the content and keeps the file id', () async {
    final f = drive.add('README.txt', bytes: utf8.encode('old text'));
    final g = await api().updateFile(f.id, 'README.txt', utf8.encode('new'));
    expect(g.id, f.id);
    expect(utf8.decode(drive.files[f.id]!.bytes), 'new');
    expect(drive.files.values.where((x) => x.name == 'README.txt'), hasLength(1));
  });

  test('download returns the bytes; trash hides the file, and trashing it again is fine', () async {
    final f = drive.add('hub.json', bytes: utf8.encode('{"format":1}'));
    final a = api();
    expect(utf8.decode(await a.download(f.id)), '{"format":1}');
    await a.trash(f.id);
    expect(drive.files[f.id]!.trashed, isTrue);
    expect(await a.children('root'), isEmpty);
    await a.trash(f.id);
  });

  test('a stored copy whose checksum differs is trashed and the upload fails', () async {
    drive.corruptUploads = true;
    await expectLater(api().createFile('a.json', 'root', utf8.encode('{"a":1}')), throwsA(isA<DriveChecksumMismatch>()));
    expect(drive.named('root', 'a.json'), isEmpty);
    expect(drive.files.values.single.trashed, isTrue);
  });

  test('a response without sha256Checksum is checked with one more metadata read', () async {
    drive.omitSha256 = true;
    final f = await api().createFile('a.json', 'root', utf8.encode('{}'));
    expect(drive.log, ['POST /upload/drive/v3/files', 'GET /drive/v3/files/${f.id}']);
  });

  test('a 401 gets one new token and one more try', () async {
    tokens = FakeTokens(['expired', 'token-1']);
    expect(await api().children('root'), isEmpty);
    expect(tokens.invalidated, ['expired']);
    expect(slept, isEmpty);
  });

  test('a second 401 means signing in again', () async {
    tokens = FakeTokens(['expired', 'revoked']);
    await expectLater(api().children('root'), throwsA(isA<DriveSignInNeeded>()));
    expect(tokens.invalidated, ['expired']);
    expect(drive.log, hasLength(2));
  });

  test('429, 5xx and rate-limit 403s back off about 1, 2 and 4 seconds and stop after four tries', () async {
    drive.fail(503, times: 1);
    drive.fail(429, reason: 'rateLimitExceeded', times: 1);
    drive.fail(403, reason: 'userRateLimitExceeded', times: 1);
    expect(await api().children('root'), isEmpty);
    expect(slept, hasLength(3));
    for (final (i, d) in slept.indexed) {
      expect(d.inMilliseconds, inInclusiveRange(1000 << i, (1000 << i) + 1000));
    }

    slept.clear();
    drive.fail(500, raw: '<html>Server Error</html>', times: 4);
    await expectLater(api().children('root'), throwsA(isA<DriveError>().having((e) => e.status, 'status', 500)));
    expect(slept, hasLength(3));
  });

  test('a dropped connection backs off and tries again, and stops after four tries', () async {
    drive.drop(times: 2);
    expect(await api().children('root'), isEmpty);
    expect(slept, hasLength(2));

    slept.clear();
    drive.drop(times: 4);
    await expectLater(api().children('root'), throwsA(isA<DriveNetworkError>()));
    expect(slept, hasLength(3));
  });

  test('a create whose answer was lost is sent again and can leave a second copy with the same bytes', () async {
    drive.drop(landed: true, match: (r) => r.method == 'POST');
    final f = await api().createFile('a.json', 'root', utf8.encode('{"a":1}'));
    final copies = drive.named('root', 'a.json');
    expect(copies, hasLength(2));
    expect(copies.map((c) => utf8.decode(c.bytes)), ['{"a":1}', '{"a":1}']);
    expect(f.id, copies.last.id);
    expect(slept, hasLength(1));
  });

  test('errors that waiting cannot fix are not retried', () async {
    drive.fail(403, reason: 'dailyLimitExceeded');
    await expectLater(api().children('root'), throwsA(isA<DriveError>().having((e) => e.reason, 'reason', 'dailyLimitExceeded')));
    drive.fail(400, raw: 'not json');
    await expectLater(api().children('root'), throwsA(isA<DriveError>().having((e) => e.toString(), 'text', 'Google Drive error 400: HTTP 400')));
    expect(slept, isEmpty);
  });

  test('403 storageQuotaExceeded is "Drive is full" at once', () async {
    drive.fail(403, reason: 'storageQuotaExceeded');
    await expectLater(
      api().createFile('a.zip', 'root', [1, 2, 3]),
      throwsA(isA<DriveFull>().having((e) => e.toString(), 'text', startsWith('Drive is full'))),
    );
    expect(slept, isEmpty);
    expect(drive.files, isEmpty);

    // A resumable upload starts over after a failed PUT, but not when the Drive is full.
    drive.fail(403, reason: 'storageQuotaExceeded', match: (r) => r.method == 'PUT');
    await expectLater(api(multipartLimit: 8).createFile('big.zip', 'root', List.filled(20, 1)), throwsA(isA<DriveFull>()));
    expect(slept, isEmpty);
    expect(drive.log.where((l) => l.startsWith('PUT')), hasLength(1));
  });
}
