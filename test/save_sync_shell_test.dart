import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shellQuote survives quotes and spaces', () {
    expect(shellQuote("it's a farm"), r"'it'\''s a farm'");
    expect(shellQuote(''), "''");
  });

  test('ProcessShell runs argv without a shell', () async {
    final r = await ProcessShell().run(['echo', r'$HOME', 'a b']);
    expect(r.ok, isTrue);
    expect(r.out.trim(), r'$HOME a b');
  });

  test('ProcessShell reports a missing command as a failed result', () async {
    final r = await ProcessShell().run(['definitely-not-a-command-xyz']);
    expect(r.ok, isFalse);
    // A command killed by a signal did run: 128+signal, never the sentinel.
    final k = await ProcessShell().run(['sh', '-c', r'kill -HUP $$']);
    expect(k.ran, isTrue);
    expect(k.code, 129);
  });

  test('ShizukuShell passes argv and maps the reply', () async {
    const channel = MethodChannel('retro_toolbox/shizuku');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'status') return {'running': true, 'granted': true, 'uid': 2000};
      return {'code': 3, 'out': 'hello\n', 'err': 'warn\n'};
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final status = await ShizukuShell.status();
    expect(status.granted, isTrue);
    expect(status.running, isTrue);
    expect(status.uid, 2000);
    final shell = ShizukuShell(uid: status.uid);
    expect(shell.privilege, Privilege.shell);
    final r = await shell.run(['echo', 'hello']);
    expect(r.out, 'hello\n');
    expect(r.code, 3);
    expect(r.ok, isFalse);
    expect(r.err, 'warn\n');
    expect(calls.last.method, 'exec');
    expect(calls.last.arguments, {
      'argv': ['echo', 'hello'],
    });
    expect(ShizukuShell(uid: 0).privilege, Privilege.root);
  });

  test('ShizukuShell marks a bridge failure as not run, not as exit 1', () async {
    const channel = MethodChannel('retro_toolbox/shizuku');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'SHIZUKU', message: 'exec failed');
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final r = await ShizukuShell(uid: 2000).run(['test', '-e', '/x']);
    expect(r.ok, isFalse);
    expect(r.ran, isFalse);
    expect(r.code, ShellResult.unreachable);
    expect(const ShellResult(1, '', '').ran, isTrue);
  });

  test('ShizukuShell.status is "not running" when the channel is missing', () async {
    final status = await ShizukuShell.status();
    expect(status.running, isFalse);
    expect(status.granted, isFalse);
  });
}
