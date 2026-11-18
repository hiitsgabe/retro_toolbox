import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppStyle JSON', () {
    test('round-trips every field', () {
      const style = AppStyle(
        backdrop: BackdropStyle(kind: BackdropKind.image, top: Color(0xFF00E0A4), bottom: Color(0xFF04080A), imagePath: '/p/a.jpg'),
        cards: CardStyle.vita,
      );
      expect(AppStyle.fromJson(style.toJson()), style);
    });

    test('a missing, broken or unknown value is the default', () {
      expect(AppStyle.fromJson(const {}), const AppStyle());
      expect(AppStyle.fromJson({'backdrop': 'x', 'cards': 3}), const AppStyle());
      expect(AppStyle.fromJson({'backdrop': {'kind': 'nope'}, 'cards': 'nope'}), const AppStyle());
    });

    test('the default is Flat in the Retro Toolbox colours with Classic cards', () {
      const s = AppStyle();
      expect(s.backdrop.kind, BackdropKind.flat);
      expect((s.backdrop.top, s.backdrop.bottom), backdropPresets['Retro Toolbox']);
      expect(s.cards, CardStyle.classic);
    });
  });

  group('styleProvider', () {
    test('loads what was saved', () async {
      SharedPreferences.setMockInitialValues({
        'app_style': '{"backdrop":{"kind":"drift","top":4286336239,"bottom":4279701547},"cards":"wii"}',
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(styleProvider.notifier).loaded;
      expect(c.read(styleProvider).backdrop.kind, BackdropKind.drift);
      expect(c.read(styleProvider).cards, CardStyle.wii);
    });

    test('a change is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(styleProvider.notifier);
      await n.loaded;
      await n.setCards(CardStyle.switchStyle);
      await n.setBackdrop(c.read(styleProvider).backdrop.copyWith(kind: BackdropKind.paint));
      final prefs = await SharedPreferences.getInstance();
      final again = AppStyle.fromJson(jsonDecodeMap(prefs.getString('app_style')!));
      expect(again.cards, CardStyle.switchStyle);
      expect(again.backdrop.kind, BackdropKind.paint);
    });
  });
}
