/// One emulator's launch recipe, as `launch_presets/launch_presets.json`
/// describes it. Pure Dart: `tool/launch_presets_check.dart` parses with it
/// under plain `dart run`, so nothing here may import Flutter.
library;

/// How a ROM is handed to an Android emulator.
enum RomMode {
  /// An absolute path, only ever in a string extra.
  path,

  /// A URI from our own FileProvider, with a read grant.
  provider,

  /// An external-storage document URI, with no grant flags.
  saf,
}

enum ExtraType { string, bool, int, long, stringArray }

enum LaunchFlag { clearTask, clearTop, noHistory }

enum FindType { path, staticPaths, flatpak, app, registry }

/// What one preset accepts for one console art slug.
class PresetSystem {
  const PresetSystem({required this.slug, required this.extensions, this.cores = const []});

  final String slug;

  /// Lowercase, no dot.
  final List<String> extensions;

  /// Libretro core base names, the first being the default. RetroArch only.
  final List<String> cores;
}

class RomSpec {
  const RomSpec({required this.mode, this.scopedMode, this.multiFileMode, this.extra, this.clipDataDiscs = false});

  final RomMode mode;

  /// Used instead of [mode] when the installed package cannot open raw paths.
  final RomMode? scopedMode;

  /// The mode for an m3u, cue or gdi launch.
  final RomMode? multiFileMode;

  /// The string extra that carries the ROM; null puts a URI in the data.
  final String? extra;

  /// An m3u goes out as one ClipData URI per disc (Dolphin).
  final bool clipDataDiscs;
}

class PresetExtra {
  const PresetExtra({required this.key, required this.type, required this.value});

  final String key;
  final ExtraType type;

  /// A String template for string, bool for bool, int for int and long,
  /// `List<String>` of templates for stringArray.
  final Object value;

  /// The template strings in [value], for the placeholder check.
  List<String> get templates => switch (value) {
        final String s => [s],
        final List<String> l => l,
        _ => const [],
      };
}

class AndroidBlock {
  const AndroidBlock({
    required this.packages,
    required this.activity,
    required this.action,
    this.categories = const [],
    this.mimeType,
    this.flags = const [],
    required this.rom,
    this.extras = const [],
  });

  /// Install variants, tried in order.
  final List<String> packages;

  /// Fully qualified class name, the same in every variant.
  final String activity;
  final String action;
  final List<String> categories;
  final String? mimeType;
  final List<LaunchFlag> flags;
  final RomSpec rom;
  final List<PresetExtra> extras;
}

class FindRule {
  const FindRule({required this.type, this.names = const [], this.paths = const [], this.id, this.key, this.value, this.file});

  final FindType type;

  /// `path`: executable names for which/where.
  final List<String> names;

  /// `static` and `app`: candidate paths.
  final List<String> paths;

  /// `flatpak`: the application id.
  final String? id;

  /// `registry`: the key and value to read, and an optional file name joined
  /// to the value when it names a folder.
  final String? key;
  final String? value;
  final String? file;
}

class DesktopBlock {
  const DesktopBlock({required this.find, required this.args});

  final List<FindRule> find;

  /// Argument templates, `{rom}` being the absolute path.
  final List<String> args;
}

class LaunchPreset {
  const LaunchPreset({
    required this.id,
    required this.name,
    this.verified = false,
    required this.systems,
    this.android,
    this.linux,
    this.windows,
    this.macos,
  });

  final String id;
  final String name;

  /// True only once the device checklist passed for this preset.
  final bool verified;

  /// Keyed by console art slug.
  final Map<String, PresetSystem> systems;
  final AndroidBlock? android;
  final DesktopBlock? linux;
  final DesktopBlock? windows;
  final DesktopBlock? macos;

  /// The block for `Platform.operatingSystem`, or null.
  DesktopBlock? desktopFor(String os) => switch (os) {
        'linux' => linux,
        'windows' => windows,
        'macos' => macos,
        _ => null,
      };

  /// Every template string the preset renders, Android and desktop.
  Iterable<String> get templates sync* {
    for (final e in android?.extras ?? const <PresetExtra>[]) {
      yield* e.templates;
    }
    for (final d in [linux, windows, macos]) {
      if (d != null) yield* d.args;
    }
  }

  bool get usesRetroarchCore => templates.any((t) => t.contains('{retroarch.core}'));

  /// [j] as a preset. Unknown fields are ignored, so a newer file still loads
  /// here. Throws [FormatException] naming the first field that is missing or
  /// of the wrong type.
  factory LaunchPreset.fromJson(Map<String, Object?> j) {
    final systems = _map(j, 'systems');
    return LaunchPreset(
      id: _string(j, 'id'),
      name: _string(j, 'name'),
      verified: _optBool(j, 'verified') ?? false,
      systems: {
        for (final e in systems.entries) e.key: _system(e.key, e.value),
      },
      android: j['android'] == null ? null : _android(_map(j, 'android')),
      linux: j['linux'] == null ? null : _desktop('linux', _map(j, 'linux')),
      windows: j['windows'] == null ? null : _desktop('windows', _map(j, 'windows')),
      macos: j['macos'] == null ? null : _desktop('macos', _map(j, 'macos')),
    );
  }
}

/// The whole preset file.
class LaunchPresetFile {
  const LaunchPresetFile({required this.schema, required this.version, required this.presets});

  static const empty = LaunchPresetFile(schema: 1, version: 0, presets: []);

  /// The format version.
  final int schema;

  /// The content version; the higher of seed and cache wins.
  final int version;
  final List<LaunchPreset> presets;
}

PresetSystem _system(String slug, Object? raw) {
  if (raw is! Map) throw FormatException('systems.$slug is not an object');
  final j = raw.cast<String, Object?>();
  return PresetSystem(slug: slug, extensions: _strings(j, 'extensions', where: 'systems.$slug'), cores: _optStrings(j, 'cores', where: 'systems.$slug'));
}

AndroidBlock _android(Map<String, Object?> j) {
  final rom = _map(j, 'rom', where: 'android');
  return AndroidBlock(
    packages: _strings(j, 'packages', where: 'android'),
    activity: _string(j, 'activity', where: 'android'),
    action: _string(j, 'action', where: 'android'),
    categories: _optStrings(j, 'categories', where: 'android'),
    mimeType: _optString(j, 'mimeType', where: 'android'),
    flags: [for (final f in _optStrings(j, 'flags', where: 'android')) _enum(LaunchFlag.values, f, 'android.flags')],
    rom: RomSpec(
      mode: _mode(rom, 'mode')!,
      scopedMode: _mode(rom, 'scopedMode'),
      multiFileMode: _mode(rom, 'multiFileMode'),
      extra: _optString(rom, 'extra', where: 'android.rom'),
      clipDataDiscs: _optBool(rom, 'clipDataDiscs', where: 'android.rom') ?? false,
    ),
    extras: [for (final e in _optList(j, 'extras', where: 'android')) _extra(e)],
  );
}

RomMode? _mode(Map<String, Object?> rom, String field) {
  final raw = rom[field];
  if (raw == null && field != 'mode') return null;
  if (raw is! String) throw FormatException('android.rom.$field is required and must be path, provider or saf');
  return _enum(RomMode.values, raw, 'android.rom.$field');
}

PresetExtra _extra(Object? raw) {
  if (raw is! Map) throw const FormatException('android.extras holds a non-object');
  final j = raw.cast<String, Object?>();
  final key = _string(j, 'key', where: 'android.extras');
  final type = _enum(ExtraType.values, _string(j, 'type', where: 'android.extras.$key'), 'android.extras.$key.type');
  final value = j['value'];
  final ok = switch (type) {
    ExtraType.string => value is String,
    ExtraType.bool => value is bool,
    ExtraType.int || ExtraType.long => value is int,
    ExtraType.stringArray => value is List && value.every((e) => e is String),
  };
  if (!ok) throw FormatException('android.extras.$key.value does not match type ${type.name}');
  return PresetExtra(key: key, type: type, value: value is List ? value.cast<String>().toList() : value!);
}

DesktopBlock _desktop(String os, Map<String, Object?> j) => DesktopBlock(
      find: [for (final r in _optList(j, 'find', where: os)) _find(os, r)],
      args: _strings(j, 'args', where: os),
    );

FindRule _find(String os, Object? raw) {
  if (raw is! Map) throw FormatException('$os.find holds a non-object');
  final j = raw.cast<String, Object?>();
  final where = '$os.find';
  return switch (_string(j, 'type', where: where)) {
    'path' => FindRule(type: FindType.path, names: _strings(j, 'names', where: where)),
    'static' => FindRule(type: FindType.staticPaths, paths: _strings(j, 'paths', where: where)),
    'flatpak' => FindRule(type: FindType.flatpak, id: _string(j, 'id', where: where)),
    'app' => FindRule(type: FindType.app, paths: _strings(j, 'paths', where: where)),
    'registry' => FindRule(
        type: FindType.registry,
        key: _string(j, 'key', where: where),
        value: _string(j, 'value', where: where),
        file: _optString(j, 'file', where: where),
      ),
    final other => throw FormatException('$where.type "$other" is not path, static, flatpak, app or registry'),
  };
}

T _enum<T extends Enum>(List<T> values, String name, String where) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('$where "$name" is not one of ${values.map((v) => v.name).join(', ')}');
}

String _at(String? where, String field) => where == null ? field : '$where.$field';

String _string(Map<String, Object?> j, String field, {String? where}) {
  final v = j[field];
  if (v is! String || v.isEmpty) throw FormatException('${_at(where, field)} is required and must be a non-empty string');
  return v;
}

String? _optString(Map<String, Object?> j, String field, {String? where}) {
  final v = j[field];
  if (v == null) return null;
  if (v is! String) throw FormatException('${_at(where, field)} must be a string');
  return v;
}

bool? _optBool(Map<String, Object?> j, String field, {String? where}) {
  final v = j[field];
  if (v == null) return null;
  if (v is! bool) throw FormatException('${_at(where, field)} must be true or false');
  return v;
}

Map<String, Object?> _map(Map<String, Object?> j, String field, {String? where}) {
  final v = j[field];
  if (v is! Map) throw FormatException('${_at(where, field)} is required and must be an object');
  return v.cast<String, Object?>();
}

List<Object?> _optList(Map<String, Object?> j, String field, {String? where}) {
  final v = j[field];
  if (v == null) return const [];
  if (v is! List) throw FormatException('${_at(where, field)} must be a list');
  return v;
}

List<String> _optStrings(Map<String, Object?> j, String field, {String? where}) {
  final v = _optList(j, field, where: where);
  if (!v.every((e) => e is String)) throw FormatException('${_at(where, field)} must be a list of strings');
  return v.cast<String>().toList();
}

List<String> _strings(Map<String, Object?> j, String field, {String? where}) {
  if (j[field] == null) throw FormatException('${_at(where, field)} is required');
  return _optStrings(j, field, where: where);
}
