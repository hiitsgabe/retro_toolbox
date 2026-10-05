import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/menu_grid/cover_flow.dart';

void main() {
  testWidgets('left/right move the centre card and enter opens it', (t) async {
    final taps = <int>[];
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: key,
      builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
      home: Scaffold(
        body: CoverFlow(items: [
          for (var i = 0; i < 3; i++)
            CoverFlowItem(
              face: Row(children: [Checkbox(value: false, onChanged: (_) {}), IconButton(onPressed: () {}, icon: const Icon(Icons.add))]),
              label: 'item $i',
              onTap: () => taps.add(i),
            ),
        ]),
      ),
    ));
    await t.pump();

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, [1]);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, [1, 0]);

    final focus = FocusManager.instance.primaryFocus!;
    expect(focus.context!.findAncestorWidgetOfExactType<Checkbox>(), isNull);
    expect(focus.context!.findAncestorWidgetOfExactType<IconButton>(), isNull);
    expect(find.descendant(of: find.byType(CoverFlow), matching: find.byType(ExcludeFocus)), findsWidgets);
  });
}
