import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
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

/// The app-wide Style: the menus' background, the card style and the games
/// layout.
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

  /// The card style's own backdrop picked back reads as not picked, so it
  /// follows the card style again.
  Future<void> setBackdrop(BackdropStyle b) =>
      _save(b == StyleTokens.forStyle(state.cards).backdrop ? state.withStyleBackdrop() : state.copyWith(backdrop: b));
  Future<void> setCards(CardStyle c) => _save(state.copyWith(cards: c));
  Future<void> setGameLayout(GameLayout l) => _save(state.copyWith(gameLayout: l));

  Future<void> _save(AppStyle next) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(next.toJson()));
  }
}
