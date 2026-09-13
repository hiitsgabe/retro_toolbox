import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

// `coverUrl` is null in every test on purpose: with a URL, CachedNetworkImage
// would hit the network inside the test.
Widget _host(
  Widget child, {
  double width = 200,
}) =>
    MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: width, child: child))));

void main() {
  testWidgets('shows the game title', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.text('Crystal Vanguard'), findsOneWidget);
  });

  testWidgets('a sourceless tile gets the cloud-off badge', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('a tile with a source gets no badge', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets('the tile is identical for a confirmed and a guessed source', (tester) async {
    // This widget has no confidence parameter; adding `confidence:` here should
    // stop compiling, which is the point.
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
  });

  testWidgets('no checkbox without an active selection', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('with an active selection every tile shows a checkbox, checked or not', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: true,
      isSelected: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('the selected tile shows the checkbox checked', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: true,
      isSelected: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('short tap opens and long press selects', (tester) async {
    var opened = 0;
    var selected = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () => opened++,
      onLongPress: () => selected++,
      onToggleSelection: () {},
    )));

    await tester.tap(find.byType(PackGridItem));
    await tester.longPress(find.byType(PackGridItem));
    await tester.pump();

    expect(opened, 1);
    expect(selected, 1);
  });

  testWidgets('the checkbox toggles the selection without opening the detail', (tester) async {
    var opened = 0;
    var toggled = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: true,
      onTap: () => opened++,
      onLongPress: () {},
      onToggleSelection: () => toggled++,
    )));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(toggled, 1);
    expect(opened, 0);
  });

  testWidgets('the thick border appears when the game is already on disk', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      isOwned: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final border = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((border.decoration as BoxDecoration).border!.top.width, 3);
  });

  testWidgets('with no state the border is thin', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final border = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((border.decoration as BoxDecoration).border!.top.width, 1);
  });
}
