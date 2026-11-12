import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

enum Privilege { none, shell, root }

class ShellResult {
  const ShellResult(this.code, this.out, this.err);

  final int code;
  final String out;
  final String err;

  /// The code for "the command never ran or no answer came back". No exit
  /// code maps to it (ProcessShell turns a death by signal into 128+signal),
  /// so a probe can tell it apart from a plain exit 1.
  static const unreachable = -1;

  bool get ok => code == 0;

  /// False when the transport failed (no reply, bridge error, timeout).
  bool get ran => code >= 0;

  @override
  String toString() => 'exit $code: ${err.trim().isEmpty ? out.trim() : err.trim()}';
}

/// Runs one command as argv. Implementations never pass untrusted text through a shell unquoted.
abstract class PrivilegedShell {
  Privilege get privilege;

  Future<ShellResult> run(List<String> argv);
}

/// Single-quotes [s] for `sh -c`.
String shellQuote(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// A local process. Plain on Linux (tests); with [viaSu] every call goes
/// through `su --mount-master -c` with each argument quoted (root on the
/// direct flavor). Each call is its own su request, so Magisk may show a toast.
class ProcessShell implements PrivilegedShell {
  ProcessShell({this.viaSu = false, this.timeout = const Duration(minutes: 2)});

  final bool viaSu;
  final Duration timeout;

  /// English error messages, which callers match on.
  static const _env = {'LC_ALL': 'C'};

  @override
  Privilege get privilege => viaSu ? Privilege.root : Privilege.none;

  @override
  Future<ShellResult> run(List<String> argv) async {
    try {
      // Process.start, not Process.run().timeout(): a timeout that only stops
      // waiting leaves the command running, and its effect can land after
      // run() has reported failure. On su the client dies without reliably
      // taking the root child along, so the inner command carries its own
      // KILL, a few seconds ahead of ours.
      final inner = max(1, timeout.inSeconds - 5);
      final p = viaSu
          ? await Process.start('su', ['--mount-master', '-c', ['timeout', '-s', 'KILL', '$inner', ...argv].map(shellQuote).join(' ')], environment: _env)
          : await Process.start(argv.first, argv.sublist(1), environment: _env);
      var timedOut = false;
      final timer = Timer(timeout, () {
        timedOut = true;
        p.kill(ProcessSignal.sigkill);
      });
      final out = systemEncoding.decodeStream(p.stdout);
      final err = systemEncoding.decodeStream(p.stderr);
      final exit = await p.exitCode;
      timer.cancel();
      if (timedOut) return ShellResult(ShellResult.unreachable, '', 'timed out: ${argv.first}');
      // Dart reports a death by signal as -signal. A shell, and Shizuku's
      // side, say 128+signal, which keeps negative codes for [unreachable].
      final code = exit < 0 ? 128 - exit : exit;
      return ShellResult(code, await out, await err);
    } on ProcessException catch (e) {
      return ShellResult(127, '', e.message);
    }
  }

  /// Whether `su` gives root in the global mount namespace here. An `su`
  /// without `--mount-master` fails this, and the app falls back to Shizuku.
  static Future<bool> rootAvailable() async {
    try {
      final r = await Process.run('su', ['--mount-master', '-c', 'id -u']).timeout(const Duration(seconds: 15));
      return r.exitCode == 0 && '${r.stdout}'.trim() == '0';
    } catch (_) {
      return false;
    }
  }
}

class ShizukuStatus {
  const ShizukuStatus({required this.running, required this.granted, required this.uid});

  final bool running;
  final bool granted;

  /// 2000 when Shizuku was started over ADB, 0 when it runs on root, -1 when unknown.
  final int uid;
}

/// Shizuku: argv runs in a UserService inside Shizuku's process (uid 2000, or 0 on root).
class ShizukuShell implements PrivilegedShell {
  ShizukuShell({required this.uid, this.timeout = const Duration(minutes: 2)});

  static const channel = MethodChannel('retro_toolbox/shizuku');

  final int uid;
  final Duration timeout;

  @override
  Privilege get privilege => uid == 0 ? Privilege.root : Privilege.shell;

  @override
  Future<ShellResult> run(List<String> argv) async {
    try {
      final m = await channel.invokeMapMethod<String, dynamic>('exec', {'argv': argv}).timeout(timeout);
      if (m == null) return const ShellResult(ShellResult.unreachable, '', 'no reply from Shizuku');
      return ShellResult(m['code'] as int, m['out'] as String, m['err'] as String);
    } on PlatformException catch (e) {
      return ShellResult(ShellResult.unreachable, '', e.message ?? e.code);
    } on TimeoutException {
      return ShellResult(ShellResult.unreachable, '', 'timed out: ${argv.first}');
    }
  }

  static Future<ShizukuStatus> status() async {
    try {
      final m = await channel.invokeMapMethod<String, dynamic>('status');
      return ShizukuStatus(running: m?['running'] == true, granted: m?['granted'] == true, uid: (m?['uid'] as int?) ?? -1);
    } on MissingPluginException {
      return const ShizukuStatus(running: false, granted: false, uid: -1);
    } on PlatformException {
      return const ShizukuStatus(running: false, granted: false, uid: -1);
    }
  }

  /// Shows Shizuku's permission prompt. True when granted.
  static Future<bool> requestPermission() async {
    try {
      return await channel.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
