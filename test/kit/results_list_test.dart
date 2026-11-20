import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  const groups = [
    ResultGroup('Final Fantasy VII', [
      ResultRow(id: 'ff', title: 'Final Fantasy VII (USA).m3u', subtitle: '3 discs', badge: 'New', badgeTone: KitTone.accent),
    ]),
    ResultGroup('Metal Gear Solid', [
      ResultRow(id: 'mgs', title: 'Metal Gear Solid (USA).m3u', subtitle: '2 discs', badge: 'New', badgeTone: KitTone.accent),
      ResultRow(id: 'old', title: 'Metal Gear Solid.m3u', badge: 'Exists', selectable: false),
    ]),
  ];

  Future<Set<String>> Function() pump(WidgetTester t, Set<String> start) {
    var selected = start;
    final done = pumpKit(
      t,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => ResultsList(groups: groups, selected: selected, onSelectionChanged: (s) => set(() => selected = s)),
        ),
      ),
    );
    return () async {
      await done;
      return selected;
    };
  }

  testWidgets('a tap marks and unmarks a row; a row that exists cannot be marked', (t) async {
    final read = pump(t, {});
    expect(await read(), isEmpty);
    await t.tap(find.text('Final Fantasy VII (USA).m3u'));
    await t.pump();
    expect(await read(), {'ff'});
    await t.tap(find.text('Metal Gear Solid.m3u'));
    await t.pump();
    expect(await read(), {'ff'});
    await t.tap(find.text('Final Fantasy VII (USA).m3u'));
    await t.pump();
    expect(await read(), isEmpty);
  });

  testWidgets('Select marks every row, then none', (t) async {
    final read = pump(t, {'ff'});
    await read();
    await t.tap(find.text('Final Fantasy VII (USA).m3u'));
    await t.pump();
    expect(await read(), isEmpty);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
    await t.pump();
    expect(await read(), {'ff', 'mgs'});
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
    await t.pump();
    expect(await read(), isEmpty);
  });

  testWidgets('each group header counts its marks and has All', (t) async {
    final read = pump(t, {});
    await read();
    expect(find.text('FINAL FANTASY VII'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('kit-group-count-Metal Gear Solid'))).data, '0 of 1');
    await t.tap(find.text('All').last);
    await t.pump();
    expect(await read(), {'mgs'});
    expect(t.widget<Text>(find.byKey(const ValueKey('kit-group-count-Metal Gear Solid'))).data, '1 of 1');
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('rows show their badge', (t) async {
    final read = pump(t, {});
    await read();
    expect(find.text('NEW'), findsNWidgets(2));
    expect(find.text('EXISTS'), findsOneWidget);
  });

  testWidgets('no rows: the empty state', (t) async {
    await pumpKit(t, const Scaffold(body: ResultsList(groups: [ResultGroup('x', [])], empty: Text('Nothing to do'))));
    expect(find.text('Nothing to do'), findsOneWidget);
  });

  testWidgets('a row can lead with a picture, and a footer follows the last row', (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpKit(
      t,
      Scaffold(
        body: ResultsList(
          controller: controller,
          groups: const [
            ResultGroup('Results', [ResultRow(id: 'c', title: 'Celeste', leading: SizedBox(key: ValueKey('banner'), width: 40, height: 20))]),
          ],
          footer: const Text('Loading more'),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('banner')), findsOneWidget);
    expect(t.getTopLeft(find.byKey(const ValueKey('banner'))).dx, lessThan(t.getTopLeft(find.text('Celeste')).dx));
    expect(t.getTopLeft(find.text('Loading more')).dy, greaterThan(t.getTopLeft(find.text('Celeste')).dy));
    expect(controller.hasClients, isTrue);
  });

  // A row's other action (Describe an app with no recipe): Y while it has
  // focus, or a long press, never a separate focus stop.
  testWidgets('Y or a long press on a row runs its menu, and a row without one ignores both', (t) async {
    final menus = <String>[];
    await pumpKit(
      t,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => ResultsList(
            groups: [
              ResultGroup('Apps', [
                ResultRow(id: 'a', title: 'Alpha', onMenu: () => menus.add('a')),
                const ResultRow(id: 'b', title: 'Beta'),
              ]),
            ],
            selected: const {},
            onSelectionChanged: (_) {},
          ),
        ),
      ),
    );
    await t.longPress(find.text('Alpha'));
    await t.pump();
    expect(menus, ['a']);
    await t.longPress(find.text('Beta'));
    await t.pump();
    expect(menus, ['a']);

    Focus.of(t.element(find.text('Alpha'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await t.pump();
    expect(menus, ['a', 'a']);
  });
}
