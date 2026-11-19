import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_grid/game_grid_item.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_menu.dart';

import 'screenshots/fakes.dart';

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  String getDownloadDir(String? consoleId) => '/downloads';
  @override
  Future<void> get loaded => Future.value();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  final games = snesGames();
  final marks = [for (final m in SelectedMarker.values) 'selected-${m.name}'];

  /// The games screen's list in [style] (Classic: its grid cards), under the
  /// app theme of that style, with [selected] marked.
  Future<void> pump(WidgetTester t, CardStyle style, {Set<String> selected = const {}}) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final nav = GlobalKey<NavigatorState>();
    final list = style == CardStyle.classic
        ? Wrap(children: [
            for (final g in games.take(4)) SizedBox(key: ValueKey(g.gameId), width: 150, height: 200, child: GameGridItem(game: g, autofocus: g == games.first)),
          ])
        : Builder(builder: (c) => cardStyleKit(style)!.gameList(c));
    await t.pumpWidget(ProviderScope(
      overrides: [...gamesOverrides(games, selected: selected), settingsProvider.overrideWith((ref) => _FakeSettings())],
      child: MaterialApp(
        navigatorKey: nav,
        theme: appTheme(style),
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(body: list),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  Finder inCard(int i, Finder f) => find.descendant(of: find.byKey(ValueKey(games[i].gameId)), matching: f);

  for (final style in CardStyle.values) {
    final own = 'selected-${StyleTokens.forStyle(style).selected.marker.name}';

    testWidgets('${style.name}: a selected game wears $own and no other mark', (t) async {
      await pump(t, style, selected: {games[1].gameId});
      expect(inCard(1, find.byKey(ValueKey(own))), findsOneWidget);
      expect(inCard(1, find.byKey(const ValueKey('badge-selected'))), findsOneWidget);
      for (final other in marks.where((m) => m != own)) {
        expect(find.byKey(ValueKey(other)), findsNothing, reason: other);
      }
      expect(inCard(0, find.byKey(ValueKey(own))), findsNothing, reason: 'not selected');
      expect(inCard(2, find.byKey(ValueKey(own))), findsNothing, reason: 'not selected');
    });
  }

  test('each style has its own selected marker', () {
    expect({for (final s in CardStyle.values) StyleTokens.forStyle(s).selected.marker}, hasLength(CardStyle.values.length));
  });

  group('DpadScope outline', () {
    setUp(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional);
    tearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

    RenderObject outline(WidgetTester t) => t.renderObject(find.byKey(const ValueKey('dpad-focus-outline')));

    for (final style in [CardStyle.threeDs, CardStyle.wii]) {
      testWidgets('${style.name}: a focused game card draws its own focus, no outline over it', (t) async {
        await pump(t, style);
        expect(FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<GameCardActions>(), isNotNull, reason: 'a card has focus');
        expect(outline(t), paintsNothing);
      });
    }

    testWidgets('classic: a focused game card gets the outline in the focus colour, round its corners', (t) async {
      await pump(t, CardStyle.classic);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pump();
      final k = StyleTokens.classic;
      final card = t.getRect(find.byType(GameGridItem).at(1));
      final out = k.focus.width / 2 + 0.5;
      expect(
        outline(t),
        paints
          ..rrect(
            color: k.focus.color,
            strokeWidth: k.focus.width,
            rrect: RRect.fromRectAndRadius(card, Radius.circular(k.cardRadius)).inflate(out),
          ),
      );
    });

    for (final style in CardStyle.values) {
      testWidgets('${style.name}: a plain button gets the focus colour', (t) async {
        final nav = GlobalKey<NavigatorState>();
        await t.pumpWidget(MaterialApp(
          navigatorKey: nav,
          theme: appTheme(style),
          builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
          home: Scaffold(body: Center(child: TextButton(autofocus: true, onPressed: () {}, child: const Text('go')))),
        ));
        await t.pump();
        final look = StyleTokens.forStyle(style).focus;
        // A glow is a blurred ring under the ring.
        final ring = look.glow ? (paints..rrect()) : paints;
        expect(outline(t), ring..rrect(color: look.color, strokeWidth: look.width > 0 ? look.width : 2));
      });
    }
  });

  testWidgets('classic: the grid card has no checkbox and no buttons on its face', (t) async {
    await pump(t, CardStyle.classic, selected: {games[1].gameId});
    expect(find.descendant(of: find.byType(GameGridItem), matching: find.byType(Checkbox)), findsNothing);
    expect(find.descendant(of: find.byType(GameGridItem), matching: find.byType(IconButton)), findsNothing);
  });

  testWidgets('the second-screen outline is in the style focus colour', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: appTheme(CardStyle.switchStyle),
      home: const SecondScreenHighlight(shown: true, child: SizedBox(width: 50, height: 50)),
    ));
    final box = t.widget<DecoratedBox>(find.descendant(of: find.byType(SecondScreenHighlight), matching: find.byType(DecoratedBox)).first);
    expect((box.decoration as BoxDecoration).border!.top.color, StyleTokens.switchStyle.focus.color);
  });
}
