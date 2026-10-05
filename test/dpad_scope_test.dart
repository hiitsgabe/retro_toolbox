import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
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
  });

  testWidgets('page down jumps several items', (t) async {
    await t.pumpWidget(app(Scaffold(
      body: ListView(children: [
        for (var i = 0; i < 20; i++) ListTile(autofocus: i == 0, title: Text('item $i'), onTap: () {}),
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

  testWidgets('gamepad B pops the top page exactly once', (t) async {
    final nav = GlobalKey<NavigatorState>();
    final observer = _PopCounter();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [observer],
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: Builder(
        builder: (c) => TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('second')))),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(observer.pops, 1);
  });

  testWidgets('gamepad R1/L1 page focus like PageDown/PageUp', (t) async {
    await t.pumpWidget(app(Scaffold(
      body: ListView(children: [
        for (var i = 0; i < 20; i++) ListTile(autofocus: i == 0, title: Text('item $i'), onTap: () {}),
      ]),
    )));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonRight1);
    await t.pump();
    expect(Focus.of(t.element(find.text('item 6'))).hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonLeft1);
    await t.pump();
    expect(Focus.of(t.element(find.text('item 0'))).hasFocus, isTrue);
  });

  testWidgets('gamepad Start activates the focused button', (t) async {
    var pressed = 0;
    await t.pumpWidget(app(Scaffold(
      body: ElevatedButton(autofocus: true, onPressed: () => pressed++, child: const Text('go')),
    )));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(pressed, 1);
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

  for (final left in [true, false]) {
    testWidgets('arrow ${left ? 'left' : 'right'} moves the caret mid-text, leaves at the edge', (t) async {
      final field = TextEditingController(text: 'abc');
      final other = FocusNode();
      addTearDown(field.dispose);
      addTearDown(other.dispose);
      await t.pumpWidget(app(Scaffold(
        body: Row(children: [
          if (left) ElevatedButton(focusNode: other, onPressed: () {}, child: const Text('x')),
          SizedBox(width: 200, child: TextField(controller: field, autofocus: true)),
          if (!left) ElevatedButton(focusNode: other, onPressed: () {}, child: const Text('x')),
        ]),
      )));
      await t.pump();
      final key = left ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowRight;
      // Mid-text: caret moves, focus stays.
      field.selection = const TextSelection.collapsed(offset: 1);
      await t.sendKeyEvent(key);
      await t.pump();
      expect(other.hasPrimaryFocus, isFalse);
      expect(field.selection.baseOffset, left ? 0 : 2);
      // Now step to the edge, then the next press leaves.
      field.selection = TextSelection.collapsed(offset: left ? 0 : 3);
      await t.sendKeyEvent(key);
      await t.pump();
      expect(other.hasPrimaryFocus, isTrue);
    });
  }

  testWidgets('empty text field: left and right both leave', (t) async {
    final other = FocusNode();
    addTearDown(other.dispose);
    await t.pumpWidget(app(Scaffold(
      body: Row(children: [
        const SizedBox(width: 200, child: TextField(autofocus: true)),
        ElevatedButton(focusNode: other, onPressed: () {}, child: const Text('x')),
      ]),
    )));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(other.hasPrimaryFocus, isTrue);
  });

  testWidgets('outline follows a moved focus rect and then goes idle', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    late StateSetter setPad;
    var pad = 0.0;
    await t.pumpWidget(app(Scaffold(
      body: StatefulBuilder(builder: (c, set) {
        setPad = set;
        return Padding(
          padding: EdgeInsets.only(top: pad),
          child: Align(
            alignment: Alignment.topLeft,
            child: TextButton(autofocus: true, onPressed: () {}, child: const Text('go')),
          ),
        );
      }),
    )));
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse); // idle stays idle

    setPad(() => pad = 100);
    await t.pump(); // the frame that moves the button
    expect(t.binding.hasScheduledFrame, isTrue); // outline catch-up frame
    await t.pumpAndSettle();
    final outline = t.renderObject<RenderBox>(find.byKey(const ValueKey('dpad-focus-outline')));
    expect(outline.debugNeedsPaint, isFalse);
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('outline survives the focused widget being replaced during layout', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    late StateSetter resize;
    var width = 200.0;
    await t.pumpWidget(
      app(
        Scaffold(
          body: StatefulBuilder(
            builder: (c, set) {
              resize = set;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  // Rebuilt during layout: the old button is deactivated but
                  // not yet unmounted when the outline paints.
                  child: LayoutBuilder(
                    builder: (c, box) => box.maxWidth > 100 ? TextButton(autofocus: true, onPressed: () {}, child: const Text('go')) : const Text('loading'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    // Highlight flips to traditional in the same frame the layout swaps the
    // focused button out, so the outline repaints while it is deactivated.
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    resize(() => width = 50);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('loading'), findsOneWidget);
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('arrow down moves the caret in a multi-line field, up/down leave a single-line one', (t) async {
    final multi = TextEditingController(text: 'one\ntwo\nthree');
    final below = FocusNode();
    addTearDown(multi.dispose);
    addTearDown(below.dispose);
    await t.pumpWidget(app(Scaffold(
      body: Column(children: [
        TextField(controller: multi, autofocus: true, maxLines: null),
        ElevatedButton(focusNode: below, onPressed: () {}, child: const Text('Below')),
      ]),
    )));
    await t.pump();
    multi.selection = const TextSelection.collapsed(offset: 1);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(below.hasPrimaryFocus, isFalse);
    final afterDown = multi.selection.baseOffset;
    expect(afterDown, greaterThan(3)); // moved to the next line
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(below.hasPrimaryFocus, isFalse);
    expect(multi.selection.baseOffset, lessThan(afterDown)); // and back
  });

  testWidgets('arrow up leaves a single-line field', (t) async {
    final above = FocusNode();
    addTearDown(above.dispose);
    await t.pumpWidget(app(Scaffold(
      body: Column(children: [
        ElevatedButton(focusNode: above, onPressed: () {}, child: const Text('Above')),
        const TextField(autofocus: true),
      ]),
    )));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(above.hasPrimaryFocus, isTrue);
  });

  testWidgets('page down scrolls content that has nothing to focus', (t) async {
    double offset() => t.state<ScrollableState>(find.byType(Scrollable)).position.pixels;
    await t.pumpWidget(app(const Scaffold(
      body: SingleChildScrollView(
        primary: true, // the route's PrimaryScrollController, as on mobile
        child: SizedBox(height: 5000, child: Text('long text')),
      ),
    )));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await t.pumpAndSettle();
    expect(offset(), greaterThan(0));
    await t.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await t.pumpAndSettle();
    expect(offset(), 0);
  });

  testWidgets('outline is wrapped in a RepaintBoundary', (t) async {
    await t.pumpWidget(app(const Scaffold(body: SizedBox())));
    final outline = t.renderObject<RenderBox>(find.byKey(const ValueKey('dpad-focus-outline')));
    expect(outline.parent, isA<RenderRepaintBoundary>());
  });
}

class _PopCounter extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}
