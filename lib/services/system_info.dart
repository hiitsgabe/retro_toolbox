import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

class MemInfo {
  final int? totalBytes, availableBytes, swapTotalBytes, swapFreeBytes;
  const MemInfo({this.totalBytes, this.availableBytes, this.swapTotalBytes, this.swapFreeBytes});

  int? get usedBytes => totalBytes == null || availableBytes == null ? null : totalBytes! - availableBytes!;
}

class BatteryInfo {
  final int? percent;
  final bool? charging;
  const BatteryInfo({this.percent, this.charging});
}

class SystemSnapshot {
  final String? deviceName, firmware, osName, osVersion, kernel, cpuModel, glibc, hostname;
  final int cores;
  final MemInfo mem;
  final BatteryInfo? battery;
  final double? cpuTempC;
  const SystemSnapshot({
    this.deviceName,
    this.firmware,
    this.osName,
    this.osVersion,
    this.kernel,
    this.cpuModel,
    this.glibc,
    this.hostname,
    this.cores = 1,
    this.mem = const MemInfo(),
    this.battery,
    this.cpuTempC,
  });
}

Map<String, String> parseOsRelease(String text) {
  final out = <String, String>{};
  for (final line in text.split('\n')) {
    final i = line.indexOf('=');
    if (i <= 0 || line.trimLeft().startsWith('#')) continue;
    var v = line.substring(i + 1).trim();
    if (v.length >= 2 && (v.startsWith('"') && v.endsWith('"') || v.startsWith("'") && v.endsWith("'"))) v = v.substring(1, v.length - 1);
    out[line.substring(0, i).trim()] = v;
  }
  return out;
}

String? parseCpuModel(String cpuinfo) {
  for (final line in cpuinfo.split('\n')) {
    final i = line.indexOf(':');
    if (i < 0) continue;
    final k = line.substring(0, i).trim();
    final v = line.substring(i + 1).trim();
    if ((k == 'model name' || k == 'Hardware' || k == 'Model') && v.isNotEmpty) return v;
  }
  return null;
}

int parseCoreCount(String cpuinfo) => math.max(1, RegExp(r'^processor\s*:', multiLine: true).allMatches(cpuinfo).length);

MemInfo parseMeminfo(String text) {
  int? kb(String key) {
    final m = RegExp('^$key:\\s*(\\d+)', multiLine: true).firstMatch(text);
    return m == null ? null : int.parse(m.group(1)!) * 1024;
  }

  return MemInfo(totalBytes: kb('MemTotal'), availableBytes: kb('MemAvailable'), swapTotalBytes: kb('SwapTotal'), swapFreeBytes: kb('SwapFree'));
}

BatteryInfo? parseBattery({String? capacity, String? status}) {
  if (capacity == null && status == null) return null;
  final s = status?.trim();
  return BatteryInfo(percent: int.tryParse(capacity?.trim() ?? ''), charging: s == null ? null : s == 'Charging' || s == 'Full');
}

double? parseThermal(String? milliC) {
  final n = int.tryParse(milliC?.trim() ?? '');
  return n == null ? null : (n / 100).round() / 10;
}

class SystemInfoReader {
  final String root;
  final Map<String, String> env;
  SystemInfoReader({this.root = '/', Map<String, String>? env}) : env = env ?? Platform.environment;

  Future<String?> _read(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _glibc() async {
    try {
      final r = await Process.run('ldd', ['--version']);
      final line = r.stdout.toString().split('\n').first.trim();
      return line.isEmpty ? null : line.split(RegExp(r'\s+')).last;
    } catch (_) {
      return null;
    }
  }

  Future<BatteryInfo?> _battery() async {
    try {
      final dirs = await Directory(p.join(root, 'sys/class/power_supply')).list().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final d in dirs) {
        if ((await _read(p.join(d.path, 'type')))?.trim() == 'Battery') {
          return parseBattery(
            capacity: await _read(p.join(d.path, 'capacity')),
            status: await _read(p.join(d.path, 'status')),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  Future<double?> _cpuTemp() async {
    double? max;
    try {
      await for (final d in Directory(p.join(root, 'sys/class/thermal')).list()) {
        if (!p.basename(d.path).startsWith('thermal_zone')) continue;
        final t = parseThermal(await _read(p.join(d.path, 'temp')));
        if (t != null && (max == null || t > max)) max = t;
      }
    } catch (_) {}
    return max;
  }

  Future<SystemSnapshot> read() async {
    final os = parseOsRelease(await _read(p.join(root, 'etc/os-release')) ?? '');
    final cpuinfo = await _read(p.join(root, 'proc/cpuinfo'));
    final model = (await _read(p.join(root, 'proc/device-tree/model')))?.replaceAll('\u0000', '').trim();
    final deviceEnv = env['RT_DEVICE_NAME'], cfwEnv = env['RT_CFW_NAME'];
    String? nonEmpty(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
    final osName = nonEmpty(os['NAME']);
    return SystemSnapshot(
      deviceName: nonEmpty(deviceEnv) ?? nonEmpty(model),
      firmware: nonEmpty(cfwEnv) ?? osName,
      osName: osName,
      osVersion: nonEmpty(os['VERSION_ID'] ?? os['VERSION']),
      kernel: nonEmpty(await _read(p.join(root, 'proc/sys/kernel/osrelease'))),
      cpuModel: cpuinfo == null ? null : parseCpuModel(cpuinfo),
      glibc: await _glibc(),
      hostname: nonEmpty(await _read(p.join(root, 'proc/sys/kernel/hostname'))),
      cores: cpuinfo == null ? math.max(1, Platform.numberOfProcessors) : parseCoreCount(cpuinfo),
      mem: parseMeminfo(await _read(p.join(root, 'proc/meminfo')) ?? ''),
      battery: await _battery(),
      cpuTempC: await _cpuTemp(),
    );
  }
}
