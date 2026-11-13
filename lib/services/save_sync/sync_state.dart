import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

abstract class SyncStore {
  String? get(String key);
  Future<void> set(String key, String value);
}

/// Save sync state in its own preferences file, kept out of Android backup and
/// device transfer: a handheld restored from another must not come up with
/// that one's device id and bases, or its next push would claim the other's
/// history and every device would pull it over its own progress.
class PrefsStore implements SyncStore {
  PrefsStore(this.prefs);

  final SharedPreferencesWithCache prefs;

  /// The excludes in android/app/src/main/res/xml name this file plus `.xml`.
  static const fileName = 'retro_toolbox_save_sync';

  /// The app's other settings stay in the default file, which is still backed up.
  static SharedPreferencesOptions options({required bool android}) => android
      ? const SharedPreferencesAsyncAndroidOptions(
          backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
          originalSharedPreferencesOptions: AndroidSharedPreferencesStoreOptions(fileName: fileName),
        )
      : const SharedPreferencesOptions();

  /// Reads the whole file once; gets come from that cache, sets write through.
  static Future<PrefsStore> open() async => PrefsStore(await SharedPreferencesWithCache.create(
        sharedPreferencesOptions: options(android: Platform.isAndroid),
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      ));

  @override
  String? get(String key) => prefs.getString(key);

  @override
  Future<void> set(String key, String value) => prefs.setString(key, value);
}

class MemoryStore implements SyncStore {
  final values = <String, String>{};

  @override
  String? get(String key) => values[key];

  @override
  Future<void> set(String key, String value) async => values[key] = value;
}

/// Where this device's hub lives: a folder another app syncs, or one Google
/// account's Drive.
sealed class HubChoice {
  const HubChoice();
}

class FolderHub extends HubChoice {
  const FolderHub(this.path);

  final String path;
}

class DriveHub extends HubChoice {
  const DriveHub({required this.accountId, required this.email});

  /// Google's id for the account. It is part of the backend id, so each
  /// account is its own hub and bases never mix between accounts.
  final String accountId;
  final String email;
}

/// What this device remembers: its id, its hub, recipe bindings, the base of
/// every unit per hub, and when each game was last pushed or pulled.
class SyncState {
  SyncState(this._store);

  final SyncStore _store;

  static const _deviceKey = 'save_sync_device_id';
  static const _hubKey = 'save_sync_hub_folder';
  static const _bindingsKey = 'save_sync_bindings';
  static const _basesKey = 'save_sync_bases';
  static const _lastKey = 'save_sync_last';
  static const _hubKindKey = 'save_sync_hub_kind';
  static const _googleKey = 'save_sync_google_account';

  Future<String> deviceId(String model, {Random? random}) async {
    final have = _store.get(_deviceKey);
    if (have != null) return have;
    final id = makeDeviceId(model, random ?? Random.secure());
    await _store.set(_deviceKey, id);
    return id;
  }

  String? get hubFolder => _store.get(_hubKey);

  Future<void> setHubFolder(String path) => _store.set(_hubKey, path);

  /// Null until the user picks a hub, and again after signing out. A hub
  /// folder stored before hub kinds existed counts as a folder hub.
  HubChoice? get hubChoice {
    final folder = hubFolder;
    switch (_store.get(_hubKindKey)) {
      case null:
      case 'folder':
        return folder == null ? null : FolderHub(folder);
      case 'drive':
        final j = _map(_googleKey);
        final id = j['id'];
        final email = j['email'];
        return id is String && id.isNotEmpty && email is String ? DriveHub(accountId: id, email: email) : null;
      default:
        return null;
    }
  }

  /// Null forgets the choice. The folder path stays, so a later switch back
  /// to a folder starts from it.
  Future<void> setHubChoice(HubChoice? choice) async {
    switch (choice) {
      case FolderHub(:final path):
        await _store.set(_hubKey, path);
        await _store.set(_hubKindKey, 'folder');
      case DriveHub(:final accountId, :final email):
        await _store.set(_googleKey, jsonEncode({'id': accountId, 'email': email}));
        await _store.set(_hubKindKey, 'drive');
      case null:
        await _store.set(_hubKindKey, 'none');
    }
  }

  Map<String, dynamic> _map(String key) {
    final s = _store.get(key);
    if (s == null) return {};
    try {
      final j = jsonDecode(s);
      return j is Map<String, dynamic> ? j : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _put(String key, String field, Object? value) {
    final m = _map(key);
    if (value == null) {
      m.remove(field);
    } else {
      m[field] = value;
    }
    return _store.set(key, jsonEncode(m));
  }

  Binding? binding(String recipe) {
    final j = _map(_bindingsKey)[recipe];
    try {
      return j is Map<String, dynamic> ? Binding.fromJson(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setBinding(Binding b) => _put(_bindingsKey, b.recipe, b.toJson());

  Future<void> clearBinding(String recipe) => _put(_bindingsKey, recipe, null);

  Base? base(String hub, String recipe, String unit) {
    final j = _map(_basesKey)['$hub|$recipe|$unit'];
    try {
      return j is Map<String, dynamic> ? Base.fromJson(j) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> setBase(String hub, String recipe, String unit, Base base) => _put(_basesKey, '$hub|$recipe|$unit', base.toJson());

  /// A base kept under another hub id of [backend] whose gen is in [listed],
  /// the newest if there are several. Two devices that open the folder before
  /// folder sync meets each write a hub.json, and only one survives; the gens
  /// still listed show it is the same hub. A base whose gen is not listed is
  /// never returned, so a hub recreated in the same place still has none.
  Base? baseUnderOtherHubId(String backend, String recipe, String unit, Set<String> listed) {
    final prefix = '$backend#';
    final suffix = '|$recipe|$unit';
    Base? best;
    for (final e in _map(_basesKey).entries) {
      final k = e.key;
      if (!k.startsWith(prefix) || !k.endsWith(suffix) || k.length < prefix.length + suffix.length) continue;
      final id = k.substring(prefix.length, k.length - suffix.length);
      if (id.contains('#') || id.contains('|')) continue; // another backend, recipe or unit
      final j = e.value;
      if (j is! Map<String, dynamic>) continue;
      final Base b;
      try {
        b = Base.fromJson(j);
      } catch (_) {
        continue;
      }
      if (listed.contains(b.gen) && (best == null || b.gen.compareTo(best.gen) > 0)) best = b;
    }
    return best;
  }

  DateTime? last(String recipe, String kind) => DateTime.tryParse('${_map(_lastKey)['$recipe|$kind'] ?? ''}');

  Future<void> setLast(String recipe, String kind, DateTime t) => _put(_lastKey, '$recipe|$kind', t.toUtc().toIso8601String());
}
