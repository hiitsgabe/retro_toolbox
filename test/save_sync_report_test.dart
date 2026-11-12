import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/hub_report.dart';

void main() {
  final thor = DeviceReport(
    id: 'thor-7f3a',
    name: 'AYN Thor',
    model: 'AYN Thor',
    toolboxVersion: '0.6.0',
    lastSeen: DateTime.utc(2026, 11, 10, 22, 41),
    access: 'shizuku',
    games: [
      GameReport(recipe: 'stardew-valley', name: 'Stardew Valley', package: 'com.chucklefish.stardewvalley', version: '1.6.15.2', state: 'ready', units: const ['Farm_1'], lastPush: DateTime.utc(2026, 11, 10, 22, 41)),
      const GameReport(recipe: 'sea-of-stars', name: 'Sea of Stars', state: 'not installed'),
    ],
  );

  test('DeviceReport JSON round-trip, tolerant of missing fields', () {
    final back = DeviceReport.fromJson(thor.toJson());
    expect(back.games.first.units, ['Farm_1']);
    expect(back.games.first.lastPush, DateTime.utc(2026, 11, 10, 22, 41));
    expect(back.games.last.version, isNull);
    final sparse = DeviceReport.fromJson({'id': 'odin-02c4'});
    expect(sparse.name, 'odin-02c4');
    expect(sparse.games, isEmpty);
  });

  test('README lists devices, their games and the newest save per unit', () {
    final gen = GenMeta(
      gen: '20261110T224107Z-thor-7f3a-9f2c01e1',
      parents: const [],
      recipe: 'stardew-valley',
      unit: 'Farm_1',
      device: 'thor-7f3a',
      deviceName: 'AYN Thor',
      createdAt: DateTime.utc(2026, 11, 10, 22, 41, 7),
      package: 'com.chucklefish.stardewvalley',
      files: const {},
      payloadSha256: 'f' * 64,
    );
    final text = buildReadme(
      devices: [thor],
      gameNames: const {'stardew-valley': 'Stardew Valley'},
      newest: {
        'stardew-valley': {'Farm_1': gen},
      },
      writtenBy: 'AYN Thor',
      now: DateTime.utc(2026, 11, 10, 22, 45),
    );
    expect(text, startsWith('Retro Toolbox Saves\n'));
    expect(text, contains('Updated 2026-11-10 22:45 UTC by AYN Thor.'));
    expect(text, contains('AYN Thor (thor-7f3a): last seen 2026-11-10 22:41 UTC, access shizuku'));
    expect(text, contains('  Stardew Valley: 1.6.15.2, ready, saves here: Farm_1'));
    expect(text, contains('  Sea of Stars: not installed'));
    expect(text, contains('Stardew Valley (stardew-valley)\n  Farm_1: 20261110T224107Z-thor-7f3a-9f2c01e1, by AYN Thor, 2026-11-10 22:41 UTC'));
  });
}
