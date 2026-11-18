import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _key = 'app_style';

/// [s] as a JSON object, or empty for anything else.
Map<String, Object?> jsonDecodeMap(String s) {
  try {
    final v = jsonDecode(s);
    return v is Map<String, Object?> ? v : const {};
  } catch (_) {
    return const {};
  }
}

/// The app-wide Style: the menus' background and the card style.
final styleProvider = StateNotifierProvider<StyleNotifier, AppStyle>((ref) => StyleNotifier());

class StyleNotifier extends StateNotifier<AppStyle> {
  StyleNotifier() : super(const AppStyle()) {
    loaded = SharedPreferences.getInstance().then((prefs) {
      final saved = prefs.getString(_key);
      if (mounted && saved != null) state = AppStyle.fromJson(jsonDecodeMap(saved));
    });
  }

  /// Completes once the saved style is in.
  late final Future<void> loaded;

  Future<void> setBackdrop(BackdropStyle b) => _save(state.copyWith(backdrop: b));
  Future<void> setCards(CardStyle c) => _save(state.copyWith(cards: c));

  Future<void> _save(AppStyle next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.toJson()));
  }
}
