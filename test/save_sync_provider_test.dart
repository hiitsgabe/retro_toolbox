import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

/// A notifier caught in the middle of an action on [recipe].
class BusyNotifier extends SaveSyncNotifier {
  BusyNotifier(String recipe) {
    state = SaveSyncState(busyRecipe: recipe);
  }

  void finish() => state = state.copyWith(clearBusy: true);
}

/// In-memory preferences that count full reads (one per store opened) and can fail the next one.
final class CountingPrefs extends InMemorySharedPreferencesAsync {
  CountingPrefs(super.data) : super.withData();

  int reads = 0;
  bool failNextRead = false;

  @override
  Future<Map<String, Object>> getPreferences(GetPreferencesParameters parameters, SharedPreferencesOptions options) {
    reads++;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('prefs unavailable');
    }
    return super.getPreferences(parameters, options);
  }
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
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({'save_sync_hub_folder': hubFolder});
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
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
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

  test('the notifier opens the save sync store once, and again only after an open that failed', () async {
    const hubFolder = '/storage/emulated/0/Hub';
    final prefs = CountingPrefs({'save_sync_hub_folder': hubFolder});
    SharedPreferencesAsyncPlatform.instance = prefs;
    mockShizuku({'running': false, 'granted': false, 'uid': -1});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final notifier = c.read(saveSyncProvider.notifier);

    prefs.failNextRead = true;
    await notifier.refresh();
    expect(c.read(saveSyncProvider).error, contains('prefs unavailable'));

    await notifier.refresh();
    expect(c.read(saveSyncProvider).error, isNull);
    expect(c.read(saveSyncProvider).hubFolder, hubFolder);
    expect(prefs.reads, 2);

    // Every store caches what it read: a second one would write over the first one's newer bindings and bases.
    await notifier.refresh();
    await notifier.setHubFolder('/storage/emulated/0/Other');
    expect(prefs.reads, 2);
  });
}
