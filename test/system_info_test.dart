import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/system_info.dart';

void main() {
  test('parseOsRelease strips quotes', () {
    expect(parseOsRelease('NAME="Knulli"\nVERSION_ID=40\n'), {'NAME': 'Knulli', 'VERSION_ID': '40'});
  });

  test('parseCpuModel and parseCoreCount', () {
    const arm = 'processor\t: 0\nprocessor\t: 1\nprocessor\t: 2\nprocessor\t: 3\nHardware\t: Rockchip RK3566\n';
    expect(parseCpuModel(arm), 'Rockchip RK3566');
    expect(parseCoreCount(arm), 4);
    expect(parseCoreCount(''), 1);
    expect(parseCpuModel('processor : 0\nmodel name : Intel X\n'), 'Intel X');
  });

  test('parseMeminfo converts kB to bytes', () {
    final m = parseMeminfo('MemTotal: 2000 kB\nMemAvailable: 500 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n');
    expect(m.totalBytes, 2048000);
    expect(m.usedBytes, 1536000);
    expect(parseMeminfo('').usedBytes, isNull);
  });

  test('parseBattery', () {
    final b = parseBattery(capacity: '87\n', status: 'Discharging');
    expect(b!.percent, 87);
    expect(b.charging, false);
    expect(parseBattery(status: 'Full')!.charging, true);
    expect(parseBattery(), isNull);
  });

  test('parseThermal', () {
    expect(parseThermal('45123'), 45.1);
    expect(parseThermal('x'), isNull);
    expect(parseThermal(null), isNull);
  });

  test('reader on an empty root yields nulls and does not throw', () async {
    final tmp = Directory.systemTemp.createTempSync('sysinfo');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final s = await SystemInfoReader(root: tmp.path, env: {}).read();
    expect(s.battery, isNull);
    expect(s.cpuTempC, isNull);
    expect(s.mem.totalBytes, isNull);
    expect(s.cores, greaterThanOrEqualTo(1));
    expect(s.deviceName, isNull);
  });

  test('reader takes device and firmware from env', () async {
    final tmp = Directory.systemTemp.createTempSync('sysinfo');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final s = await SystemInfoReader(root: tmp.path, env: {'RT_DEVICE_NAME': 'RG35XX Plus', 'RT_CFW_NAME': 'Knulli'}).read();
    expect(s.deviceName, 'RG35XX Plus');
    expect(s.firmware, 'Knulli');
  });

  test('reader reads files under root', () async {
    final tmp = Directory.systemTemp.createTempSync('sysinfo');
    addTearDown(() => tmp.deleteSync(recursive: true));
    void w(String rel, String c) => (File('${tmp.path}/$rel')..createSync(recursive: true)).writeAsStringSync(c);
    w('etc/os-release', 'NAME="Knulli"\nVERSION_ID=40\n');
    w('proc/device-tree/model', 'Anbernic RG35XX\u0000');
    w('proc/sys/kernel/osrelease', '6.1.0\n');
    w('proc/meminfo', 'MemTotal: 2000 kB\nMemAvailable: 500 kB\n');
    w('sys/class/power_supply/ac/type', 'Mains\n');
    w('sys/class/power_supply/bat/type', 'Battery\n');
    w('sys/class/power_supply/bat/capacity', '55\n');
    w('sys/class/power_supply/bat/status', 'Charging\n');
    w('sys/class/thermal/thermal_zone0/temp', '40000\n');
    w('sys/class/thermal/thermal_zone1/temp', '52500\n');
    final s = await SystemInfoReader(root: tmp.path, env: {}).read();
    expect(s.osName, 'Knulli');
    expect(s.osVersion, '40');
    expect(s.firmware, 'Knulli');
    expect(s.deviceName, 'Anbernic RG35XX');
    expect(s.kernel, '6.1.0');
    expect(s.mem.usedBytes, 1536000);
    expect(s.battery!.percent, 55);
    expect(s.battery!.charging, true);
    expect(s.cpuTempC, 52.5);
  });
}
