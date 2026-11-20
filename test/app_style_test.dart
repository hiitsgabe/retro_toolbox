import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppStyle JSON', () {
    test('round-trips every field', () {
      const style = AppStyle(
        backdrop: BackdropStyle(kind: BackdropKind.image, top: Color(0xFF00E0A4), bottom: Color(0xFF04080A), imagePath: '/p/a.jpg'),
        cards: CardStyle.vita,
        gameLayout: GameLayout.coverFlow,
      );
      expect(AppStyle.fromJson(style.toJson()), style);
    });

    test('every game layout round-trips; a save from before it reads as the style default', () {
      for (final l in GameLayout.values) {
        expect(AppStyle.fromJson(AppStyle(cards: CardStyle.wii, gameLayout: l).toJson()).gameLayout, l);
      }
      expect(AppStyle.fromJson({'cards': 'vita'}), const AppStyle(cards: CardStyle.vita));
      expect(AppStyle.fromJson({'cards': 'vita'}).gameLayout, GameLayout.styleDefault);
      expect(AppStyle.fromJson({'cards': 'vita', 'gameLayout': 'nope'}).gameLayout, GameLayout.styleDefault);
      expect(const AppStyle(gameLayout: GameLayout.grid), isNot(const AppStyle()));
    });

    test("the games view: a picked layout's in any style, else the style's own (Classic: its toggle)", () {
      for (final c in CardStyle.values) {
        expect(AppStyle(cards: c, gameLayout: GameLayout.grid).gameView(ViewMode.list), ViewMode.grid, reason: c.name);
        expect(AppStyle(cards: c, gameLayout: GameLayout.list).gameView(ViewMode.grid), ViewMode.list, reason: c.name);
        expect(AppStyle(cards: c, gameLayout: GameLayout.coverFlow).gameView(ViewMode.grid), ViewMode.coverflow, reason: c.name);
        expect(AppStyle(cards: c).gameView(ViewMode.list), c == CardStyle.classic ? ViewMode.list : null, reason: c.name);
      }
    });

    test('the header toggle goes round the three views', () {
      expect(GameLayout.grid.next, GameLayout.list);
      expect(GameLayout.list.next, GameLayout.coverFlow);
      expect(GameLayout.coverFlow.next, GameLayout.grid);
    });

    test('a missing, broken or unknown value is the default', () {
      expect(AppStyle.fromJson(const {}), const AppStyle());
      expect(AppStyle.fromJson({'backdrop': 'x', 'cards': 3}), const AppStyle());
      expect(AppStyle.fromJson({'backdrop': {'kind': 'nope'}, 'cards': 'nope'}), const AppStyle());
    });

    test('the default picks no backdrop: Classic cards show their own', () {
      const s = AppStyle();
      expect(s.backdrop, isNull);
      expect(s.toJson().containsKey('backdrop'), isFalse);
      expect(s.cards, CardStyle.classic);
      expect(s.shownBackdrop, StyleTokens.classic.backdrop);
    });

    test('a save holding the old default backdrop reads as not picked', () {
      // Every save had a backdrop, and it was the default unless changed.
      final old = AppStyle.fromJson({'backdrop': const BackdropStyle().toJson(), 'cards': 'switchStyle'});
      expect(old.backdrop, isNull);
      expect(old.shownBackdrop, StyleTokens.switchStyle.backdrop);
      final picked = AppStyle.fromJson({'backdrop': const BackdropStyle(kind: BackdropKind.aurora).toJson(), 'cards': 'switchStyle'});
      expect(picked.shownBackdrop, const BackdropStyle(kind: BackdropKind.aurora));
    });

    test('each card style has a backdrop of its own', () {
      final own = {for (final c in CardStyle.values) c: AppStyle(cards: c).shownBackdrop};
      expect(own.values.toSet(), hasLength(CardStyle.values.length));
      expect(own[CardStyle.classic]!.kind, BackdropKind.dots);
      expect(own.values, isNot(contains(const BackdropStyle())));
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
      expect(c.read(styleProvider).backdrop!.kind, BackdropKind.drift);
      expect(c.read(styleProvider).cards, CardStyle.wii);
    });

    test('a change is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(styleProvider.notifier);
      await n.loaded;
      await n.setCards(CardStyle.switchStyle);
      await n.setBackdrop(c.read(styleProvider).shownBackdrop.copyWith(kind: BackdropKind.paint));
      final prefs = await SharedPreferences.getInstance();
      final again = AppStyle.fromJson(jsonDecodeMap(prefs.getString('app_style')!));
      expect(again.cards, CardStyle.switchStyle);
      expect(again.backdrop!.kind, BackdropKind.paint);
    });

    test('the game layout is stored and stays through card style and backdrop changes', () async {
      SharedPreferences.setMockInitialValues({'app_style': '{"cards":"vita"}'});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(styleProvider.notifier);
      await n.loaded;
      await n.setGameLayout(GameLayout.list);
      final prefs = await SharedPreferences.getInstance();
      GameLayout stored() => AppStyle.fromJson(jsonDecodeMap(prefs.getString('app_style')!)).gameLayout;
      expect(stored(), GameLayout.list);
      await n.setCards(CardStyle.threeDs);
      await n.setBackdrop(const BackdropStyle(kind: BackdropKind.drift));
      // The style's own backdrop picked back clears the pick.
      await n.setBackdrop(StyleTokens.threeDs.backdrop);
      expect(c.read(styleProvider).backdrop, isNull);
      expect(c.read(styleProvider).gameLayout, GameLayout.list);
      expect(stored(), GameLayout.list);
    });

    test('a picked backdrop stays when the card style changes', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(styleProvider.notifier);
      await n.loaded;
      await n.setBackdrop(const BackdropStyle(kind: BackdropKind.drift));
      await n.setCards(CardStyle.wii);
      expect(c.read(styleProvider).shownBackdrop, const BackdropStyle(kind: BackdropKind.drift));
    });

    test('picking the card style\'s own backdrop back is no pick', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(styleProvider.notifier);
      await n.loaded;
      await n.setBackdrop(const BackdropStyle(kind: BackdropKind.drift));
      await n.setBackdrop(StyleTokens.classic.backdrop);
      expect(c.read(styleProvider).backdrop, isNull);
      await n.setCards(CardStyle.vita);
      expect(c.read(styleProvider).shownBackdrop, StyleTokens.vita.backdrop);
    });
  });
}
