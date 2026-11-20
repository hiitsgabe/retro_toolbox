import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

import 'kit_support.dart';

void main() {
  testWidgets('one icon at the one size, one line, one action', (t) async {
    var ran = 0;
    await pumpKit(
      t,
      Scaffold(body: EmptyState(icon: Icons.search_off, glyph: PixelIcons.games, line: 'No games match', action: KitAction('Reset filters', () => ran++))),
      style: CardStyle.vita,
    );
    expect(t.widget<Icon>(find.byIcon(Icons.search_off)).size, EmptyState.iconSize);
    expect(find.text('No games match'), findsOneWidget);
    await t.tap(find.text('Reset filters'));
    expect(ran, 1);
  });

  testWidgets('pixel styles draw the glyph at the same size', (t) async {
    await pumpKit(t, const Scaffold(body: EmptyState(icon: Icons.search_off, glyph: PixelIcons.games, line: 'No games')), style: CardStyle.classic);
    expect(t.widget<PixelIcon>(find.byType(PixelIcon)).size, EmptyState.iconSize);
    expect(find.byIcon(Icons.search_off), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('a second action sits beside the first, and either can be left out', (t) async {
    final ran = <String>[];
    await pumpKit(
      t,
      Scaffold(
        body: EmptyState(
          icon: Icons.search_off,
          line: 'No games match',
          action: KitAction('Reset filters', () => ran.add('reset')),
          secondAction: KitAction('Clear search', () => ran.add('clear')),
        ),
      ),
      style: CardStyle.vita,
    );
    expect(t.getCenter(find.text('Reset filters')).dy, closeTo(t.getCenter(find.text('Clear search')).dy, 1));
    await t.tap(find.text('Clear search'));
    await t.tap(find.text('Reset filters'));
    expect(ran, ['clear', 'reset']);

    await pumpKit(t, Scaffold(body: EmptyState(line: 'No games match', secondAction: KitAction('Clear search', () {}))), style: CardStyle.vita);
    expect(find.byType(OutlinedButton), findsOneWidget);
  });
}
