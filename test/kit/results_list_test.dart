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
}
