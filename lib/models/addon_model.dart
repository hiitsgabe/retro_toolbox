import 'package:flutter/foundation.dart';

/// The addon id for the built-in `consoles.json` source.
///
/// Warning: harvested tokens are stored under this id, so changing it orphans
/// the user's secret in the vault.
const kBuiltinAddonId = 'builtin';

/// An installed catalog source, in the position the user placed it.
///
/// Position in the list is the priority: it feeds `sourcePriority`. Hence a
/// `List` and not a `Set` or a map.
@immutable
class Addon {
  final String id;
  final String name;

  /// Where the catalog came from, when it came from a URL. `null` for the
  /// built-in source and for a catalog imported from a file.
  final String? url;

  const Addon({required this.id, required this.name, this.url});

  bool get isBuiltin => id == kBuiltinAddonId;

  Addon copyWith({String? name, String? url}) => Addon(id: id, name: name ?? this.name, url: url ?? this.url);

  /// A stable id for the URL a catalog came from: scheme, `www.`, query and
  /// trailing slash all collapse to the same id, so reinstalling the same
  /// source finds the token already in the vault.
  ///
  /// Warning: the port is part of the id on purpose, via `hasPort` not `port`,
  /// so scheme-default ports stay collapsed while distinct ports stay distinct.
  static String idFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final raw = (uri == null || uri.host.isEmpty)
        ? url
        : '${uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    final slug = _slug(raw);
    return slug == kBuiltinAddonId ? '${slug}_1' : slug;
  }

  factory Addon.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return Addon(id: id, name: json['name'] as String? ?? id, url: json['url'] as String?);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (url != null) 'url': url};
}

String _slug(String text) {
  final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'addon' : cleaned;
}

/// Inserts [incoming]. If an addon with the same id exists, it is replaced in
/// place: reinstalling a source to fix its url must not demote its priority.
List<Addon> upsertAddon(List<Addon> list, Addon incoming) {
  final i = list.indexWhere((a) => a.id == incoming.id);
  if (i < 0) return [...list, incoming];
  final result = [...list];
  result[i] = incoming;
  return result;
}

List<Addon> removeAddon(List<Addon> list, String id) => [
      for (final a in list)
        if (a.id != id) a,
    ];

/// Moves an item with `ReorderableListView` semantics: a downward move's
/// `newIndex` already counts the vacated slot, so the real target is one less.
List<Addon> reorderAddons(List<Addon> list, int from, int to) {
  if (from < 0 || from >= list.length) return list;
  final result = [...list];
  final item = result.removeAt(from);
  final target = to > from ? to - 1 : to;
  result.insert(target.clamp(0, result.length), item);
  return result;
}
