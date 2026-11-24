import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Launcher mode's own settings, apart from AppSettings as dual screen keeps
/// its own: whether the mode is on, the emulator of each console, and what
/// the last detection found.
@immutable
class LaunchConfig {
  const LaunchConfig({this.enabled = false, this.home = false, this.defaults = const {}, this.lastDetected, this.manual = const [], this.noFolders = const {}});

  final bool enabled;

  /// Android: Retro Toolbox is the home app, as Android last said (HomeRole).
  final bool home;

  /// By catalog console id, which works for a console with no art slug too.
  /// A default names a preset; the variant in use comes from the detection.
  final Map<String, LaunchChoice> defaults;

  /// Null until the first detection. Saved without icons.
  final List<DetectedEmulator>? lastDetected;

  /// The emulators the user added by hand, each a preset of its own
  /// (presetsWithManual).
  final List<ManualEmulator> manual;

  /// Catalog console ids whose folders are never a game: on Switch a folder
  /// holds updates or DLC, not one more game.
  final Set<String> noFolders;

  /// Whether a folder in [consoleId]'s library can be a game.
  bool folderGames(String consoleId) => !noFolders.contains(consoleId);

  LaunchConfig copyWith({
    bool? enabled,
    bool? home,
    Map<String, LaunchChoice>? defaults,
    List<DetectedEmulator>? lastDetected,
    List<ManualEmulator>? manual,
    Set<String>? noFolders,
  }) =>
      LaunchConfig(
        enabled: enabled ?? this.enabled,
        home: home ?? this.home,
        defaults: defaults ?? this.defaults,
        lastDetected: lastDetected ?? this.lastDetected,
        manual: manual ?? this.manual,
        noFolders: noFolders ?? this.noFolders,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'home': home,
        'defaults': {for (final e in defaults.entries) e.key: e.value.toJson()},
        if (lastDetected != null) 'lastDetected': [for (final d in lastDetected!) d.toJson()],
        'manual': [for (final m in manual) m.toJson()],
        if (noFolders.isNotEmpty) 'noFolders': noFolders.toList()..sort(),
      };

  /// What [j] holds, a bad default or detection left out; anything that is
  /// not a saved config reads as the default one.
  static LaunchConfig fromJson(Object? j) {
    if (j is! Map) return const LaunchConfig();
    final defaults = j['defaults'], detected = j['lastDetected'], manual = j['manual'], noFolders = j['noFolders'];
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
      manual: [
        if (manual is List)
          for (final m in manual)
            if (ManualEmulator.fromJson(m) != null) ManualEmulator.fromJson(m)!,
      ],
      noFolders: {
        if (noFolders is List)
          for (final id in noFolders)
            if (id is String) id,
      },
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

  /// Whether a folder in [consoleId]'s library can be a game.
  Future<void> setFolderGames(String consoleId, bool on) => _update((c) => c.copyWith(noFolders: {
        for (final id in c.noFolders)
          if (id != consoleId) id,
        if (!on) consoleId,
      }));

  /// [m] after the others, or in the place of the one with its id: adding
  /// the same app again changes how it opens, and never lists it twice.
  Future<void> addManual(ManualEmulator m) => _update((c) => c.copyWith(manual: [
        for (final e in c.manual) e.id == m.id ? m : e,
        if (!c.manual.any((e) => e.id == m.id)) m,
      ]));

  /// Drops the manual emulator [id], every console default that names it and
  /// its saved detection, so no default points at nothing. The per-game
  /// overrides have their own file: removeManualEmulatorProvider drops
  /// those.
  Future<void> removeManual(String id) => _update((c) => c.copyWith(
        manual: [for (final e in c.manual) if (e.id != id) e],
        defaults: {
          for (final e in c.defaults.entries)
            if (e.value.presetId != id) e.key: e.value,
        },
        lastDetected: c.lastDetected == null ? null : [for (final d in c.lastDetected!) if (d.presetId != id) d],
      ));
}
