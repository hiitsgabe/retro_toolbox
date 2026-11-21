import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/screens/sports_grid_screen.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

const _we = PatcherInfo(gameId: 'we2002-psx', platform: 'psx', sport: 'soccer', requiresSlotMapping: true, providers: ['espn']);
const _nhl = PatcherInfo(gameId: 'nhl94-snes', platform: 'snes', sport: 'hockey', requiresSlotMapping: false, providers: ['espn']);

void main() {
  Future<void> pump(WidgetTester t, Future<List<PatcherInfo>> Function() list) async {
    await t.binding.setSurfaceSize(const Size(1000, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [patchersProvider.overrideWith((ref) => list())],
      child: const MaterialApp(home: SportsGridScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('kit header with the one-line subtitle; the grouping switch is in the action bar', (t) async {
    await pump(t, () async => [_we, _nhl]);
    expect(find.byType(KitScaffold), findsOneWidget);
    expect(find.text('Update rosters in classic games'), findsOneWidget);
    expect(find.byType(SegmentedButton<bool>), findsNothing, reason: 'no toggle in the header');
    expect(find.text('Only a handful of games', findRichText: true), findsNothing, reason: 'the contribute note is behind the (i)');

    List<String> labels() => [for (final tile in t.widget<MenuGrid>(find.byType(MenuGrid)).tiles) tile.label];
    expect(labels(), ['PS1', 'SNES']);
    String? toggle() => t.widget<ActionBar>(find.byType(ActionBar)).secondary?.label;
    expect(toggle(), 'By sport');
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    await t.pumpAndSettle();
    expect(labels(), ['Soccer', 'Hockey']);
    expect(toggle(), 'By console');
  });

  testWidgets('nothing for this device is an empty state, not an error with Retry', (t) async {
    await pump(t, () async => const []);
    expect(find.text('No games for this device yet'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.byType(ActionBar), findsNothing);
  });

  testWidgets('a failed load says so and offers Retry', (t) async {
    await pump(t, () async => throw Exception('offline'));
    expect(find.textContaining("Couldn't load the game list"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
