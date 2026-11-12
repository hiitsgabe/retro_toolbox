import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/services/save_sync/sync_state.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

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

  test('the hub choice: none at first, a folder, a Google account, then none again', () async {
    final s = SyncState(MemoryStore());
    expect(s.hubChoice, isNull);
    await s.setHubChoice(const FolderHub('/storage/emulated/0/Retro Toolbox Saves'));
    expect(s.hubChoice, isA<FolderHub>().having((h) => h.path, 'path', '/storage/emulated/0/Retro Toolbox Saves'));
    await s.setHubChoice(const DriveHub(accountId: '1234567890', email: 'player@gmail.com'));
    expect(s.hubChoice, isA<DriveHub>().having((h) => h.accountId, 'accountId', '1234567890').having((h) => h.email, 'email', 'player@gmail.com'));
    await s.setHubChoice(null);
    expect(s.hubChoice, isNull);
    expect(s.hubFolder, '/storage/emulated/0/Retro Toolbox Saves', reason: 'kept for the next switch back to a folder');
  });

  test('a hub folder stored before hub kinds existed is a folder hub', () {
    final store = MemoryStore()..values['save_sync_hub_folder'] = '/storage/emulated/0/Hub';
    expect(SyncState(store).hubChoice, isA<FolderHub>().having((h) => h.path, 'path', '/storage/emulated/0/Hub'));
  });

  test('a Google hub whose stored account cannot be read is no choice', () {
    final store = MemoryStore()
      ..values['save_sync_hub_kind'] = 'drive'
      ..values['save_sync_google_account'] = '{oops';
    expect(SyncState(store).hubChoice, isNull);
  });

  test('corrupt stored JSON reads as empty instead of throwing', () async {
    final store = MemoryStore()..values['save_sync_bindings'] = '{oops';
    expect(SyncState(store).binding('x'), isNull);
  });

  group('PrefsStore', () {
    const binding = Binding(recipe: 'stardew-valley', package: 'com.chucklefish.stardewvalley', area: Area.androidData, root: 'files/Saves');

    test('a value written comes back from the cache, and a second store on the same backend reads it', () async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      final first = SyncState(await PrefsStore.open());
      await first.setHubFolder('/x');
      await first.setBinding(binding);
      final id = await first.deviceId('AYN Thor', random: Random(3));
      expect(first.hubFolder, '/x');
      expect(first.binding('stardew-valley')!.root, 'files/Saves');

      final second = SyncState(await PrefsStore.open());
      expect(second.hubFolder, '/x');
      expect(second.binding('stardew-valley')!.root, 'files/Saves');
      expect(await second.deviceId('Something Else', random: Random(4)), id);
    });

    test('on Android it is its own SharedPreferences file, the one the backup rules exclude', () async {
      final options = PrefsStore.options(android: true);
      expect(options, isA<SharedPreferencesAsyncAndroidOptions>());
      final android = options as SharedPreferencesAsyncAndroidOptions;
      // DataStore would ignore the file name and keep the state in a file the rules do not name.
      expect(android.backend, SharedPreferencesAndroidBackendLibrary.SharedPreferences);
      final file = android.originalSharedPreferencesOptions?.fileName;
      expect(file, isNotNull);
      expect(file, isNot('FlutterSharedPreferences'));

      final exclude = '<exclude domain="sharedpref" path="$file.xml" />';
      const res = 'android/app/src/main/res/xml';
      final full = File('$res/backup_rules.xml').readAsStringSync();
      final extraction = File('$res/data_extraction_rules.xml').readAsStringSync();
      expect(RegExp('<exclude ').allMatches(full).length, 1);
      expect(full, contains(exclude));
      expect(RegExp('<include ').hasMatch(full), isFalse, reason: 'an include would stop everything else being backed up');
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(extraction)?.group(1);
        expect(body, isNotNull, reason: section);
        expect(RegExp('<exclude ').allMatches(body!).length, 1, reason: section);
        expect(body, contains(exclude), reason: section);
      }
      expect(RegExp('<include ').hasMatch(extraction), isFalse, reason: 'an include would stop everything else being backed up');

      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    });
  });
}
