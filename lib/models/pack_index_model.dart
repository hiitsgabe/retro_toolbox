import 'dart:convert';
import 'package:flutter/foundation.dart';

/// A console from the user's catalog: an arbitrary id and a free-form name.
/// The pack provider keys on it, so it needs value equality.
@immutable
class PackTarget {
  final String consoleId;
  final String consoleName;

  const PackTarget(this.consoleId, this.consoleName);

  @override
  bool operator ==(Object other) =>
      other is PackTarget &&
      other.consoleId == consoleId &&
      other.consoleName == consoleName;

  @override
  int get hashCode => Object.hash(consoleId, consoleName);

  @override
  String toString() => 'PackTarget($consoleId, $consoleName)';
}

class PackIndexEntry {
  final String pack;
  final String system;
  final int games;
  final List<String> aliases;

  const PackIndexEntry({
    required this.pack,
    required this.system,
    required this.games,
    required this.aliases,
  });

  factory PackIndexEntry.fromJson(Map<String, dynamic> json) => PackIndexEntry(
        pack: json['pack'] as String,
        system: json['system'] as String,
        games: (json['games'] as int?) ?? 0,
        aliases: ((json['aliases'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'pack': pack, 'system': system, 'games': games, 'aliases': aliases};
}

class PackIndex {
  final String built;
  final List<PackIndexEntry> packs;

  const PackIndex({required this.built, required this.packs});

  /// Same rule as `CatalogService._nameToId`.
  static String normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  /// Finds the console's pack. Pack id and name always beat an alias.
  PackIndexEntry? resolve(PackTarget target) {
    final candidates = <String>{
      normalize(target.consoleId),
      normalize(target.consoleName),
    };
    for (final entry in packs) {
      if (candidates.contains(entry.pack)) return entry;
      if (candidates.contains(normalize(entry.system))) return entry;
    }
    for (final entry in packs) {
      for (final alias in entry.aliases) {
        if (candidates.contains(normalize(alias))) return entry;
      }
    }
    return null;
  }

  factory PackIndex.fromJson(Map<String, dynamic> json) => PackIndex(
        built: json['built'] as String,
        packs: ((json['packs'] as List?) ?? const [])
            .map((e) => PackIndexEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() =>
      {'built': built, 'packs': packs.map((p) => p.toJson()).toList()};

  static PackIndex decode(String jsonStr) =>
      PackIndex.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}
