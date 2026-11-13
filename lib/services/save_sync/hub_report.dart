import 'package:retro_toolbox/services/save_sync/gen.dart';

class GameReport {
  const GameReport({required this.recipe, required this.name, this.package, this.version, required this.state, this.units = const [], this.lastPush, this.lastPull});

  final String recipe;
  final String name;
  final String? package;

  /// Installed versionName; null when not installed or unknown.
  final String? version;

  /// Binding state in words: ready, not installed, needs root, ...
  final String state;

  /// Units with files on this device.
  final List<String> units;
  final DateTime? lastPush;
  final DateTime? lastPull;

  Map<String, dynamic> toJson() => {
        'recipe': recipe,
        'name': name,
        'package': package,
        'version': version,
        'state': state,
        'units': units,
        'lastPush': lastPush?.toUtc().toIso8601String(),
        'lastPull': lastPull?.toUtc().toIso8601String(),
      };

  static GameReport fromJson(Map<String, dynamic> j) => GameReport(
        recipe: '${j['recipe'] ?? ''}',
        name: '${j['name'] ?? j['recipe'] ?? ''}',
        package: j['package'] as String?,
        version: j['version'] as String?,
        state: '${j['state'] ?? ''}',
        units: [for (final u in (j['units'] as List?) ?? const []) '$u'],
        lastPush: DateTime.tryParse('${j['lastPush'] ?? ''}'),
        lastPull: DateTime.tryParse('${j['lastPull'] ?? ''}'),
      );
}

/// What one device writes to `devices/<id>.json`.
class DeviceReport {
  const DeviceReport({
    required this.id,
    required this.name,
    this.model = '',
    this.toolboxVersion = '',
    this.lastSeen,
    this.access = '',
    this.games = const [],
  });

  final String id;
  final String name;
  final String model;
  final String toolboxVersion;
  final DateTime? lastSeen;

  /// shizuku, root or none.
  final String access;
  final List<GameReport> games;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'model': model,
        'toolboxVersion': toolboxVersion,
        'lastSeen': lastSeen?.toUtc().toIso8601String(),
        'access': access,
        'games': [for (final g in games) g.toJson()],
      };

  static DeviceReport fromJson(Map<String, dynamic> j) => DeviceReport(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? j['id'] ?? ''}',
        model: '${j['model'] ?? ''}',
        toolboxVersion: '${j['toolboxVersion'] ?? ''}',
        lastSeen: DateTime.tryParse('${j['lastSeen'] ?? ''}'),
        access: '${j['access'] ?? ''}',
        games: [
          for (final g in (j['games'] as List?) ?? const [])
            if (g is Map<String, dynamic>) GameReport.fromJson(g),
        ],
      );
}

String _utc(DateTime? t) {
  if (t == null) return 'never';
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)} ${two(u.hour)}:${two(u.minute)} UTC';
}

/// The hub's README.txt, built only from device reports and gen metadata.
String buildReadme({
  required List<DeviceReport> devices,
  required Map<String, String> gameNames,
  required Map<String, Map<String, GenMeta>> newest,
  required String writtenBy,
  required DateTime now,
}) {
  final b = StringBuffer()
    ..writeln('Retro Toolbox Saves')
    ..writeln('===================')
    ..writeln()
    ..writeln('Game saves synced by Retro Toolbox (Save Sync). Each save version is a zip')
    ..writeln('in units/<game>/<save>/, with a .json beside it saying which device made it')
    ..writeln('and when. Do not rename or edit files here. To restore a save, use Retro')
    ..writeln("Toolbox, or unpack a zip into the game's save folder by hand.")
    ..writeln()
    ..writeln('Updated ${_utc(now)} by $writtenBy.')
    ..writeln()
    ..writeln('Devices')
    ..writeln('-------');
  for (final d in devices) {
    b.writeln('${d.name} (${d.id}): last seen ${_utc(d.lastSeen)}, access ${d.access.isEmpty ? 'unknown' : d.access}');
    for (final g in d.games) {
      final parts = [
        if (g.version != null) g.version!,
        g.state,
        if (g.units.isNotEmpty) 'saves here: ${g.units.join(', ')}',
      ];
      b.writeln('  ${g.name}: ${parts.join(', ')}');
    }
  }
  b
    ..writeln()
    ..writeln('Games')
    ..writeln('-----');
  for (final recipe in (newest.keys.toList()..sort())) {
    final units = newest[recipe]!;
    if (units.isEmpty) continue;
    b.writeln('${gameNames[recipe] ?? recipe} ($recipe)');
    for (final unit in (units.keys.toList()..sort())) {
      final g = units[unit]!;
      b.writeln('  $unit: ${g.gen}, by ${g.deviceName}, ${_utc(g.createdAt)}');
    }
  }
  return b.toString();
}
