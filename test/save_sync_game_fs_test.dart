import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';

class FakeShell implements PrivilegedShell {
  FakeShell(this.reply);

  final ShellResult Function(List<String> argv) reply;
  final calls = <List<String>>[];

  @override
  Privilege get privilege => Privilege.shell;

  @override
  Future<ShellResult> run(List<String> argv) async {
    calls.add(argv);
    return reply(argv);
  }
}

class _Flaky implements PrivilegedShell {
  _Flaky(this.inner, this.failNextChmod);

  final PrivilegedShell inner;
  final bool Function() failNextChmod;

  @override
  Privilege get privilege => inner.privilege;

  @override
  Future<ShellResult> run(List<String> argv) async {
    if (argv.first == 'chmod' && failNextChmod()) return const ShellResult(ShellResult.unreachable, '', 'no reply from Shizuku');
    return inner.run(argv);
  }
}

void main() {
  late Directory tmp;
  late String game;
  late String sync;
  late ShellGameFs fs;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gamefs');
    game = p.join(tmp.path, 'Android/data/com.example.game/files/Saves');
    sync = p.join(tmp.path, 'RetroToolbox/SaveSync');
    Directory(p.join(game, 'Farm_1')).createSync(recursive: true);
    Directory(sync).createSync(recursive: true);
    File(p.join(game, 'Farm_1/Farm_1')).writeAsStringSync('<SaveGame/>');
    File(p.join(game, 'Farm_1/SaveGameInfo')).writeAsStringSync('<Farmer/>');
    File(p.join(game, 'it' "'" 's a file')).writeAsStringSync('q');
    fs = ShellGameFs(ProcessShell(), PathGuard([p.join(tmp.path, 'Android/data/com.example.game'), sync]));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('listFiles walks the tree with sizes and mtimes', () async {
    final files = await fs.listFiles(game);
    expect(files.map((f) => p.relative(f.path, from: game)), unorderedEquals(['Farm_1/Farm_1', 'Farm_1/SaveGameInfo', "it's a file"]));
    expect(files.firstWhere((f) => f.path.endsWith('Farm_1/Farm_1')).size, 11);
    expect(files.first.mtime, greaterThan(0));
    expect(await fs.listFiles(p.join(game, 'missing')), isEmpty);
  });

  test('sha256 of several files', () async {
    final a = p.join(game, 'Farm_1/Farm_1'), b = p.join(game, "it's a file");
    final h = await fs.sha256([a, b]);
    expect(h[a], sha256.convert(File(a).readAsBytesSync()).toString());
    expect(h[b], sha256.convert(File(b).readAsBytesSync()).toString());
    expect(await fs.sha256([]), isEmpty);
  });

  test('copyOut, moveTo, exists, isDir, remove', () async {
    final out = p.join(sync, 'staging/Farm_1');
    Directory(p.dirname(out)).createSync(recursive: true);
    await fs.copyOut(p.join(game, 'Farm_1/Farm_1'), out);
    expect(File(out).readAsStringSync(), '<SaveGame/>');
    await fs.moveTo(p.join(game, 'Farm_1/SaveGameInfo'), p.join(sync, 'SaveGameInfo'));
    expect(await fs.exists(p.join(game, 'Farm_1/SaveGameInfo')), isFalse);
    expect(await fs.isDir(p.join(game, 'Farm_1')), isTrue);
    await fs.remove(p.join(sync, 'SaveGameInfo'));
    expect(File(p.join(sync, 'SaveGameInfo')).existsSync(), isFalse);
  });

  test('replace goes through a dot temp, verifies the hash and leaves no temp behind', () async {
    final staged = p.join(sync, 'new');
    File(staged).writeAsStringSync('<SaveGame>new</SaveGame>');
    final sha = sha256.convert(File(staged).readAsBytesSync()).toString();
    final target = p.join(game, 'Farm_1/Farm_1');
    await fs.replace(staged, target, sha);
    expect(File(target).readAsStringSync(), '<SaveGame>new</SaveGame>');
    expect(Directory(p.join(game, 'Farm_1')).listSync().map((e) => p.basename(e.path)).where((n) => n.startsWith('.')), isEmpty);
    expect(File(target).statSync().mode & 0x1FF, 0x1B6); // 0666
  });

  test('replace with the wrong hash leaves the target alone', () async {
    final staged = p.join(sync, 'new');
    File(staged).writeAsStringSync('other');
    final target = p.join(game, 'Farm_1/Farm_1');
    await expectLater(fs.replace(staged, target, 'deadbeef'), throwsA(isA<GameFsError>()));
    expect(File(target).readAsStringSync(), '<SaveGame/>');
    expect(Directory(p.join(game, 'Farm_1')).listSync().where((e) => p.basename(e.path).startsWith('.')), isEmpty);
  });

  test('makeGameDir creates a folder anyone can write', () async {
    final dir = p.join(game, 'Farm_2');
    await fs.makeGameDir(dir);
    expect(Directory(dir).statSync().mode & 0x1FF, 0x1FF); // 0777
  });

  test('makeGameDir leaves no folder under the final name when chmod fails once', () async {
    final dir = p.join(game, 'Farm_2');
    var failed = false;
    final real = ProcessShell();
    final shell = _Flaky(real, () {
      if (failed) return false;
      failed = true;
      return true;
    });
    final f = ShellGameFs(shell, PathGuard([p.join(tmp.path, 'Android/data/com.example.game')]));
    await expectLater(f.makeGameDir(dir), throwsA(isA<GameFsError>()));
    expect(Directory(dir).existsSync(), isFalse);
    expect(Directory(game).listSync().where((e) => p.basename(e.path).startsWith('.rtsync-')), isEmpty);
    await f.makeGameDir(dir);
    expect(Directory(dir).statSync().mode & 0x1FF, 0x1FF);
  });

  test('paths outside the guard never reach the shell', () async {
    expect(() => fs.listFiles('/etc'), throwsA(isA<PathRefused>()));
    expect(() => fs.copyOut(p.join(game, 'Farm_1/Farm_1'), '/tmp/x'), throwsA(isA<PathRefused>()));
  });

  test('running, versionName, installed', () async {
    final shell = FakeShell((argv) => switch (argv.first) {
          'pidof' => argv[1] == 'com.example.game' ? const ShellResult(0, '1234\n', '') : const ShellResult(1, '', ''),
          'dumpsys' => const ShellResult(0, '  Packages:\n    versionCode=24334 minSdk=21\n    versionName=1.6.15.2\n', ''),
          'pm' => argv[2] == 'com.example.game' ? const ShellResult(0, 'package:/data/app/x/base.apk\n', '') : const ShellResult(1, '', ''),
          'mkdir' || 'chmod' || 'mv' => const ShellResult(0, '', ''),
          _ => const ShellResult(1, '', 'unexpected'),
        });
    final f = ShellGameFs(shell, PathGuard(['/x']));
    expect(await f.running('com.example.game'), isTrue);
    expect(await f.running('com.other'), isFalse);
    expect(await f.versionName('com.example.game'), '1.6.15.2');
    expect(await f.installed('com.example.game'), isTrue);
    expect(await f.installed('com.other'), isFalse);
    expect(shell.calls.first, ['pidof', 'com.example.game']);
    expect(() => f.running('bad name; rm -rf /'), throwsA(isA<ArgumentError>()));
    await f.makeGameDir('/x/Farm_2');
    // GNU chmod keeps a dir's setgid on `chmod 777`, toybox clears it: pin the argv.
    final chmod = shell.calls.lastWhere((c) => c.first == 'chmod');
    expect(chmod.sublist(0, 2), ['chmod', 'a+rwx']);
    expect(chmod[2], startsWith('/x/.rtsync-'));
    expect(shell.calls.last, ['mv', chmod[2], '/x/Farm_2']);
    // A probe that failed is an error, never a plain "no": exit 1 with a
    // message here, and a bridge that never answered below.
    await expectLater(f.exists('/x/a'), throwsA(isA<GameFsError>()));
    final down = ShellGameFs(FakeShell((argv) => const ShellResult(ShellResult.unreachable, '', 'exec failed')), PathGuard(['/x']));
    await expectLater(down.running('com.example.game'), throwsA(isA<GameFsError>()));
    await expectLater(down.exists('/x/a'), throwsA(isA<GameFsError>()));
    await expectLater(down.isDir('/x/a'), throwsA(isA<GameFsError>()));
  });

  test('versionName takes the whole line, and "null" is no version', () async {
    var reply = '    versionName=1.0.3 (release)\n    splits=[base]\n';
    final f = ShellGameFs(FakeShell((argv) => ShellResult(0, reply, '')), PathGuard(['/x']));
    expect(await f.versionName('com.example.game'), '1.0.3 (release)');
    reply = '    versionName=null\n';
    expect(await f.versionName('com.example.game'), isNull);
  });

  test('listFiles: a missing folder is empty, one the shell cannot reach is an error', () async {
    var statErr = "stat: '/x/Saves': No such file or directory";
    final f = ShellGameFs(
      FakeShell((argv) => switch (argv.first) {
            'stat' => ShellResult(1, '', statErr),
            _ => const ShellResult(1, '', ''),
          }),
      PathGuard(['/x']),
    );
    expect(await f.listFiles('/x/Saves'), isEmpty);
    statErr = "stat: '/x/Saves': Permission denied";
    await expectLater(f.listFiles('/x/Saves'), throwsA(isA<GameFsError>()));
  });
}
