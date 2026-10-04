import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

Widget app(Widget home, {GlobalKey<NavigatorState>? nav}) {
  final key = nav ?? GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: key,
    builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
    home: home,
  );
}

void main() {
  testWidgets('arrow down leaves a text field', (t) async {
    final below = FocusNode();
    addTearDown(below.dispose);
    await t.pumpWidget(app(Scaffold(
      body: Column(children: [
        const TextField(autofocus: true),
        ElevatedButton(
          focusNode: below,
          onPressed: () {},
          child: const Text('Below'),
        ),
      ]),
    )));
    await t.pump();
    expect(below.hasPrimaryFocus, isFalse);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(below.hasPrimaryFocus, isTrue);
    expect(
      find.descendant(
        of: find.byType(TextField),
        matching: find.byWidgetPredicate((w) => w is EditableText && w.focusNode.hasFocus),
      ),
      findsNothing,
    );
  });

  testWidgets('page down jumps several items', (t) async {
    await t.pumpWidget(app(Scaffold(
      body: ListView(children: [
        for (var i = 0; i < 20; i++)
          ListTile(autofocus: i == 0, title: Text('item $i'), onTap: () {}),
      ]),
    )));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pump();
    expect(Focus.of(t.element(find.text('item 6'))).hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await t.pump();
    expect(Focus.of(t.element(find.text('item 0'))).hasFocus, isTrue);
  });

  testWidgets('escape pops the top page', (t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(app(
      Builder(
        builder: (c) => TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(c).push(
            MaterialPageRoute(builder: (_) => const Scaffold(body: Text('second'))),
          ),
          child: const Text('open'),
        ),
      ),
      nav: nav,
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('escape closes a dialog without popping the page below', (t) async {
    await t.pumpWidget(app(Builder(
      builder: (c) => TextButton(
        autofocus: true,
        onPressed: () => showDialog<void>(
          context: c,
          builder: (_) => const AlertDialog(title: Text('dlg')),
        ),
        child: const Text('open'),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('dlg'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text('dlg'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('escape on the root page does nothing', (t) async {
    await t.pumpWidget(app(Scaffold(
      body: TextButton(autofocus: true, onPressed: () {}, child: const Text('only')),
    )));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(find.text('only'), findsOneWidget);
  });

  testWidgets('outline shows for keyboard focus and does not keep frames coming',
      (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    await t.pumpWidget(app(Scaffold(
      body: TextButton(autofocus: true, onPressed: () {}, child: const Text('go')),
    )));
    await t.pumpAndSettle();
    expect(find.byType(DpadScope), findsOneWidget);
    final outline = find.descendant(
      of: find.byType(DpadScope),
      matching: find.byKey(const ValueKey('dpad-focus-outline')),
    );
    expect(outline, findsOneWidget);
    // Idle: a focused node must not schedule frames by itself.
    expect(t.binding.hasScheduledFrame, isFalse);
  });
}
