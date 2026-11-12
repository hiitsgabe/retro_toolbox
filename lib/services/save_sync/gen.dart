import 'dart:math';

import 'package:flutter/foundation.dart';

class GenFile {
  const GenFile(this.sha256, this.size);

  final String sha256;
  final int size;
}

/// One immutable version of one unit in the hub. Its `.json` file commits it.
class GenMeta {
  const GenMeta({
    required this.gen,
    required this.parents,
    this.kind = 'save',
    required this.recipe,
    required this.unit,
    required this.device,
    required this.deviceName,
    required this.createdAt,
    required this.package,
    this.packageVersion,
    this.gameVersion,
    required this.files,
    required this.payloadSha256,
  });

  static const format = 1;

  final String gen;
  final List<String> parents;

  /// `save` or `merge`.
  final String kind;
  final String recipe;
  final String unit;
  final String device;
  final String deviceName;
  final DateTime createdAt;
  final String package;
  final String? packageVersion;
  final String? gameVersion;
  final Map<String, GenFile> files;
  final String payloadSha256;

  Map<String, String> get hashes => {for (final e in files.entries) e.key: e.value.sha256};

  Map<String, dynamic> toJson() => {
        'format': format,
        'gen': gen,
        'parents': parents,
        'kind': kind,
        'recipe': recipe,
        'unit': unit,
        'device': device,
        'deviceName': deviceName,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'package': package,
        'packageVersion': packageVersion,
        'gameVersion': gameVersion,
        'files': {for (final e in files.entries) e.key: {'sha256': e.value.sha256, 'size': e.value.size}},
        'payloadSha256': payloadSha256,
      };

  static GenMeta fromJson(Map<String, dynamic> j) {
    if (j['format'] != format) throw FormatException('gen format ${j['format']}');
    try {
      return GenMeta(
        gen: j['gen'] as String,
        parents: List<String>.from(j['parents'] as List),
        kind: j['kind'] as String,
        recipe: j['recipe'] as String,
        unit: j['unit'] as String,
        device: j['device'] as String,
        deviceName: j['deviceName'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
        package: j['package'] as String,
        packageVersion: j['packageVersion'] as String?,
        gameVersion: j['gameVersion'] as String?,
        files: {
          for (final e in (j['files'] as Map<String, dynamic>).entries)
            e.key: GenFile((e.value as Map<String, dynamic>)['sha256'] as String, (e.value as Map<String, dynamic>)['size'] as int),
        },
        payloadSha256: j['payloadSha256'] as String,
      );
    } on TypeError catch (e) {
      throw FormatException('bad gen metadata: $e');
    }
  }
}

final genIdRe = RegExp(r'^\d{8}T\d{6}Z-[a-z0-9-]{1,24}-[0-9a-f]{8}$');

String _two(int n) => n.toString().padLeft(2, '0');

/// `yyyyMMddTHHmmssZ` in UTC.
String utcStamp(DateTime t) {
  final u = t.toUtc();
  return '${u.year.toString().padLeft(4, '0')}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}${_two(u.second)}Z';
}

String makeGenId(DateTime t, String deviceId, String payloadSha) => '${utcStamp(t)}-$deviceId-${payloadSha.substring(0, 8)}';

/// The time at the start of a gen id (or any name starting with a [utcStamp]).
DateTime? genTime(String id) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z').firstMatch(id);
  if (m == null) return null;
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
}

/// A device id made once per install: the model as a slug plus 4 hex digits.
String makeDeviceId(String model, Random random) {
  var slug = model.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) slug = 'device';
  if (slug.length > 19) slug = slug.substring(0, 19).replaceAll(RegExp(r'-+$'), '');
  return '$slug-${random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0')}';
}

/// Gens no other gen names as a parent, newest first.
List<GenMeta> headsOf(List<GenMeta> gens) {
  final parents = {for (final x in gens) ...x.parents};
  return gens.where((x) => !parents.contains(x.gen)).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

/// Gens to delete: everything but the heads and the newest [keep]. A gen
/// whose parent stays is kept too, so a device clock that runs behind never
/// cuts a chain in the middle and brings an old gen back as a head. The list
/// is ordered parents first, so every prefix of it is safe to delete.
List<GenMeta> pruneCandidates(List<GenMeta> gens, {int keep = 20}) {
  final sorted = [...gens]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final kept = {for (final h in headsOf(gens)) h.gen, for (final x in sorted.take(keep)) x.gen};
  final present = {for (final x in gens) x.gen};
  final del = {for (final x in sorted) if (!kept.contains(x.gen)) x.gen};
  for (var changed = true; changed;) {
    changed = false;
    for (final x in gens) {
      if (del.contains(x.gen) && x.parents.any((p) => present.contains(p) && !del.contains(p))) {
        del.remove(x.gen);
        changed = true;
      }
    }
  }
  // Parents first, so stopping after any prefix never leaves a child's parent
  // deleted ahead of it or a parent without its child as a new head.
  final pending = sorted.reversed.where((x) => del.contains(x.gen)).toList();
  final left = {for (final x in pending) x.gen};
  final ordered = <GenMeta>[];
  while (pending.isNotEmpty) {
    final ready = pending.where((x) => !x.parents.any(left.contains)).toList();
    if (ready.isEmpty) break; // a parent cycle in corrupt metadata
    for (final x in ready) {
      ordered.add(x);
      left.remove(x.gen);
    }
    pending.removeWhere((x) => !left.contains(x.gen));
  }
  return ordered;
}

bool sameFiles(Map<String, String> a, Map<String, String> b) => mapEquals(a, b);
