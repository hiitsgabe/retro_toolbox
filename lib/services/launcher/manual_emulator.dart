/// An emulator the user added by hand, for an app or executable detection
/// does not know: paired with a preset of the file it opens games like, or
/// with none ([ManualEmulator.generic]: it gets the game file as a viewer
/// would). Pure Dart, like launch_preset.dart.
library;

import 'package:retro_toolbox/services/launcher/launch_preset.dart';

class ManualEmulator {
  const ManualEmulator({required this.variant, required this.label, required this.recipe, this.systems = const [], this.activity});

  /// No recipe: on Android ACTION_VIEW on our provider URI, on desktop the
  /// file's path as the only argument.
  static const generic = 'generic';

  /// The Android package, or the desktop executable's path.
  final String variant;

  /// What the user saw when picking it: the app's label, or the file's name.
  final String label;

  /// A preset id of the file, or [generic].
  final String recipe;

  /// Console art slugs. With a recipe, empty is all of the recipe's; a
  /// generic one has at least one, the consoles the user ticked.
  final List<String> systems;

  /// Android generic only: the activity viewActivity found when it was added.
  final String? activity;

  bool get isGeneric => recipe == generic;

  /// The preset id it goes by. Derived from the variant, so adding the same
  /// app again replaces it, and a default or override naming it outlives a
  /// restart.
  String get id => manualId(variant);

  Map<String, Object?> toJson() => {'variant': variant, 'label': label, 'recipe': recipe, 'systems': systems, if (activity != null) 'activity': activity};

  /// Null for anything that is not a saved manual emulator, so one bad entry
  /// never costs the others.
  static ManualEmulator? fromJson(Object? j) {
    if (j is! Map) return null;
    final variant = j['variant'], label = j['label'], recipe = j['recipe'], systems = j['systems'], activity = j['activity'];
    if (variant is! String || variant.isEmpty || label is! String || recipe is! String || recipe.isEmpty) return null;
    if (systems != null && systems is! List) return null;
    if (activity != null && activity is! String) return null;
    final slugs = [
      if (systems is List)
        for (final s in systems)
          if (s is String) s,
    ];
    if (recipe == generic && slugs.isEmpty) return null;
    return ManualEmulator(variant: variant, label: label, recipe: recipe, systems: slugs, activity: activity as String?);
  }
}

/// `manual-` and [variant] lowercased, every character outside
/// `[a-z0-9._-]` made a `-`: a preset id is a plain word wherever it goes.
String manualId(String variant) => 'manual-${variant.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]'), '-')}';

/// [file]'s presets, then one per entry of [manual] built for [os], so
/// everything that reads presets sees a manual emulator as any other. A
/// recipe entry is its preset under the entry's id and label, with the
/// picked package or a find rule on the picked executable; a generic one
/// opens the file as a viewer does. An entry whose recipe left the file, or
/// has no block for [os], is left out: it stays saved and comes back with
/// the file. [extensions], by console art slug, is what a generic entry
/// opens; a slug not in it opens any file.
List<LaunchPreset> presetsWithManual(List<LaunchPreset> file, List<ManualEmulator> manual, {required String os, Map<String, List<String>> extensions = const {}}) {
  final byId = {for (final p in file) p.id: p};
  final out = [...file];
  for (final m in manual) {
    final preset = m.isGeneric ? _generic(m, os, extensions) : _recipe(m, byId[m.recipe], os);
    if (preset != null) out.add(preset);
  }
  return out;
}

LaunchPreset? _recipe(ManualEmulator m, LaunchPreset? recipe, String os) {
  if (recipe == null) return null;
  final systems = m.systems.isEmpty
      ? recipe.systems
      : {
          for (final e in recipe.systems.entries)
            if (m.systems.contains(e.key)) e.key: e.value,
        };
  if (os != 'android') {
    final desktop = recipe.desktopFor(os);
    return desktop == null ? null : _desktop(m, os, verified: recipe.verified, systems: systems, args: desktop.args);
  }
  final a = recipe.android;
  if (a == null) return null;
  return LaunchPreset(
    id: m.id,
    name: m.label,
    verified: recipe.verified,
    systems: systems,
    android: AndroidBlock(
      packages: [m.variant],
      activity: a.activity,
      action: a.action,
      categories: a.categories,
      mimeType: a.mimeType,
      flags: a.flags,
      rom: a.rom,
      extras: a.extras,
    ),
  );
}

LaunchPreset? _generic(ManualEmulator m, String os, Map<String, List<String>> extensions) {
  final systems = {for (final s in m.systems) s: PresetSystem(slug: s, extensions: extensions[s] ?? const [])};
  if (os != 'android') return _desktop(m, os, verified: false, systems: systems, args: const ['{rom}']);
  final activity = m.activity;
  if (activity == null) return null;
  return LaunchPreset(
    id: m.id,
    name: m.label,
    systems: systems,
    // Our own FileProvider with a read grant reaches the file wherever the
    // library is, with no folder for the user to set up in the app. A cue or
    // an m3u goes the same way: saf would need a folder grant a viewer has no
    // setting for, so the app gets that one file and not the bins beside it.
    android: AndroidBlock(
      packages: [m.variant],
      activity: activity,
      action: 'android.intent.action.VIEW',
      rom: const RomSpec(mode: RomMode.provider, multiFileMode: RomMode.provider),
    ),
  );
}

/// The block finds the picked executable by its path, so the emulator is
/// detected exactly while that file is there, with no rule of its own in
/// the detector.
LaunchPreset? _desktop(ManualEmulator m, String os, {required bool verified, required Map<String, PresetSystem> systems, required List<String> args}) {
  final block = DesktopBlock(find: [FindRule(type: FindType.staticPaths, paths: [m.variant])], args: args);
  return switch (os) {
    'linux' => LaunchPreset(id: m.id, name: m.label, verified: verified, systems: systems, linux: block),
    'windows' => LaunchPreset(id: m.id, name: m.label, verified: verified, systems: systems, windows: block),
    'macos' => LaunchPreset(id: m.id, name: m.label, verified: verified, systems: systems, macos: block),
    _ => null,
  };
}
