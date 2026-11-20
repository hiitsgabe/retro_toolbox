import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
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

  // The flow is one focus stop; the ring used to go round all of it.
  testWidgets('the focus ring goes round the centre card, in the given shape', (t) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);
    final nav = GlobalKey<NavigatorState>();
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)));
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: Scaffold(
        body: CoverFlow(focusShape: shape, items: [
          for (var i = 0; i < 3; i++) CoverFlowItem(face: SizedBox.expand(key: ValueKey('face $i')), label: 'item $i'),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    final card = t.getRect(find.byKey(const ValueKey('face 1')).first);
    expect(card.width, lessThan(400), reason: 'a card, not the 800 px flow');
    final look = StyleTokens.of(t.element(find.byType(CoverFlow))).focus;
    final width = look.width > 0 ? look.width : 2.0;
    expect(
      t.renderObject(find.byKey(const ValueKey('dpad-focus-outline'))),
      paints..rrect(rrect: RRect.fromRectAndRadius(card, const Radius.circular(12)).inflate(look.gap + width / 2 + 0.5)),
    );
  });

  // A see-through neighbour showed the titles of the cards behind it.
  testWidgets('the cards beside the centre are dimmed, never see-through', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: CoverFlow(items: [for (var i = 0; i < 5; i++) CoverFlowItem(face: const ColoredBox(color: Colors.white), label: 'item $i')])),
    ));
    await t.pump();
    final translucent = t.widgetList<Opacity>(find.byType(Opacity)).where((o) => o.opacity < 1);
    expect(translucent, isEmpty);
  });

  testWidgets('every card has its reflection: the face mirrored under it', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: CoverFlow(items: [for (var i = 0; i < 2; i++) CoverFlowItem(face: Text('title $i'), label: 'item $i')])),
    ));
    await t.pump();
    expect(find.byType(ShaderMask), findsNWidgets(2));
    expect(find.text('title 1'), findsNWidgets(2), reason: 'the face and its mirror');
  });

  // The flow sat in a band in the middle with empty thirds on each side, and
  // its first card touched the top.
  testWidgets('the cards fan out to the edge, and the centre card keeps a gap at the top', (t) async {
    t.view.physicalSize = const Size(731, 320);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CoverFlow(aspectRatio: 0.72, items: [
          for (var i = 0; i < 15; i++) CoverFlowItem(face: SizedBox.expand(key: ValueKey('face $i')), label: 'item $i'),
        ]),
      ),
    ));
    await t.pump();
    final rights = [
      for (var i = 0; i < 15; i++)
        if (find.byKey(ValueKey('face $i')).evaluate().isNotEmpty) t.getRect(find.byKey(ValueKey('face $i')).first).right,
    ];
    expect(rights.reduce((a, b) => a > b ? a : b), greaterThan(731 * 0.9));
    expect(rights.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(731));
    expect(t.getRect(find.byKey(const ValueKey('face 0')).first).top, greaterThan(16));
  });

  // On a phone the card sat in a third of the height, the label by the
  // footer, and one neighbour peeked.
  testWidgets('portrait: a tall card, the label under it, neighbours peeking on both sides', (t) async {
    t.view.physicalSize = const Size(412, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CoverFlow(aspectRatio: 0.72, items: [
          for (var i = 0; i < 12; i++) CoverFlowItem(face: SizedBox.expand(key: ValueKey('face $i')), label: 'item $i'),
        ]),
      ),
    ));
    await t.pumpAndSettle();
    for (var i = 0; i < 5; i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await t.pumpAndSettle();
    }
    final centre = t.getRect(find.byKey(const ValueKey('face 5')).first);
    expect(centre.height, greaterThan(300));
    // The title sits over the reflection's fading end, not by the footer.
    final label = t.getRect(find.text('item 5'));
    expect(label.top, greaterThan(centre.bottom));
    expect(label.bottom - centre.bottom, lessThan(centre.height * 0.42));
    bool peeks(int i) {
      final f = find.byKey(ValueKey('face $i'));
      if (f.evaluate().isEmpty) return false;
      final r = t.getRect(f.first);
      return r.right > 0 && r.left < 412;
    }

    expect([for (final i in [3, 4, 6, 7]) peeks(i)], everyElement(isTrue));
  });
}
