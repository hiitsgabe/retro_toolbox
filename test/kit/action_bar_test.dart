import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  Widget screen({KitAction? secondary, String? summary}) => KitScaffold(
        title: 'Tool',
        body: const SizedBox.expand(),
        actionBar: ActionBar(
          primary: KitAction('Add to Tasks', () {}),
          secondary: secondary,
          hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
          summary: summary,
        ),
      );

  testWidgets('hints and the START cap show only after gamepad input', (t) async {
    final c = await pumpKit(t, screen(), mode: InputMode.touch);
    expect(find.text('Choose'), findsNothing);
    expect(find.text('START'), findsNothing);

    c.read(inputModeProvider.notifier).state = InputMode.gamepad;
    await t.pump();
    expect(find.text('Choose'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kit-primary')), matching: find.text('START')), findsOneWidget);
  });

  testWidgets('the bar is one row high on a pad, its key caps no taller than the text', (t) async {
    for (final d in [odin2, linux640]) {
      await pumpKit(t, screen(summary: 'x'), device: d, mode: InputMode.gamepad);
      expect(t.getSize(find.byType(ActionBar)).height, lessThan(60), reason: '$d');
      expect(t.getSize(find.byType(PadKey).first).height, lessThan(30), reason: '$d');
    }
    await pumpKit(t, screen(), device: phone, mode: InputMode.gamepad);
    expect(t.getSize(find.byType(ActionBar)).height, lessThan(100));
  });

  testWidgets('in portrait the primary takes the width, with no hints even on a pad', (t) async {
    await pumpKit(t, screen(), device: phone, mode: InputMode.gamepad);
    expect(t.getSize(find.byKey(const ValueKey('kit-primary'))).width, greaterThan(412 - 2 * 16 - 1));
    expect(find.text('Choose'), findsNothing);
  });

  testWidgets('on Odin 2 the primary keeps its own width at the right', (t) async {
    await pumpKit(t, screen());
    final r = t.getRect(find.byKey(const ValueKey('kit-primary')));
    expect(r.width, lessThan(300));
    expect(r.right, greaterThan(731 - 20));
  });

  testWidgets('the summary is one line', (t) async {
    await pumpKit(t, screen(summary: 'Crash Bandicoot (USA).cue to .chd'));
    final s = t.widget<Text>(find.byKey(const ValueKey('kit-summary')));
    expect(s.data, 'Crash Bandicoot (USA).cue to .chd');
    expect(s.maxLines, 1);
  });

  testWidgets('a secondary on Select answers Select, and shows its cap on a pad', (t) async {
    var added = 0;
    await pumpKit(t, screen(secondary: KitAction('Add app', () => added++, button: PadButton.select)), mode: InputMode.gamepad);
    expect(find.descendant(of: find.byKey(const ValueKey('kit-secondary')), matching: find.text('SELECT')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
    await t.pump();
    expect(added, 1);
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    expect(added, 2);
  });

  testWidgets('a tap on the primary runs it', (t) async {
    var ran = 0;
    await pumpKit(t, KitScaffold(title: 'T', body: const SizedBox(), actionBar: ActionBar(primary: KitAction('Go', () => ran++))));
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    expect(ran, 1);
  });
}
