import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

const osk = ValueKey('osk');
Key key(String label) => ValueKey('osk-$label');

Widget app(Widget home, {bool onScreenKeyboard = true}) {
  final nav = GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: nav,
    builder: (c, child) => DpadScope(navigatorKey: nav, onScreenKeyboard: onScreenKeyboard, child: child!),
    home: home,
  );
}

Future<void> press(WidgetTester t, LogicalKeyboardKey k, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await t.sendKeyEvent(k);
    await t.pump();
  }
}

bool focused(WidgetTester t, String label) => Focus.of(t.element(find.byKey(key(label)))).hasPrimaryFocus;

void main() {
  late TextEditingController text;
  late FocusNode field;
  setUp(() {
    text = TextEditingController();
    field = FocusNode();
  });
  tearDown(() {
    text.dispose();
    field.dispose();
  });

  Widget form({ValueChanged<String>? onSubmitted, TextInputType? keyboardType, VoidCallback? onBelow}) => Scaffold(
        body: Column(children: [
          ElevatedButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
          TextField(controller: text, focusNode: field, keyboardType: keyboardType, onSubmitted: onSubmitted),
          ElevatedButton(onPressed: onBelow ?? () {}, child: const Text('Below')),
        ]),
      );

  testWidgets('focusing a field does not open the keyboard; Enter does', (t) async {
    await t.pumpWidget(app(form()));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(field.hasPrimaryFocus, isTrue);
    expect(find.byKey(osk), findsNothing);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(osk), findsOneWidget);
  });

  testWidgets('arrows move between keys and Enter types into the field', (t) async {
    await t.pumpWidget(app(form()));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    expect(focused(t, 'q'), isTrue);
    await press(t, LogicalKeyboardKey.arrowDown); // a
    await press(t, LogicalKeyboardKey.arrowRight, 5); // h
    expect(focused(t, 'h'), isTrue);
    await press(t, LogicalKeyboardKey.enter);
    await press(t, LogicalKeyboardKey.arrowUp); // u or y
    while (!focused(t, 'i')) {
      await press(t, LogicalKeyboardKey.arrowRight);
    }
    await press(t, LogicalKeyboardKey.enter);
    expect(text.text, 'hi');
    expect(field.hasPrimaryFocus, isFalse, reason: 'the keyboard owns the d-pad');
  });

  testWidgets('gamepad shortcuts: X space, Y backspace, L1/R1 caret', (t) async {
    text.text = 'ab';
    await t.pumpWidget(app(form()));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    await press(t, LogicalKeyboardKey.pageUp); // caret between a|b
    await press(t, LogicalKeyboardKey.space);
    expect(text.text, 'a b');
    await press(t, LogicalKeyboardKey.tab);
    expect(text.text, 'ab');
    await press(t, LogicalKeyboardKey.pageDown);
    await press(t, LogicalKeyboardKey.space);
    expect(text.text, 'ab ');
  });

  testWidgets('Escape hides the keyboard and keeps focus on the field', (t) async {
    await t.pumpWidget(app(form()));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    await press(t, LogicalKeyboardKey.escape);
    expect(find.byKey(osk), findsNothing);
    expect(field.hasPrimaryFocus, isTrue);
    expect(find.text('Above'), findsOneWidget, reason: 'the route was not popped');
  });

  testWidgets('Done submits the text and focuses the next control', (t) async {
    String? submitted;
    text.text = 'go';
    await t.pumpWidget(app(form(onSubmitted: (s) => submitted = s)));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    Focus.of(t.element(find.byKey(key('Done')))).requestFocus();
    await t.pump();
    await press(t, LogicalKeyboardKey.enter);
    expect(submitted, 'go');
    expect(find.byKey(osk), findsNothing);
    expect(Focus.of(t.element(find.text('Below'))).hasPrimaryFocus, isTrue);
  });

  testWidgets('number fields get a digit pad', (t) async {
    await t.pumpWidget(app(form(keyboardType: TextInputType.number)));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(key('7')), findsOneWidget);
    expect(find.byKey(key('q')), findsNothing);
  });

  testWidgets('fits the handheld screen (600x400 logical) on every page', (t) async {
    t.view
      ..physicalSize = const Size(720, 480)
      ..devicePixelRatio = 1.2;
    addTearDown(t.view.reset);
    await t.pumpWidget(app(form()));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    expect(t.getSize(find.byKey(osk)).height, lessThanOrEqualTo(400 * 0.45));
    await t.tap(find.byKey(key('symbols')));
    await t.pump();
    expect(find.byKey(key('~')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('disabled: Enter does not open the keyboard', (t) async {
    await t.pumpWidget(app(form(), onScreenKeyboard: false));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(osk), findsNothing);
  });
}
