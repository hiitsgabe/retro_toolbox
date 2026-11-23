import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';

/// "Always for this game": `<support>/launcher/overrides.json`, gameId to
/// choice. Writes wait [debounce], like favorites, so a burst is one write.
class LaunchOverridesStore {
  LaunchOverridesStore({required Future<Directory> Function() supportDir, this.debounce = const Duration(milliseconds: 300)}) : _supportDir = supportDir;

  final Future<Directory> Function() _supportDir;
  final Duration debounce;
  Timer? _timer;

  Future<File> _file() async => File('${(await _supportDir()).path}/launcher/overrides.json');

  /// Empty when there is no file or it is unreadable; a bad entry is skipped.
  Future<Map<String, LaunchChoice>> load() async {
    try {
      final j = jsonDecode(await (await _file()).readAsString());
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.key is String && LaunchChoice.fromJson(e.value) != null) e.key as String: LaunchChoice.fromJson(e.value)!,
      };
    } catch (_) {
      return {};
    }
  }

  void save(Map<String, LaunchChoice> overrides) {
    _timer?.cancel();
    final json = jsonEncode({for (final e in overrides.entries) e.key: e.value.toJson()});
    _timer = Timer(debounce, () async {
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        await file.writeAsString(json);
      } catch (e) {
        debugPrint('Saving launch overrides failed: $e');
      }
    });
  }
}

class LaunchOverridesNotifier extends StateNotifier<Map<String, LaunchChoice>> {
  LaunchOverridesNotifier(this._store) : super(const {}) {
    loaded = _store.load().then((saved) {
      // A choice made while the file was loading is newer than the file.
      if (mounted) state = {...saved, ...state};
    });
  }

  final LaunchOverridesStore _store;

  /// Completes once the saved overrides are in [state]: a card launch reads
  /// them at once, where Play had its page's build to wait for them.
  late final Future<void> loaded;

  void set(String gameId, LaunchChoice choice) {
    state = {...state, gameId: choice};
    _store.save(state);
  }
}
