import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';

Widget _app(List<int> taps, FocusNode below) {
  final key = GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: key,
    builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
    home: Scaffold(
      body: Column(children: [
        Expanded(
          child: CoverFlow(items: [
            for (var i = 0; i < 3; i++)
              CoverFlowItem(
                face: Row(children: [
                  Checkbox(value: false, onChanged: (_) {}),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.add)),
                ]),
                label: 'item $i',
                onTap: () => taps.add(i),
              ),
          ]),
        ),
        ElevatedButton(focusNode: below, onPressed: () {}, child: const Text('Below')),
      ]),
    ),
  );
}

void main() {
  late FocusNode below;
  setUp(() => below = FocusNode());
  tearDown(() => below.dispose());

  Future<void> key(WidgetTester t, LogicalKeyboardKey k) async {
    await t.sendKeyEvent(k);
    await t.pumpAndSettle();
  }

  testWidgets('left/right move the centre card and enter opens it', (t) async {
    final taps = <int>[];
    await t.pumpWidget(_app(taps, below));
    await t.pump();

    await key(t, LogicalKeyboardKey.arrowRight);
    await key(t, LogicalKeyboardKey.enter);
    expect(taps, [1]);

    await key(t, LogicalKeyboardKey.arrowLeft);
    await key(t, LogicalKeyboardKey.arrowLeft);
    await key(t, LogicalKeyboardKey.enter);
    expect(taps, [1, 0]);
  });

  testWidgets('ends swallow the arrow; down leaves for the button below', (t) async {
    final taps = <int>[];
    await t.pumpWidget(_app(taps, below));
    await t.pump();

    await key(t, LogicalKeyboardKey.arrowLeft); // at first: no-op
    await key(t, LogicalKeyboardKey.arrowRight);
    await key(t, LogicalKeyboardKey.arrowRight);
    await key(t, LogicalKeyboardKey.arrowRight); // at last: no-op
    expect(below.hasPrimaryFocus, isFalse);
    await key(t, LogicalKeyboardKey.enter);
    expect(taps, [2]);

    await key(t, LogicalKeyboardKey.arrowDown);
    expect(below.hasPrimaryFocus, isTrue);
  });

  testWidgets('faces never take focus, even when tabbing through', (t) async {
    await t.pumpWidget(_app([], below));
    await t.pump();

    final faceNodes = [
      for (final f in [find.byType(Checkbox), find.byType(IconButton)])
        for (final e in f.evaluate()) Focus.of(e),
    ];
    expect(faceNodes, isNotEmpty);
    for (var i = 0; i < 4; i++) {
      await key(t, LogicalKeyboardKey.tab);
      final p = FocusManager.instance.primaryFocus;
      expect(faceNodes.any((n) => n == p || n.descendants.contains(p)), isFalse);
      expect(faceNodes.every((n) => !n.canRequestFocus), isTrue);
    }
  });

  for (final k in [LogicalKeyboardKey.gameButtonA, LogicalKeyboardKey.select, LogicalKeyboardKey.gameButtonStart, LogicalKeyboardKey.f5, LogicalKeyboardKey.space]) {
    testWidgets('${k.debugName} opens the centre card, once per press', (t) async {
      final taps = <int>[];
      await t.pumpWidget(_app(taps, below));
      await t.pump();
      await key(t, LogicalKeyboardKey.arrowRight);
      await t.sendKeyDownEvent(k);
      await t.sendKeyRepeatEvent(k);
      await t.sendKeyRepeatEvent(k);
      await t.sendKeyUpEvent(k);
      await t.pumpAndSettle();
      expect(taps, [1]);
    });
  }
}
