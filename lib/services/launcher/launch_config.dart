import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Launcher mode's own settings, apart from AppSettings as dual screen keeps
/// its own: whether the mode is on, the emulator of each console, and what
/// the last detection found.
@immutable
class LaunchConfig {
  const LaunchConfig({this.enabled = false, this.home = false, this.defaults = const {}, this.lastDetected});

  final bool enabled;

  /// Android: Retro Toolbox is the home app, as Android last said (HomeRole).
  final bool home;

  /// By catalog console id, which works for a console with no art slug too.
  /// A default names a preset; the variant in use comes from the detection.
  final Map<String, LaunchChoice> defaults;

  /// Null until the first detection. Saved without icons.
  final List<DetectedEmulator>? lastDetected;

  LaunchConfig copyWith({bool? enabled, bool? home, Map<String, LaunchChoice>? defaults, List<DetectedEmulator>? lastDetected}) => LaunchConfig(
        enabled: enabled ?? this.enabled,
        home: home ?? this.home,
        defaults: defaults ?? this.defaults,
        lastDetected: lastDetected ?? this.lastDetected,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'home': home,
        'defaults': {for (final e in defaults.entries) e.key: e.value.toJson()},
        if (lastDetected != null) 'lastDetected': [for (final d in lastDetected!) d.toJson()],
      };

  /// What [j] holds, a bad default or detection left out; anything that is
  /// not a saved config reads as the default one.
  static LaunchConfig fromJson(Object? j) {
    if (j is! Map) return const LaunchConfig();
    final defaults = j['defaults'], detected = j['lastDetected'];
    return LaunchConfig(
      enabled: j['enabled'] == true,
      home: j['home'] == true,
      defaults: {
        if (defaults is Map)
          for (final e in defaults.entries)
            if (e.key is String && LaunchChoice.fromJson(e.value) != null) e.key as String: LaunchChoice.fromJson(e.value)!,
      },
      lastDetected: detected is List
          ? [
              for (final d in detected)
                if (DetectedEmulator.fromJson(d) != null) DetectedEmulator.fromJson(d)!,
            ]
          : null,
    );
  }
}

/// The config under its own SharedPreferences key.
class LaunchConfigStore {
  LaunchConfigStore({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;

  static const key = 'launcher_config_v1';

  final Future<SharedPreferences> Function() _prefs;

  /// The default config when nothing is saved or it cannot be read.
  Future<LaunchConfig> load() async {
    try {
      final raw = (await _prefs()).getString(key);
      return raw == null ? const LaunchConfig() : LaunchConfig.fromJson(jsonDecode(raw));
    } catch (e) {
      debugPrint('Reading the launcher config failed: $e');
      return const LaunchConfig();
    }
  }

  Future<void> save(LaunchConfig config) async {
    try {
      await (await _prefs()).setString(key, jsonEncode(config.toJson()));
    } catch (e) {
      debugPrint('Saving the launcher config failed: $e');
    }
  }
}

class LaunchConfigNotifier extends StateNotifier<LaunchConfig> {
  LaunchConfigNotifier(this._store) : super(const LaunchConfig()) {
    loaded = _store.load().then((saved) {
      if (mounted) state = saved;
    });
  }

  final LaunchConfigStore _store;

  /// Completes once the saved config is in [state]. Every change waits for
  /// it, so a change made early is applied over the saved config, never lost
  /// under it.
  late final Future<void> loaded;

  Future<void> _update(LaunchConfig Function(LaunchConfig c) change) async {
    await loaded;
    if (!mounted) return;
    state = change(state);
    await _store.save(state);
  }

  Future<void> setEnabled(bool enabled) => _update((c) => c.copyWith(enabled: enabled));

  /// [choice] null drops the console's default.
  Future<void> setDefault(String consoleId, LaunchChoice? choice) =>
      _update((c) => c.copyWith(defaults: {
            for (final e in c.defaults.entries)
              if (e.key != consoleId) e.key: e.value,
            if (choice != null) consoleId: choice,
          }));

  /// The wizard's Finish: [picks] over the defaults it did not show, and the
  /// mode on, in one write.
  Future<void> finishSetup(Map<String, LaunchChoice> picks) => _update((c) => c.copyWith(enabled: true, defaults: {...c.defaults, ...picks}));

  Future<void> setDetected(List<DetectedEmulator> detected) => _update((c) => c.copyWith(lastDetected: detected));

  /// What Android says: Retro Toolbox is the home app or not.
  Future<void> setHome(bool home) => _update((c) => c.copyWith(home: home));
}
