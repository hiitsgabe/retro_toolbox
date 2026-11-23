import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/launch_preset.dart';

/// Runs and starts processes; a fake in tests, so they never spawn anything.
abstract class ProcessRunner {
  Future<ProcessResult> run(String executable, List<String> arguments);

  Future<Process> start(String executable, List<String> arguments);
}

class IoProcessRunner implements ProcessRunner {
  const IoProcessRunner();

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) => Process.run(executable, arguments);

  @override
  Future<Process> start(String executable, List<String> arguments) => Process.start(executable, arguments);
}

/// A desktop emulator found by a find rule.
class DesktopHit {
  const DesktopHit({required this.exe, this.prefixArgs = const [], this.flatpakId});

  final String exe;

  /// Before the preset's args: `run <id>` for a flatpak.
  final List<String> prefixArgs;
  final String? flatpakId;

  /// What a launch choice records: the flatpak id, or the executable.
  String get variant => flatpakId ?? exe;
}

/// Runs a preset's find rules in order; the first hit wins.
class DesktopFinder {
  DesktopFinder({required this.os, ProcessRunner? runner, Map<String, String>? env})
      : runner = runner ?? const IoProcessRunner(),
        env = env ?? Platform.environment;

  final String os;
  final ProcessRunner runner;
  final Map<String, String> env;

  p.Context get _path => os == 'windows' ? p.windows : p.posix;

  Future<DesktopHit?> find(List<FindRule> rules) async {
    for (final rule in rules) {
      final hit = await _try(rule);
      if (hit != null) return hit;
    }
    return null;
  }

  Future<DesktopHit?> _try(FindRule rule) async {
    try {
      switch (rule.type) {
        case FindType.path:
          for (final name in rule.names) {
            final r = await runner.run(os == 'windows' ? 'where' : 'which', [name]);
            final first = r.exitCode == 0 ? '${r.stdout}'.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '') : '';
            if (first.isNotEmpty) return DesktopHit(exe: first);
          }
        case FindType.staticPaths:
          for (final raw in rule.paths) {
            final found = _glob(expand(raw));
            if (found != null) return DesktopHit(exe: found);
          }
        case FindType.flatpak:
          final r = await runner.run('flatpak', ['info', rule.id!]);
          if (r.exitCode == 0) return DesktopHit(exe: 'flatpak', prefixArgs: ['run', rule.id!], flatpakId: rule.id);
        case FindType.app:
          for (final raw in rule.paths) {
            final bundle = expand(raw);
            final plist = File(_path.join(bundle, 'Contents', 'Info.plist'));
            if (!plist.existsSync()) continue;
            final m = RegExp(r'<key>CFBundleExecutable</key>\s*<string>([^<]+)</string>').firstMatch(plist.readAsStringSync());
            if (m == null) continue;
            final exe = _path.join(bundle, 'Contents', 'MacOS', m[1]!.trim());
            if (File(exe).existsSync()) return DesktopHit(exe: exe);
          }
        case FindType.registry:
          if (os != 'windows') return null;
          final r = await runner.run('reg', ['query', rule.key!, '/v', rule.value!]);
          if (r.exitCode != 0) return null;
          final m = RegExp('${RegExp.escape(rule.value!)}\\s+REG_\\w+\\s+(.+)').firstMatch('${r.stdout}');
          if (m == null) return null;
          final data = m[1]!.trim();
          final exe = rule.file == null ? data : _path.join(data, rule.file!);
          if (File(exe).existsSync()) return DesktopHit(exe: exe);
      }
    } on ProcessException {
      // which, where, flatpak or reg is not there: this rule finds nothing.
    } on FileSystemException {
      // A binary Info.plist or a folder we may not list: one bad file must not
      // stop the later rules, or the other presets, from being tried.
    }
    return null;
  }

  /// `%VAR%` from the environment and a leading `~` as the home folder.
  String expand(String raw) {
    var s = raw.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) => env[m[1]!] ?? m[0]!);
    final home = env['HOME'] ?? env['USERPROFILE'];
    if (home != null && (s == '~' || s.startsWith('~/') || s.startsWith(r'~\'))) s = home + s.substring(1);
    return s;
  }

  /// [pattern] itself when it exists, or the first match of a `*` in its
  /// file name (folders take no wildcards), in name order.
  String? _glob(String pattern) {
    final name = _path.basename(pattern);
    if (!name.contains('*')) return File(pattern).existsSync() ? pattern : null;
    final dir = Directory(_path.dirname(pattern));
    if (!dir.existsSync()) return null;
    final re = RegExp('^${name.split('*').map(RegExp.escape).join('.*')}\$');
    final hits = [for (final e in dir.listSync()) if (e is File && re.hasMatch(_path.basename(e.path))) e.path]..sort();
    return hits.firstOrNull;
  }
}
