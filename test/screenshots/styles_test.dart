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
  final kind = BackdropKind.values.byName(const String.fromEnvironment('BACKDROP', defaultValue: 'drift'));
  final only = const String.fromEnvironment('CARDS');

  for (final cards in CardStyle.values) {
    if (only.isNotEmpty && cards.name != only) continue;
    final style = AppStyle(backdrop: BackdropStyle(kind: kind), cards: cards);
    final tag = 'styles_${cards.name}';

    testWidgets('$tag menu', (t) async {
      await launch(t, const MenuScreen(), style: style, overrides: [patchersProvider.overrideWith((ref) async => [])]);
      await key(t, LogicalKeyboardKey.arrowRight);
      await snap(t, '${tag}_menu_focused');
    }, skip: !screenshotsEnabled);

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
