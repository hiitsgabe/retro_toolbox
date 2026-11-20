import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'menu_order';

/// The order the user gave each menu, by menu id (`home`, `servers`,
/// `tools`, `consoles`, ...): tile ids, first to last. A menu never moved has
/// no entry and keeps its default order.
final menuOrderProvider = StateNotifierProvider<MenuOrderNotifier, Map<String, List<String>>>((ref) => MenuOrderNotifier());

class MenuOrderNotifier extends StateNotifier<Map<String, List<String>>> {
  MenuOrderNotifier() : super(const {}) {
    loaded = SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (mounted && saved != null) state = _decode(saved);
    });
  }

  /// Completes once the saved orders are in.
  late final Future<void> loaded;

  static Map<String, List<String>> _decode(String s) {
    try {
      final v = jsonDecode(s);
      if (v is! Map) return const {};
      return {
        for (final e in v.entries)
          if (e.key is String && e.value is List) e.key as String: [for (final id in e.value as List) if (id is String) id],
      };
    } catch (_) {
      return const {};
    }
  }

  /// [menu] now shows [visible] (its tiles on screen, in their new order).
  /// Tiles saved but not on screen now keep their slots.
  Future<void> save(String menu, List<String> visible) => _write({...state, menu: mergeMenuOrder(state[menu], visible)});

  /// Every menu back to its default order.
  Future<void> reset() => _write(const {});

  Future<void> _write(Map<String, List<String>> next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (next.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(next));
    }
  }
}

/// [defaults] (tile ids in their default order) in the [saved] order: the
/// saved ids that are there, then the ones the saved order lacks, in default
/// order. Saved ids not in [defaults] are skipped.
List<String> applyMenuOrder(List<String> defaults, List<String>? saved) {
  if (saved == null) return defaults;
  final here = defaults.toSet();
  final seen = <String>{};
  final ordered = [for (final id in saved) if (here.contains(id) && seen.add(id)) id];
  return [...ordered, for (final id in defaults) if (!seen.contains(id)) id];
}

/// The order to save when a menu shows [visible] after a move: the slots of
/// [saved] that hold a tile on screen take [visible] in turn, the others
/// (tiles hidden now) stay where they were, and tiles new to the saved order
/// go at the end.
List<String> mergeMenuOrder(List<String>? saved, List<String> visible) {
  final shown = visible.toSet();
  final seen = <String>{};
  final full = [for (final id in saved ?? const <String>[]) if (seen.add(id)) id];
  var next = 0;
  for (var i = 0; i < full.length; i++) {
    if (shown.contains(full[i])) full[i] = visible[next++];
  }
  return [...full, ...visible.skip(next)];
}
