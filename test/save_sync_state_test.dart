import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('device id is made once and kept', () async {
    final s = SyncState(MemoryStore());
    final a = await s.deviceId('AYN Thor', random: Random(3));
    final b = await s.deviceId('Something Else', random: Random(4));
    expect(a, b);
    expect(a, startsWith('ayn-thor-'));
  });

  test('bindings, bases and last actions round-trip', () async {
    final s = SyncState(MemoryStore());
    const binding = Binding(recipe: 'stardew-valley', package: 'com.chucklefish.stardewvalley', area: Area.androidData, root: 'files/Saves');
    await s.setBinding(binding);
    expect(s.binding('stardew-valley')!.root, 'files/Saves');
    await s.clearBinding('stardew-valley');
    expect(s.binding('stardew-valley'), isNull);

    await s.setBase('folder:/hub', 'stardew-valley', 'Farm_1', const Base('g1', {'Farm_1/Farm_1': 'h'}));
    expect(s.base('folder:/hub', 'stardew-valley', 'Farm_1')!.gen, 'g1');
    expect(s.base('folder:/other', 'stardew-valley', 'Farm_1'), isNull);

    await s.setLast('stardew-valley', 'push', DateTime.utc(2026, 11, 10, 22));
    expect(s.last('stardew-valley', 'push'), DateTime.utc(2026, 11, 10, 22));
    expect(s.last('stardew-valley', 'pull'), isNull);

    await s.setHubFolder('/storage/emulated/0/Retro Toolbox Saves');
    expect(s.hubFolder, '/storage/emulated/0/Retro Toolbox Saves');
  });

  test('a base under another hub id is found only when its gen is listed and the backend is the same', () async {
    final s = SyncState(MemoryStore());
    const files = {'Farm_1/Farm_1': 'h'};
    await s.setBase('folder:/hub#aaaa', 'stardew-valley', 'Farm_1', const Base('20261110T220100Z-thor-7f3a-00000001', files));
    await s.setBase('folder:/hub#bbbb', 'stardew-valley', 'Farm_1', const Base('20261110T220500Z-thor-7f3a-00000005', files));
    await s.setBase('folder:/usb#cccc', 'stardew-valley', 'Farm_1', const Base('20261110T220900Z-thor-7f3a-00000009', files));
    await s.setBase('folder:/hub#x#dddd', 'stardew-valley', 'Farm_1', const Base('20261110T220800Z-thor-7f3a-00000008', files));
    await s.setBase('folder:/hub#eeee', 'stardew-valley', 'Farm_2', const Base('20261110T220700Z-thor-7f3a-00000007', files));
    const listed = {
      '20261110T220100Z-thor-7f3a-00000001',
      '20261110T220700Z-thor-7f3a-00000007',
      '20261110T220800Z-thor-7f3a-00000008',
      '20261110T220900Z-thor-7f3a-00000009',
    };

    // bbbb's gen is newer but not listed; usb#cccc, hub#x#dddd and Farm_2 are listed but not this backend's Farm_1.
    expect(s.baseUnderOtherHubId('folder:/hub', 'stardew-valley', 'Farm_1', listed)!.gen, '20261110T220100Z-thor-7f3a-00000001');
    expect(s.baseUnderOtherHubId('folder:/hub', 'stardew-valley', 'Farm_1', {...listed, '20261110T220500Z-thor-7f3a-00000005'})!.gen,
        '20261110T220500Z-thor-7f3a-00000005');
    expect(s.baseUnderOtherHubId('folder:/hub', 'stardew-valley', 'Farm_1', listed.difference({'20261110T220100Z-thor-7f3a-00000001'})), isNull);
  });

  test('corrupt stored JSON reads as empty instead of throwing', () async {
    final store = MemoryStore()..values['save_sync_bindings'] = '{oops';
    expect(SyncState(store).binding('x'), isNull);
  });

  test('PrefsStore reads and writes shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final s = SyncState(PrefsStore(prefs));
    await s.setHubFolder('/x');
    expect(prefs.getString('save_sync_hub_folder'), '/x');
  });
}
