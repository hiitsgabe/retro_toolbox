import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

void main() {
  testWidgets('focus that lands on a covered page returns to the page on top', (t) async {
    final nav = GlobalKey<NavigatorState>();
    final below = FocusNode(debugLabel: 'below');
    final onTop = FocusNode(debugLabel: 'onTop');
    addTearDown(below.dispose);
    addTearDown(onTop.dispose);
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [DpadScope.routeObserver],
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: Scaffold(body: TextButton(focusNode: below, autofocus: true, onPressed: () {}, child: const Text('menu tile'))),
    ));
    await t.pump();
    nav.currentState!.push(MaterialPageRoute(
      builder: (_) => Scaffold(body: TextButton(focusNode: onTop, onPressed: () {}, child: const Text('games'))),
    ));
    await t.pumpAndSettle();

    // Something hands focus back to the covered page (as seen on device).
    below.requestFocus();
    await t.pump();
    await t.pump();

    expect(below.hasPrimaryFocus, isFalse);
    expect(onTop.hasPrimaryFocus, isTrue);
  });

  testWidgets('dialogs and sheets on top keep their focus', (t) async {
    final nav = GlobalKey<NavigatorState>();
    final inDialog = FocusNode(debugLabel: 'dialog');
    addTearDown(inDialog.dispose);
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [DpadScope.routeObserver],
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: Scaffold(body: TextButton(autofocus: true, onPressed: () {}, child: const Text('page'))),
    ));
    await t.pump();
    showDialog<void>(
      context: nav.currentContext!,
      builder: (_) => AlertDialog(actions: [TextButton(focusNode: inDialog, autofocus: true, onPressed: () {}, child: const Text('OK'))]),
    );
    await t.pumpAndSettle();
    expect(inDialog.hasPrimaryFocus, isTrue);
  });

  testWidgets('back: the outline waits for the closing page to finish', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [DpadScope.routeObserver],
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: Scaffold(body: TextButton(autofocus: true, onPressed: () {}, child: const Text('menu'))),
    ));
    await t.pump();
    nav.currentState!.push(MaterialPageRoute(
      builder: (_) => Scaffold(body: TextButton(autofocus: true, onPressed: () {}, child: const Text('page'))),
    ));
    await t.pumpAndSettle();
    RenderBox outline() => t.renderObject<RenderBox>(find.byKey(const ValueKey('dpad-focus-outline')));
    expect(outline(), paints..rrect());

    nav.currentState!.pop();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(outline(), isNot(paints..rrect())); // page above still closing

    await t.pumpAndSettle();
    expect(outline(), paints..rrect());
  });

  testWidgets('Select calls onOptions, but not over a dialog', (t) async {
    final nav = GlobalKey<NavigatorState>();
    var options = 0;
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [DpadScope.routeObserver],
      builder: (c, child) => DpadScope(navigatorKey: nav, onOptions: () => options++, child: child!),
      home: Scaffold(body: TextButton(autofocus: true, onPressed: () {}, child: const Text('page'))),
    ));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonSelect);
    expect(options, 1);

    showDialog<void>(context: nav.currentContext!, builder: (_) => AlertDialog(actions: [TextButton(autofocus: true, onPressed: () {}, child: const Text('OK'))]));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.f4);
    expect(options, 1);
  });
}
