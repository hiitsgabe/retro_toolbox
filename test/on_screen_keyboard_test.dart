import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

const osk = ValueKey('osk');
Key key(String label) => ValueKey('osk-$label');

Widget app(Widget home, {bool onScreenKeyboard = true, GlobalKey<NavigatorState>? navigator}) {
  final nav = navigator ?? GlobalKey<NavigatorState>();
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

  Widget form({
    ValueChanged<String>? onSubmitted,
    TextInputType? keyboardType,
    VoidCallback? onBelow,
    bool obscureText = false,
    int? maxLength,
    bool showField = true,
  }) =>
      Scaffold(
        body: Column(children: [
          ElevatedButton(autofocus: true, onPressed: () {}, child: const Text('Above')),
          if (showField)
            TextField(
              controller: text,
              focusNode: field,
              keyboardType: keyboardType,
              onSubmitted: onSubmitted,
              obscureText: obscureText,
              maxLength: maxLength,
            ),
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

  testWidgets('gamepad buttons in the keyboard: X space, Y backspace, L1/R1 caret, B hides', (t) async {
    text.text = 'ab';
    await t.pumpWidget(app(form()));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    await press(t, LogicalKeyboardKey.gameButtonLeft1); // a|b
    await press(t, LogicalKeyboardKey.gameButtonX);
    expect(text.text, 'a b');
    await press(t, LogicalKeyboardKey.gameButtonY);
    expect(text.text, 'ab');
    await press(t, LogicalKeyboardKey.gameButtonRight1);
    await press(t, LogicalKeyboardKey.gameButtonX);
    expect(text.text, 'ab ');
    await press(t, LogicalKeyboardKey.gameButtonB);
    expect(find.byKey(osk), findsNothing);
    expect(field.hasPrimaryFocus, isTrue);
  });

  testWidgets('opening the keyboard hides the system IME', (t) async {
    final calls = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, (c) async {
      calls.add(c.method);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.textInput, null));
    await t.pumpWidget(app(form()));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    calls.clear();
    await press(t, LogicalKeyboardKey.enter);
    expect(calls, contains('TextInput.hide'));
  });

  for (final k in [LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.select]) {
    testWidgets('${k.keyLabel.isEmpty ? k.debugName : k.keyLabel} on a focused text field opens the keyboard only when enabled', (t) async {
      for (final enabled in [true, false]) {
        await t.pumpWidget(app(form(), onScreenKeyboard: enabled));
        await t.pump();
        await press(t, LogicalKeyboardKey.arrowDown);
        expect(field.hasPrimaryFocus, isTrue);
        await press(t, k);
        expect(find.byKey(osk), enabled ? findsOneWidget : findsNothing);
        await t.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('B with a text field focused pops the page exactly once', (t) async {
    final nav = GlobalKey<NavigatorState>();
    var pops = 0;
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [_Pops(() => pops++)],
      builder: (c, child) => DpadScope(navigatorKey: nav, onScreenKeyboard: true, child: child!),
      home: Builder(
        builder: (c) => TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(
            builder: (_) => Scaffold(body: TextField(autofocus: true, controller: text, focusNode: field)),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(field.hasPrimaryFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(pops, 1);
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

  testWidgets('signed number fields get a minus key; plain ones do not', (t) async {
    await t.pumpWidget(app(form(keyboardType: TextInputType.number)));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(key('-')), findsNothing);
    await t.pumpWidget(const SizedBox());

    await t.pumpWidget(app(form(keyboardType: const TextInputType.numberWithOptions(signed: true))));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(key('-')), findsOneWidget);
    await t.tap(find.byKey(key('-')));
    await t.pump();
    expect(text.text, '-');
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

  Future<void> open(WidgetTester t) async {
    await press(t, LogicalKeyboardKey.arrowDown);
    expect(field.hasPrimaryFocus, isTrue);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(osk), findsOneWidget);
  }

  testWidgets('closes when the field\'s route pops', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(app(
      Builder(
        builder: (c) => TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => form())),
          child: const Text('Open'),
        ),
      ),
      navigator: nav,
    ));
    await t.pump();
    await press(t, LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    await open(t);
    nav.currentState!.pop();
    await t.pump(); // the pop's first frame: noticed after it
    await t.pump(); // removed; the exit transition is still running
    expect(find.byKey(osk), findsNothing);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(Focus.of(t.element(find.text('Open'))).hasPrimaryFocus, isTrue, reason: 'focus back on the opener');
  });

  testWidgets('closes when the field leaves the tree', (t) async {
    final nav = GlobalKey<NavigatorState>(); // same navigator, so only the field goes
    await t.pumpWidget(app(form(), navigator: nav));
    await t.pump();
    await open(t);
    await t.pumpWidget(app(form(showField: false), navigator: nav));
    await t.pump();
    expect(find.byKey(osk), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('Enter on the field again does not stack a second keyboard', (t) async {
    await t.pumpWidget(app(form()));
    await t.pump();
    await open(t);
    field.requestFocus(); // e.g. a tap back on the field
    await t.pump();
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(osk), findsOneWidget);
  });

  testWidgets('obscured fields show only dots in the header', (t) async {
    text.text = 'abc';
    await t.pumpWidget(app(form(obscureText: true)));
    await t.pump();
    await open(t);
    expect(t.widget<Text>(find.byKey(const ValueKey('osk-header'))).textSpan!.toPlainText(), '•••▏');
  });

  testWidgets('a field maxLength stops input', (t) async {
    text.text = 'ab';
    await t.pumpWidget(app(form(maxLength: 2)));
    await t.pump();
    await open(t);
    await press(t, LogicalKeyboardKey.enter); // q
    expect(text.text, 'ab');
    expect(find.byKey(osk), findsOneWidget);
    expect(field.hasPrimaryFocus, isFalse);
  });

  testWidgets('X types no space on the digit pad', (t) async {
    await t.pumpWidget(app(form(keyboardType: TextInputType.number)));
    await t.pump();
    await open(t);
    await press(t, LogicalKeyboardKey.space);
    expect(text.text, '');
  });

  testWidgets('disabled: Enter does not open the keyboard', (t) async {
    await t.pumpWidget(app(form(), onScreenKeyboard: false));
    await t.pump();
    await press(t, LogicalKeyboardKey.arrowDown);
    await press(t, LogicalKeyboardKey.enter);
    expect(find.byKey(osk), findsNothing);
  });
}

class _Pops extends NavigatorObserver {
  _Pops(this.onPop);
  final VoidCallback onPop;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => onPop();
}
