/// Parses and validates a launch preset file. Pure Dart, like
/// launch_preset.dart: the strict check in tool/launch_presets_check.dart
/// runs it under plain `dart run`.
library;

import 'dart:convert';

import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/utils/console_slugs.dart';

/// The newest `schema` this app reads. A file with a newer one is refused
/// whole, and the app keeps the copy it had.
const supportedPresetSchema = 1;

/// Placeholders a template may use.
const presetPlaceholders = {'rom', 'rom.path', 'rom.uri', 'retroarch.core', 'retroarch.config'};

final _placeholder = RegExp(r'\{([^{}]*)\}');

class PresetFileCheck {
  const PresetFileCheck({required this.file, required this.problems});

  /// The file with every invalid preset dropped; null when the file as a
  /// whole is refused (not JSON, no schema or version, a newer schema).
  final LaunchPresetFile? file;

  /// Every problem found. The app ignores them once the bad presets are
  /// dropped; the tool and the committed-file test fail on any.
  final List<String> problems;

  /// What the app may use: a file with at least one valid preset.
  bool get usable => file != null && file!.presets.isNotEmpty;
}

PresetFileCheck checkPresetFile(String body) {
  final Object? root;
  try {
    root = jsonDecode(body);
  } on FormatException catch (e) {
    return PresetFileCheck(file: null, problems: ['not JSON: ${e.message}']);
  }
  if (root is! Map) return const PresetFileCheck(file: null, problems: ['the file is not a JSON object']);
  final schema = root['schema'];
  final version = root['version'];
  final list = root['presets'];
  if (schema is! int) return const PresetFileCheck(file: null, problems: ['schema is required and must be an integer']);
  if (schema > supportedPresetSchema) {
    return PresetFileCheck(file: null, problems: ['schema $schema is newer than $supportedPresetSchema, the newest this app reads']);
  }
  if (version is! int) return const PresetFileCheck(file: null, problems: ['version is required and must be an integer']);
  if (list is! List) return const PresetFileCheck(file: null, problems: ['presets is required and must be a list']);

  final problems = <String>[];
  final kept = <LaunchPreset>[];
  final ids = <String>{};
  final packageOwner = <String, String>{};
  for (var i = 0; i < list.length; i++) {
    final raw = list[i];
    final label = raw is Map && raw['id'] is String ? raw['id'] as String : 'presets[$i]';
    if (raw is! Map) {
      problems.add('$label: not an object');
      continue;
    }
    final LaunchPreset preset;
    try {
      preset = LaunchPreset.fromJson(raw.cast<String, Object?>());
    } on FormatException catch (e) {
      problems.add('$label: ${e.message}');
      continue;
    }
    final own = _presetProblems(preset, ids, packageOwner);
    problems.addAll([for (final p in own) '$label: $p']);
    if (own.isNotEmpty) continue;
    ids.add(preset.id);
    for (final pkg in preset.android?.packages ?? const <String>[]) {
      packageOwner[pkg] = preset.id;
    }
    kept.add(preset);
  }
  return PresetFileCheck(file: LaunchPresetFile(schema: schema, version: version, presets: kept), problems: problems);
}

/// What is wrong with [p], given the ids and Android packages the presets
/// before it already claimed.
List<String> _presetProblems(LaunchPreset p, Set<String> ids, Map<String, String> packageOwner) {
  final out = <String>[];
  if (ids.contains(p.id)) out.add('id "${p.id}" is used by an earlier preset');
  for (final s in p.systems.values) {
    if (!knownConsoleSlugs.contains(s.slug)) out.add('system "${s.slug}" is not a known console slug');
    // Empty means any file, for a generic manual emulator; a preset of the
    // file always says what it opens.
    if (s.extensions.isEmpty) out.add('systems.${s.slug} needs at least one extension');
    for (final e in s.extensions) {
      if (e != e.toLowerCase() || e.startsWith('.')) out.add('systems.${s.slug} extension "$e" must be lowercase with no dot');
    }
  }
  final android = p.android;
  if (android != null) {
    for (final pkg in android.packages) {
      final owner = packageOwner[pkg];
      if (owner != null) out.add('package $pkg is already claimed by $owner');
    }
    if (android.activity.startsWith('.')) out.add('android.activity must be fully qualified, not ${android.activity}');
    final rom = android.rom;
    final usesPath = rom.mode == RomMode.path || rom.scopedMode == RomMode.path || rom.multiFileMode == RomMode.path;
    if (usesPath && rom.extra == null) out.add('android.rom uses path mode, which needs rom.extra: a path never goes in the data');
  }
  for (final t in p.templates) {
    for (final m in _placeholder.allMatches(t)) {
      if (!presetPlaceholders.contains(m[1])) out.add('unknown placeholder {${m[1]}} in "$t"');
    }
  }
  if (p.usesRetroarchCore) {
    for (final s in p.systems.values) {
      if (s.cores.isEmpty) out.add('systems.${s.slug} needs cores: the preset uses {retroarch.core}');
    }
  }
  return out;
}
