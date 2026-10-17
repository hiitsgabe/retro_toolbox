import 'dart:io';

/// Processes the device needs to keep running; they never get an end action.
const protectedNames = {
  'gptokeyb', 'gptokeyb2', 'emulationstation', 'es', 'frontend', 'muxlaunch', 'muxfrontend', 'udevd', 'systemd-udevd', 'dbus-daemon', //
  'wpa_supplicant', 'connmand', 'NetworkManager', 'dhcpcd', 'udhcpc', 'iwd', 'systemd', 'init', 'Xorg', 'weston', 'sway', 'flutter-pi',
};

class ProcessEntry {
  final int pid, ppid;
  final String name;
  final String cmdline;
  final int rssBytes;
  final bool protected;
  const ProcessEntry({
    required this.pid,
    required this.ppid,
    required this.name,
    required this.cmdline,
    required this.rssBytes,
    required this.protected,
  });
}

enum EndResult { ended, stillRunning, alreadyGone, refused }

class ProcessList {
  ProcessList({this.procRoot = '/proc', int? selfPid}) : selfPid = selfPid ?? pid;

  final String procRoot;
  final int selfPid;

  /// Every readable process, protected flags set. Pids that vanish mid-read are skipped.
  Future<List<ProcessEntry>> _scan() async {
    final raw = <int, ({int ppid, String name, String cmd, int rss})>{};
    final List<FileSystemEntity> dirs;
    try {
      dirs = await Directory(procRoot).list().toList();
    } on FileSystemException {
      return [];
    }
    for (final d in dirs) {
      final p = int.tryParse(d.uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (p == null) continue;
      try {
        final stat = await File('${d.path}/stat').readAsString();
        final open = stat.indexOf('('), close = stat.lastIndexOf(')');
        final ppid = int.parse(stat.substring(close + 1).trim().split(' ')[1]);
        final status = await File('${d.path}/status').readAsString();
        final kb = RegExp(r'^VmRSS:\s*(\d+)', multiLine: true).firstMatch(status)?.group(1);
        final cmd = (await File('${d.path}/cmdline').readAsString()).replaceAll('\x00', ' ').trim();
        raw[p] = (ppid: ppid, name: stat.substring(open + 1, close), cmd: cmd, rss: (int.tryParse(kb ?? '') ?? 0) * 1024);
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on RangeError {
        continue;
      }
    }
    final self = <int>{};
    for (var p = selfPid; raw.containsKey(p) && self.add(p) && p != 1; p = raw[p]!.ppid) {}
    return [
      for (final e in raw.entries)
        ProcessEntry(
          pid: e.key,
          ppid: e.value.ppid,
          name: e.value.name,
          cmdline: e.value.cmd,
          rssBytes: e.value.rss,
          protected: e.key == 1 ||
              _isKernel(e.key, e.value.ppid, e.value.cmd) ||
              self.contains(e.key) ||
              protectedNames.contains(e.value.name) ||
              // comm is cut at 15 chars, so also match the executable's basename
              protectedNames.contains(e.value.cmd.split(' ').first.split('/').last),
        ),
    ];
  }

  static bool _isKernel(int pid, int ppid, String cmd) => cmd.isEmpty || ppid == 2 || pid == 2;

  Future<List<ProcessEntry>> list() async {
    final all = await _scan();
    return all.where((e) => !(e.rssBytes == 0 && _isKernel(e.pid, e.ppid, e.cmdline))).toList()..sort((a, b) => b.rssBytes.compareTo(a.rssBytes));
  }

  Future<EndResult> end(int pid, {bool force = false}) async {
    final entry = (await _scan()).where((e) => e.pid == pid).firstOrNull;
    if (entry == null) return EndResult.alreadyGone;
    if (entry.protected) return EndResult.refused;
    if (!Process.killPid(pid, force ? ProcessSignal.sigkill : ProcessSignal.sigterm)) return EndResult.alreadyGone;
    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!Directory('$procRoot/$pid').existsSync()) return EndResult.ended;
    }
    return EndResult.stillRunning;
  }
}
