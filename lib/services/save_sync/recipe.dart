import 'package:retro_toolbox/services/save_sync/path_guard.dart';

enum RecipeStatus { verified, fromCode, draft }

enum UnitKind { folder, file, all }

enum Area { androidData, internal }

enum VersionRule { receiverAtLeastSave, sameBuild }

/// Where the device keeps things. Tests point these at temp folders.
class DevicePaths {
  const DevicePaths({this.sdcard = '/storage/emulated/0', this.data = '/data/data'});

  final String sdcard;
  final String data;

  String area(Area a, String package) => a == Area.androidData ? '$sdcard/Android/data/$package' : '$data/$package';

  String get saveSync => '$sdcard/RetroToolbox/SaveSync';
}

class RecipeLocation {
  const RecipeLocation(this.area, this.root);

  final Area area;
  final String root;
}

sealed class BeforeRestoreStep {
  const BeforeRestoreStep();
}

/// Move these paths (relative to the location root), when present, into the
/// pull's history entry.
class MoveAside extends BeforeRestoreStep {
  const MoveAside(this.paths);

  final List<String> paths;
}

/// Move [file] aside only when its first .NET BinaryWriter string equals [value].
class MoveAsideIfFirstStringIs extends BeforeRestoreStep {
  const MoveAsideIfFirstStringIs(this.value, this.file);

  final String value;
  final String file;
}

class SaveCheck {
  const SaveCheck({required this.file, this.xmlEndsWith, this.binaryFormatterEnvelope = false});

  final String file;
  final String? xmlEndsWith;
  final bool binaryFormatterEnvelope;
}

class VersionSource {
  const VersionSource({this.file, this.xmlTag, this.parts, this.fromPackage = false, required this.rule});

  final String? file;
  final String? xmlTag;
  final int? parts;
  final bool fromPackage;
  final VersionRule rule;
}

class NativeCloud {
  const NativeCloud(this.provider, this.defaultMode);

  final String provider;
  final String defaultMode;
}

class RecipeError implements Exception {
  RecipeError(this.message);

  final String message;

  @override
  String toString() => 'Recipe error: $message';
}

/// The recipe needs a newer Retro Toolbox: shown, never run.
class RecipeTooNew implements Exception {
  RecipeTooNew(this.schema);

  final int schema;

  @override
  String toString() => 'Recipe schema $schema needs a newer Retro Toolbox';
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.status,
    required this.packages,
    required this.locations,
    required this.unit,
    required this.include,
    this.deviceLocal = const [],
    this.inProgress = const [],
    this.beforeRestore = const [],
    this.checks = const [],
    this.version,
    this.nativeCloud,
    this.raw = const {},
  });

  /// Schema 2 added one globbed segment in a location root, for apps that
  /// bury their saves under a directory named per install.
  static const supportedSchema = 2;

  /// The JSON this recipe was parsed from, published as-is to the hub.
  final Map<String, dynamic> raw;

  final String id;
  final String name;
  final RecipeStatus status;
  final List<String> packages;
  final List<RecipeLocation> locations;
  final UnitKind unit;
  final List<String> include;
  final List<String> deviceLocal;
  final List<String> inProgress;
  final List<BeforeRestoreStep> beforeRestore;
  final List<SaveCheck> checks;
  final VersionSource? version;
  final NativeCloud? nativeCloud;

  static const _fields = {
    'schema', 'id', 'name', 'status', 'packages', 'locations', 'unit', 'include', //
    'deviceLocal', 'inProgress', 'beforeRestore', 'checks', 'version', 'nativeCloud',
  };
  static final _idRe = RegExp(r'^[a-z0-9][a-z0-9-]{1,63}$');
  static final _packageRe = RegExp(r'^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$');
  static final _placeholderRe = RegExp(r'\{([a-z]+)\}');

  static Recipe parse(Map<String, dynamic> j) {
    final schema = j['schema'];
    if (schema is! int) throw RecipeError('schema must be a number');
    if (schema > supportedSchema) throw RecipeTooNew(schema);
    final unknown = j.keys.where((k) => !_fields.contains(k)).toList();
    if (unknown.isNotEmpty) throw RecipeError('unknown fields: ${unknown.join(', ')}');

    final id = _string(j, 'id');
    if (!_idRe.hasMatch(id)) throw RecipeError('id "$id" must match ${_idRe.pattern}');
    final name = _string(j, 'name');
    final status = _enum(RecipeStatus.values, _string(j, 'status'), 'status');
    final unit = _enum(UnitKind.values, _string(j, 'unit'), 'unit');

    final packages = _strings(j, 'packages', required: true);
    for (final pkg in packages) {
      if (!_packageRe.hasMatch(pkg)) throw RecipeError('package "$pkg" is not a package name');
    }

    final locs = j['locations'];
    if (locs is! List || locs.isEmpty) throw RecipeError('locations must be a non-empty list');
    final locations = [
      for (final l in locs)
        if (l is Map<String, dynamic> && l.keys.toSet().difference({'area', 'root'}).isEmpty)
          RecipeLocation(_enum(Area.values, _string(l, 'area'), 'area'), _relative(_string(l, 'root'), 'root', schema: schema))
        else
          throw RecipeError('each location is {area, root}'),
    ];

    List<String> patterns(String field, {bool required = false}) {
      final list = _strings(j, field, required: required);
      for (final s in list) {
        _pattern(s, unit, field);
      }
      return list;
    }

    final include = patterns('include', required: true);
    final deviceLocal = patterns('deviceLocal');
    final inProgress = patterns('inProgress');
    if (unit == UnitKind.file && [...include, ...deviceLocal, ...inProgress].any((s) => s.contains('/'))) {
      throw RecipeError('unit file: patterns must name files directly under root');
    }

    final br = j['beforeRestore'];
    if (br != null && br is! List) throw RecipeError('beforeRestore must be a list');
    final beforeRestore = <BeforeRestoreStep>[];
    for (final s in (br as List?) ?? const []) {
      if (s is Map<String, dynamic> && s.keys.toSet().difference({'moveAside'}).isEmpty && s['moveAside'] is List) {
        final paths = _strings(s, 'moveAside', required: true);
        for (final path in paths) {
          _pattern(path, unit, 'beforeRestore');
        }
        beforeRestore.add(MoveAside(paths));
      } else if (s is Map<String, dynamic> && s.keys.toSet().difference({'moveAsideIfFirstStringIs', 'file'}).isEmpty) {
        final file = _string(s, 'file');
        _pattern(file, unit, 'beforeRestore');
        beforeRestore.add(MoveAsideIfFirstStringIs(_string(s, 'moveAsideIfFirstStringIs'), file));
      } else {
        throw RecipeError('beforeRestore steps are {moveAside} or {moveAsideIfFirstStringIs, file}');
      }
    }

    final ch = j['checks'];
    if (ch != null && ch is! List) throw RecipeError('checks must be a list');
    final checks = <SaveCheck>[];
    for (final c in (ch as List?) ?? const []) {
      if (c is! Map<String, dynamic>) throw RecipeError('each check is an object');
      final file = _string(c, 'file');
      _pattern(file, unit, 'checks');
      if (c.keys.toSet().difference({'file', 'xmlEndsWith'}).isEmpty && c['xmlEndsWith'] is String) {
        checks.add(SaveCheck(file: file, xmlEndsWith: c['xmlEndsWith'] as String));
      } else if (c.keys.toSet().difference({'file', 'binaryFormatterEnvelope'}).isEmpty && c['binaryFormatterEnvelope'] == true) {
        checks.add(SaveCheck(file: file, binaryFormatterEnvelope: true));
      } else {
        throw RecipeError('checks are {file, xmlEndsWith} or {file, binaryFormatterEnvelope: true}');
      }
    }

    VersionSource? version;
    final v = j['version'];
    if (v != null) {
      if (v is! Map<String, dynamic>) throw RecipeError('version must be an object');
      final rule = _enum(VersionRule.values, _string(v, 'rule'), 'version.rule');
      if (v['from'] == 'package' && v.keys.toSet().difference({'from', 'rule'}).isEmpty) {
        version = VersionSource(fromPackage: true, rule: rule);
      } else if (v.keys.toSet().difference({'file', 'xmlTag', 'parts', 'rule'}).isEmpty && v['parts'] is int?) {
        final file = _string(v, 'file');
        _pattern(file, unit, 'version.file');
        version = VersionSource(file: file, xmlTag: _string(v, 'xmlTag'), parts: v['parts'] as int?, rule: rule);
      } else {
        throw RecipeError('version is {from: "package", rule} or {file, xmlTag, parts, rule}');
      }
    }

    NativeCloud? nativeCloud;
    final n = j['nativeCloud'];
    if (n != null) {
      if (n is! Map<String, dynamic> || n.keys.toSet().difference({'provider', 'defaultMode'}).isNotEmpty) {
        throw RecipeError('nativeCloud is {provider, defaultMode}');
      }
      final mode = _string(n, 'defaultMode');
      if (mode != 'backup' && mode != 'sync') throw RecipeError('nativeCloud.defaultMode is backup or sync');
      nativeCloud = NativeCloud(_string(n, 'provider'), mode);
    }

    return Recipe(
      id: id,
      name: name,
      status: status,
      packages: packages,
      locations: locations,
      unit: unit,
      include: include,
      deviceLocal: deviceLocal,
      inProgress: inProgress,
      beforeRestore: beforeRestore,
      checks: checks,
      version: version,
      nativeCloud: nativeCloud,
      raw: Map<String, dynamic>.unmodifiable(j),
    );
  }

  static String _string(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v is! String || v.isEmpty) throw RecipeError('$key must be a non-empty string');
    return v;
  }

  static List<String> _strings(Map<String, dynamic> j, String key, {bool required = false}) {
    final v = j[key];
    if (v == null && !required) return const [];
    if (v is! List || (required && v.isEmpty) || v.any((e) => e is! String || e.isEmpty)) {
      throw RecipeError('$key must be a${required ? ' non-empty' : ''} list of strings');
    }
    return v.cast<String>();
  }

  static T _enum<T extends Enum>(List<T> values, String name, String field) =>
      values.firstWhere((e) => e.name == name, orElse: () => throw RecipeError('$field "$name" is not one of ${values.map((e) => e.name).join(', ')}'));

  /// A relative path, and from schema 2 one of its segments may be a glob.
  ///
  /// One, deliberately: the segment stands for a directory this install named
  /// itself, and a device resolves it before anything downstream ever sees a
  /// pattern. Two would mean a tree to walk and more than one plausible
  /// answer, which is how a save ends up restored into the wrong place.
  static String _relative(String s, String field, {int schema = 1}) {
    if (!PathGuard.isSafeRelative(s)) throw RecipeError('$field "$s" must be a plain relative path');
    final globbed = s.split('/').where((seg) => seg.contains('*') || seg.contains('?') || seg.contains('[')).length;
    if (globbed > 0 && schema < 2) throw RecipeError('$field "$s" needs schema 2 to use a pattern');
    if (globbed > 1) throw RecipeError('$field "$s" may have only one patterned segment');
    return s;
  }

  /// Whether this recipe's roots have to be resolved on the device first.
  bool get rootNeedsResolving => locations.any((l) => l.root.split('/').any((seg) => seg.contains('*') || seg.contains('?') || seg.contains('[')));

  static void _pattern(String s, UnitKind unit, String field) {
    for (final m in _placeholderRe.allMatches(s)) {
      final ph = m[1];
      final ok = (ph == 'folder' && unit == UnitKind.folder) || (ph == 'file' && unit == UnitKind.file);
      if (!ok) throw RecipeError('$field: {$ph} is not valid for unit ${unit.name}');
    }
    if (!PathGuard.isSafeRelative(s.replaceAll(_placeholderRe, 'x'))) throw RecipeError('$field: unsafe pattern "$s"');
  }
}
