import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// Where the addon list and each addon's catalog live.
class AddonStore {
  /// The `shared_preferences` key holding the serialized ordered list.
  static const String prefsKey = 'addons';

  final SharedPreferences _prefs;
  final Directory _root;

  AddonStore(this._prefs, this._root);

  static Future<AddonStore> open() async => AddonStore(
        await SharedPreferences.getInstance(),
        await getApplicationSupportDirectory(),
      );

  /// The installed list, in priority order.
  ///
  /// A missing key returns the migration list (the built-in alone) without
  /// writing: reading must not have a side effect. A saved empty list is a
  /// legitimate state, distinct from a missing key.
  List<Addon> load() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null) return [_migratedBuiltin()];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [_migratedBuiltin()];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic> && item['id'] is String) Addon.fromJson(item),
      ];
    } catch (e) {
      debugPrint('Unreadable addon list, falling back to migration: $e');
      return [_migratedBuiltin()];
    }
  }

  Future<void> save(List<Addon> list) async {
    await _prefs.setString(prefsKey, jsonEncode([for (final addon in list) addon.toJson()]));
  }

  /// The addon representing the pre-slice-4 `consoles.json`.
  Addon _migratedBuiltin() {
    String? url;
    try {
      final raw = _prefs.getString(SettingsService.settingsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        final value = decoded is Map ? decoded['catalogSourceUrl'] : null;
        if (value is String && value.isNotEmpty) url = value;
      }
    } catch (e) {
      debugPrint('Unreadable catalogSourceUrl during addon migration: $e');
    }
    return Addon(id: kBuiltinAddonId, name: 'Built-in catalog', url: url);
  }

  /// Where each addon's catalog lives.
  File catalogFile(String addonId) => addonId == kBuiltinAddonId
      ? File(path.join(_root.path, 'config', 'consoles.json'))
      : File(path.join(_root.path, 'config', 'addons', '$addonId.json'));

  Future<String?> readCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> writeCatalog(String addonId, String jsonStr) async {
    final file = catalogFile(addonId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonStr);
  }

  Future<void> deleteCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (await file.exists()) await file.delete();
  }
}
