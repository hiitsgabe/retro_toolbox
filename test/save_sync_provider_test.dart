import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/drive_backend.dart';
import 'package:retro_toolbox/services/save_sync/google_auth.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'save_sync_fake_drive.dart';

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

/// Google sign-in that answers from fields.
class FakeGoogleAuth implements GoogleAuth {
  FakeGoogleAuth({this.available = true});

  @override
  final bool available;
  GoogleAuthError? signInFails;
  String? nextToken = 'token-1';
  bool signedOut = false;

  @override
  Future<GoogleAccount> signIn() async {
    if (signInFails != null) throw signInFails!;
    return const GoogleAccount(id: '1234567890', email: 'player@gmail.com');
  }

  @override
  Future<String?> token(GoogleAccount account) async => nextToken;

  @override
  Future<void> clearToken(String token) async {}

  @override
  Future<void> signOut() async => signedOut = true;
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

  group('the hub choice', () {
    late FakeGoogleAuth google;
    late FakeDrive drive;
    late InMemorySharedPreferencesAsync prefs;

    ProviderContainer container(Map<String, Object> stored, {bool googleAvailable = true, bool shizuku = true, DevicePaths paths = const DevicePaths()}) {
      prefs = InMemorySharedPreferencesAsync.withData(stored);
      SharedPreferencesAsyncPlatform.instance = prefs;
      mockShizuku(shizuku ? {'running': true, 'granted': true, 'uid': 2000} : {'running': false, 'granted': false, 'uid': -1});
      PackageInfo.setMockInitialValues(appName: 'Retro Toolbox', packageName: 'name.rafaismy.retrotoolbox', version: '0.6.0', buildNumber: '60', buildSignature: '');
      google = FakeGoogleAuth(available: googleAvailable);
      drive = FakeDrive();
      final c = ProviderContainer(overrides: [
        saveSyncProvider.overrideWith((ref) => SaveSyncNotifier(paths: paths, google: google, driveTransport: drive)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<Object?> stored(String key) async =>
        (await prefs.getPreferences(const GetPreferencesParameters(filter: PreferencesFilters(allowList: null)), const SharedPreferencesOptions()))[key];

    test('with no hub chosen, refresh asks for one and opens nothing', () async {
      final c = container({});
      await c.read(saveSyncProvider.notifier).refresh();
      final s = c.read(saveSyncProvider);
      expect(s.hubKind, HubKind.none);
      expect(s.googleAvailable, isTrue);
      expect(s.access, SyncAccess.shizuku);
      expect(s.error, isNull);
      expect(drive.log, isEmpty);
      final lines = await c.read(saveSyncProvider.notifier).check('stardew-valley');
      expect(lines.single.detail, 'Choose where saves go first');
    });

    test('Sign in with Google stores the account, and the refresh writes the hub into that Drive', () async {
      final c = container({});
      await c.read(saveSyncProvider.notifier).signInWithGoogle();
      final s = c.read(saveSyncProvider);
      expect(s.hubKind, HubKind.drive);
      expect(s.googleEmail, 'player@gmail.com');
      expect(s.hubFolder, '');
      expect(s.signingIn, isFalse);
      expect(s.error, isNull);
      expect(await stored('save_sync_hub_kind'), 'drive');
      expect(jsonDecode(await stored('save_sync_google_account') as String), {'id': '1234567890', 'email': 'player@gmail.com'});
      for (final f in ['hub.json', 'README.txt']) {
        expect(drive.at('Retro Toolbox Saves/$f'), isNotNull, reason: f);
      }
      expect(drive.named(drive.at('Retro Toolbox Saves/devices')!.id, '${await stored('save_sync_device_id')}.json'), hasLength(1));
    });

    test('a sign-in that fails says why and leaves the hub as it was', () async {
      final c = container({'save_sync_hub_folder': '/storage/emulated/0/Hub'}, shizuku: false);
      google.signInFails = const GoogleAuthError(GoogleAuthProblem.notRegistered);
      await c.read(saveSyncProvider.notifier).signInWithGoogle();
      final s = c.read(saveSyncProvider);
      expect(s.signInError, contains('build is not registered with Google'));
      expect(s.signingIn, isFalse);
      expect(await stored('save_sync_hub_kind'), isNull);
      await c.read(saveSyncProvider.notifier).refresh();
      expect(c.read(saveSyncProvider).hubKind, HubKind.folder);
      expect(c.read(saveSyncProvider).hubFolder, '/storage/emulated/0/Hub');
    });

    test('a Drive hub that needs the user again asks to sign in again', () async {
      final c = container({
        'save_sync_hub_kind': 'drive',
        'save_sync_google_account': '{"id":"1234567890","email":"player@gmail.com"}',
      });
      google.nextToken = null;
      await c.read(saveSyncProvider.notifier).refresh();
      final s = c.read(saveSyncProvider);
      expect(s.hubKind, HubKind.drive);
      expect(s.googleEmail, 'player@gmail.com');
      expect(s.signInAgain, isTrue);
      expect(s.error, 'Sign in to Google again.');
      expect(drive.log, isEmpty);

      google.nextToken = 'token-1';
      await c.read(saveSyncProvider.notifier).refresh();
      expect(c.read(saveSyncProvider).signInAgain, isFalse);
      expect(c.read(saveSyncProvider).error, isNull);
    });

    test('a Google hub in a build without Google says so', () async {
      final c = container({
        'save_sync_hub_kind': 'drive',
        'save_sync_google_account': '{"id":"1234567890","email":"player@gmail.com"}',
      }, googleAvailable: false);
      await c.read(saveSyncProvider.notifier).refresh();
      expect(c.read(saveSyncProvider).googleAvailable, isFalse);
      expect(c.read(saveSyncProvider).error, contains('cannot sign in to Google'));
    });

    test('sign out forgets the account and asks for a hub again; the bases stay', () async {
      const base = '{"drive:1234567890#aaaa|stardew-valley|Farm_1":{"gen":"g1","files":{}}}';
      final c = container({
        'save_sync_hub_kind': 'drive',
        'save_sync_google_account': '{"id":"1234567890","email":"player@gmail.com"}',
        'save_sync_bases': base,
      }, shizuku: false);
      await c.read(saveSyncProvider.notifier).signOut();
      expect(google.signedOut, isTrue);
      expect(c.read(saveSyncProvider).hubKind, HubKind.none);
      expect(await stored('save_sync_bases'), base);
    });

    test('Use a folder picks the default folder; recipes the Drive hub published go with it', () async {
      final tmp = await Directory.systemTemp.createTemp('rt-provider-');
      addTearDown(() => tmp.delete(recursive: true));
      final c = container({}, paths: DevicePaths(sdcard: tmp.path));
      final odin = Hub(DriveBackend('1234567890', DriveApi(drive, FakeTokens(['token-1']))));
      await odin.open(deviceId: 'odin-02c4');
      final raw = jsonDecode(File('save_recipes/stardew-valley.json').readAsStringSync()) as Map<String, dynamic>;
      await odin.publishRecipe({...raw, 'id': 'hub-only-game', 'name': 'Hub Only Game'}, source: 'user', deviceId: 'odin-02c4', now: DateTime.utc(2026, 11, 12));

      await c.read(saveSyncProvider.notifier).signInWithGoogle();
      expect(c.read(saveSyncProvider).games.map((g) => g.recipe.id), contains('hub-only-game'));

      await c.read(saveSyncProvider.notifier).setHubFolder();
      final s = c.read(saveSyncProvider);
      expect(s.hubKind, HubKind.folder);
      expect(s.hubFolder, '${tmp.path}/Retro Toolbox Saves');
      expect(s.games.map((g) => g.recipe.id), isNot(contains('hub-only-game')));
    });
  });
}
