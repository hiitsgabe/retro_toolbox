import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/process_list.dart';

typedef FakeProc = ({int ppid, String name, String cmd, int rssKb});

Directory fakeProc(Map<int, FakeProc> procs) {
  final root = Directory.systemTemp.createTempSync('fakeproc');
  addTearDown(() => root.deleteSync(recursive: true));
  procs.forEach((pid, p) {
    final d = Directory('${root.path}/$pid')..createSync();
    File('${d.path}/stat').writeAsStringSync('$pid (${p.name}) S ${p.ppid} 0 0 0 0 0 0\n');
    File('${d.path}/status').writeAsStringSync('Name:\t${p.name}\nVmRSS:\t${p.rssKb} kB\n');
    File('${d.path}/cmdline').writeAsStringSync(p.cmd.isEmpty ? '' : '${p.cmd.split(' ').join('\x00')}\x00');
  });
  return root;
}

void main() {
  final procs = <int, FakeProc>{
    1: (ppid: 0, name: 'init', cmd: '/sbin/init', rssKb: 2000),
    2: (ppid: 0, name: 'kthreadd', cmd: '', rssKb: 0),
    3: (ppid: 2, name: 'rcu_gp', cmd: '', rssKb: 0),
    40: (ppid: 1, name: 'sh', cmd: 'sh run.sh', rssKb: 1000),
    50: (ppid: 40, name: 'app', cmd: 'app --x', rssKb: 5000),
    60: (ppid: 1, name: 'retroarch', cmd: 'retroarch -L core', rssKb: 300 * 1024),
    61: (ppid: 1, name: 'tailscaled', cmd: 'tailscaled', rssKb: 20000),
    62: (ppid: 1, name: 'gptokeyb', cmd: 'gptokeyb -1', rssKb: 3000),
    63: (ppid: 1, name: 'emulationstatio', cmd: '/usr/bin/emulationstation --x', rssKb: 40000),
    64: (ppid: 1, name: 'weird', cmd: '', rssKb: 100),
  };

  test('sorted by rss, protection rules, rss==0 kernel threads dropped', () async {
    final root = fakeProc(procs);
    final list = await ProcessList(procRoot: root.path, selfPid: 50).list();
    expect(list.first.name, 'retroarch');
    expect(list.first.rssBytes, 300 * 1024 * 1024);
    expect(list.first.cmdline, 'retroarch -L core');
    expect(list.map((e) => e.pid), isNot(contains(2)));
    expect(list.map((e) => e.pid), isNot(contains(3)));
    bool prot(int pid) => list.firstWhere((e) => e.pid == pid).protected;
    expect(prot(60), isFalse);
    expect(prot(61), isFalse);
    expect(prot(62), isTrue);
    expect(prot(63), isTrue); // comm is truncated to 15 chars, argv0 matches
    expect(prot(1), isTrue);
    expect(prot(64), isTrue); // empty cmdline
    expect(prot(40), isTrue);
    expect(prot(50), isTrue);
  });

  test('end refuses protected pids without signalling', () async {
    final root = fakeProc(procs);
    expect(await ProcessList(procRoot: root.path, selfPid: 50).end(62), EndResult.refused);
    expect(await ProcessList(procRoot: root.path, selfPid: 50).end(1), EndResult.refused);
  });

  test('end of a missing pid is alreadyGone', () async {
    final root = fakeProc(procs);
    expect(await ProcessList(procRoot: root.path, selfPid: 50).end(999), EndResult.alreadyGone);
  });

  test('end with a name leaves a pid now held by another process alone', () async {
    final child = await Process.start('sleep', ['30']);
    addTearDown(() => child.kill(ProcessSignal.sigkill));
    final root = fakeProc({
      1: (ppid: 0, name: 'init', cmd: '/sbin/init', rssKb: 2000),
      child.pid: (ppid: 1, name: 'other', cmd: 'other', rssKb: 100),
    });
    expect(await ProcessList(procRoot: root.path, selfPid: 50).end(child.pid, name: 'retroarch'), EndResult.alreadyGone);
    expect(await child.exitCode.timeout(const Duration(milliseconds: 200), onTimeout: () => -1), -1, reason: 'was signalled');
  });

  test('ancestors with invalid UTF-8 are still parsed and keep their parents protected', () async {
    final root = fakeProc({
      1: (ppid: 0, name: 'init', cmd: '/sbin/init', rssKb: 2000),
      30: (ppid: 1, name: 'launcher', cmd: 'launcher.sh', rssKb: 1000),
      40: (ppid: 30, name: 'sh', cmd: 'sh', rssKb: 1000),
      50: (ppid: 40, name: 'app', cmd: 'app', rssKb: 5000),
    });
    File('${root.path}/40/cmdline').writeAsBytesSync([0x73, 0x68, 0x20, 0xff, 0xfe, 0x00]);
    File('${root.path}/40/stat').writeAsBytesSync([...'40 (s'.codeUnits, 0xff, ...') S 30 0 0'.codeUnits]);
    final list = await ProcessList(procRoot: root.path, selfPid: 50).list();
    expect(list.firstWhere((e) => e.pid == 40).protected, isTrue);
    expect(list.firstWhere((e) => e.pid == 30).protected, isTrue);
  });
}
