import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A notifier caught in the middle of an action on [recipe].
class BusyNotifier extends SaveSyncNotifier {
  BusyNotifier(String recipe) {
    state = SaveSyncState(busyRecipe: recipe);
  }

  void finish() => state = state.copyWith(clearBusy: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers Shizuku's status with [status] and records every method called.
  List<String> mockShizuku(Map<String, Object> status) {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ShizukuShell.channel, (call) async {
      calls.add(call.method);
      return call.method == 'status' ? status : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(ShizukuShell.channel, null));
    return calls;
  }

  test('a hub that cannot be opened still shows the access and the hub folder', () async {
    final tmp = await Directory.systemTemp.createTemp('rt-provider-');
    addTearDown(() => tmp.delete(recursive: true));
    // A file where the hub's parent folder should be: like a removed SD card, nothing can be created under it.
    final card = await File('${tmp.path}/card').create();
    final hubFolder = '${card.path}/Retro Toolbox Saves';
    SharedPreferences.setMockInitialValues({'save_sync_hub_folder': hubFolder});
    mockShizuku({'running': true, 'granted': true, 'uid': 2000});
    final c = ProviderContainer();
    addTearDown(c.dispose);

    await c.read(saveSyncProvider.notifier).refresh();

    final s = c.read(saveSyncProvider);
    expect(s.error, contains(card.path), reason: 'the refresh fails in hub.open');
    expect(s.loading, isFalse);
    expect(s.games, isEmpty);
    expect(s.access, SyncAccess.shizuku);
    expect(s.shizukuRunning, isTrue);
    expect(s.hubFolder, hubFolder);
  });

  test('refresh does nothing while an action is running', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = mockShizuku({'running': false, 'granted': false, 'uid': -1});
    final busy = BusyNotifier('stardew-valley');
    final c = ProviderContainer(overrides: [saveSyncProvider.overrideWith((ref) => busy)]);
    addTearDown(c.dispose);

    await c.read(saveSyncProvider.notifier).refresh();
    expect(calls, isEmpty);

    // The same refresh once the action is over does ask Shizuku, so the empty list above is the guard.
    busy.finish();
    await c.read(saveSyncProvider.notifier).refresh();
    expect(calls, ['status']);
  });
}
