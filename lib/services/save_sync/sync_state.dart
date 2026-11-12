import 'dart:convert';
import 'dart:math';

import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SyncStore {
  String? get(String key);
  Future<void> set(String key, String value);
}

class PrefsStore implements SyncStore {
  PrefsStore(this.prefs);

  final SharedPreferences prefs;

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

/// What this device remembers: its id, the hub folder, recipe bindings, the
/// base of every unit per hub, and when each game was last pushed or pulled.
class SyncState {
  SyncState(this._store);

  final SyncStore _store;

  static const _deviceKey = 'save_sync_device_id';
  static const _hubKey = 'save_sync_hub_folder';
  static const _bindingsKey = 'save_sync_bindings';
  static const _basesKey = 'save_sync_bases';
  static const _lastKey = 'save_sync_last';

  Future<String> deviceId(String model, {Random? random}) async {
    final have = _store.get(_deviceKey);
    if (have != null) return have;
    final id = makeDeviceId(model, random ?? Random.secure());
    await _store.set(_deviceKey, id);
    return id;
  }

  String? get hubFolder => _store.get(_hubKey);

  Future<void> setHubFolder(String path) => _store.set(_hubKey, path);

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

  DateTime? last(String recipe, String kind) => DateTime.tryParse('${_map(_lastKey)['$recipe|$kind'] ?? ''}');

  Future<void> setLast(String recipe, String kind, DateTime t) => _put(_lastKey, '$recipe|$kind', t.toUtc().toIso8601String());
}
