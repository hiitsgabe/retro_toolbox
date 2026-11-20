import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';

import 'support.dart';
import 'fakes.dart';

void main() {
  screenshotSetUp();
  // 'style': no backdrop picked, so each card style shows its own.
  const backdrop = String.fromEnvironment('BACKDROP', defaultValue: 'drift');
  final kind = backdrop == 'style' ? null : BackdropKind.values.byName(backdrop);
  final only = const String.fromEnvironment('CARDS');
  const layoutName = String.fromEnvironment('LAYOUT');
  final layout = layoutName.isEmpty ? GameLayout.styleDefault : GameLayout.values.byName(layoutName);

  for (final cards in CardStyle.values) {
    if (only.isNotEmpty && cards.name != only) continue;
    final style = AppStyle(backdrop: kind == null ? null : BackdropStyle(kind: kind), cards: cards, gameLayout: layout);
    final tag = 'styles_${cards.name}${layout == GameLayout.styleDefault ? '' : '_${layout.name}'}';

    testWidgets('$tag menu', (t) async {
      await launch(t, const MenuScreen(), style: style, overrides: [patchersProvider.overrideWith((ref) async => [])]);
      await key(t, LogicalKeyboardKey.arrowRight);
      await snap(t, '${tag}_menu_focused');
    }, skip: !screenshotsEnabled);

    // Touch has no hover: on 3DS a tap selects (the strip names Tools), on
    // Switch it opens, and the frame is on Tools once its page is closed.
    if (cards == CardStyle.threeDs || cards == CardStyle.switchStyle) {
      testWidgets('$tag menu tapped', (t) async {
        await launch(t, const MenuScreen(), style: style, overrides: [patchersProvider.overrideWith((ref) async => [])]);
        final ink = find.descendant(of: find.byKey(const ValueKey('Tools')), matching: find.byType(InkWell)).first;
        await t.ensureVisible(ink);
        await frames(t, 4);
        await t.tap(ink);
        await frames(t, 8);
        if (cards == CardStyle.switchStyle) {
          await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
          await frames(t, 8);
        }
        await snap(t, '${tag}_menu_tapped');
      }, skip: !screenshotsEnabled);
    }

    testWidgets('$tag consoles', (t) async {
      await launch(t, const ConsoleGridScreen(), style: style, overrides: consolesOverrides());
      await key(t, LogicalKeyboardKey.arrowRight);
      await snap(t, '${tag}_consoles_focused');
    }, skip: !screenshotsEnabled);

    testWidgets('$tag games focused', (t) async {
      await launch(t, const HomeScreen(), style: style, overrides: gamesOverrides(snesGames()));
      // Two columns on the phone: a second press leaves the grid for the header.
      await key(t, LogicalKeyboardKey.arrowRight);
      if (shotDevice != 'phone') await key(t, LogicalKeyboardKey.arrowRight);
      await snap(t, '${tag}_games_focused');
    }, skip: !screenshotsEnabled);

    // A plain control (the header's filter button): DpadScope's ring in the
    // style's focus look.
    testWidgets('$tag games header focused', (t) async {
      await launch(t, const HomeScreen(), style: style, overrides: gamesOverrides(snesGames()));
      await key(t, LogicalKeyboardKey.arrowUp);
      await snap(t, '${tag}_games_header_focused');
    }, skip: !screenshotsEnabled);

    testWidgets('$tag games selected', (t) async {
      final games = snesGames();
      await launch(t, const HomeScreen(), style: style, overrides: gamesOverrides(games, selected: {games[1].gameId, games[3].gameId}));
      // Two columns on the phone: a second press leaves the grid for the header.
      await key(t, LogicalKeyboardKey.arrowRight);
      if (shotDevice != 'phone') await key(t, LogicalKeyboardKey.arrowRight);
      await snap(t, '${tag}_games_selected');
    }, skip: !screenshotsEnabled);
  }
}
