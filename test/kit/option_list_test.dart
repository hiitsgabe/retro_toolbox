import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  testWidgets('a toggle row flips on a tap and on A, and a disabled one does not', (t) async {
    final got = <bool>[];
    await pumpKit(
      t,
      Scaffold(
        body: OptionList(children: [
          OptionToggle(title: 'Delete original', value: false, onChanged: got.add, autofocus: true),
          const OptionToggle(title: 'Locked', value: true, onChanged: null),
        ]),
      ),
    );
    await t.tap(find.text('Delete original'));
    expect(got, [true]);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(got, [true, true]);
    await t.tap(find.text('Locked'));
    expect(got, [true, true]);
  });

  testWidgets('one focus stop per row: down moves from the toggle to the next row', (t) async {
    await pumpKit(
      t,
      Scaffold(
        body: OptionList(children: [
          OptionToggle(title: 'One', value: false, onChanged: (_) {}, autofocus: true),
          OptionToggle(title: 'Two', value: false, onChanged: (_) {}),
        ]),
      ),
    );
    await t.pump();
    final first = FocusManager.instance.primaryFocus;
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    final second = FocusManager.instance.primaryFocus;
    expect(second, isNot(first));
    expect(find.ancestor(of: find.text('Two'), matching: find.byWidgetPredicate((w) => w is InkWell && w.focusNode == null)), findsWidgets);
    expect(t.getRect(find.text('Two')).overlaps(second!.rect), isTrue);
  });

  testWidgets('choices select their value', (t) async {
    String? picked;
    await pumpKit(
      t,
      Scaffold(
        body: StatefulBuilder(
          builder: (context, set) => OptionList(children: [
            for (final v in ['Built-in catalog', 'From a link'])
              OptionChoice<String>(title: v, value: v, groupValue: picked ?? 'Built-in catalog', onSelected: (s) => set(() => picked = s)),
          ]),
        ),
      ),
    );
    KitRadio radio(String title) => t.widget<KitRadio>(find.descendant(of: find.ancestor(of: find.text(title), matching: find.byType(KitRow)), matching: find.byType(KitRadio)));
    expect(radio('Built-in catalog').selected, isTrue);
    expect(radio('From a link').selected, isFalse);
    await t.tap(find.text('From a link'));
    await t.pump();
    expect(picked, 'From a link');
    expect(radio('From a link').selected, isTrue);
    expect(radio('Built-in catalog').selected, isFalse);
  });

  testWidgets('Advanced is closed until opened, and closes again', (t) async {
    await pumpKit(
      t,
      Scaffold(
        body: OptionList(children: [
          OptionExpander(subtitle: '.iso format', children: [OptionToggle(title: 'CD for AetherSX2', value: false, onChanged: (_) {})]),
        ]),
      ),
    );
    expect(find.text('CD for AetherSX2'), findsNothing);
    await t.tap(find.text('Advanced'));
    await t.pump();
    expect(find.text('CD for AetherSX2'), findsOneWidget);
    await t.tap(find.text('Advanced'));
    await t.pump();
    expect(find.text('CD for AetherSX2'), findsNothing);
  });

  testWidgets('Advanced says when it opens and closes', (t) async {
    final told = <bool>[];
    await pumpKit(t, Scaffold(body: OptionList(children: [OptionExpander(onChanged: told.add, children: const [Text('inside')])])));
    await t.tap(find.text('Advanced'));
    await t.pump();
    await t.tap(find.text('Advanced'));
    await t.pump();
    expect(told, [true, false]);
  });

  testWidgets('an action row shows its value and runs', (t) async {
    var ran = 0;
    await pumpKit(t, Scaffold(body: OptionList(children: [OptionAction(title: 'Port', value: '9092', onTap: () => ran++)])));
    expect(find.text('9092'), findsOneWidget);
    await t.tap(find.text('Port'));
    expect(ran, 1);
  });
}
