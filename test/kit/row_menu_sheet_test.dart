import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  Widget row(List<String> log) => Scaffold(
        body: Builder(
          builder: (context) => RowMenuTarget(
            onMenu: () => showRowMenu(context, title: 'Stardew Valley', subtitle: '3 saves', items: [
              RowMenuItem('Restore a backup', () => log.add('restore'), icon: Icons.history),
              const RowMenuItem('Check now', null),
              RowMenuItem('Forget', () => log.add('forget'), destructive: true),
            ]),
            child: TextButton(autofocus: true, onPressed: () {}, child: const Text('Stardew Valley row')),
          ),
        ),
      );

  testWidgets('Y opens the row menu with the first action focused; A runs it after the sheet closes', (t) async {
    final log = <String>[];
    await pumpKit(t, row(log));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
    await t.pumpAndSettle();
    expect(find.byType(RowMenuSheet), findsOneWidget);
    expect(find.text('3 saves'), findsOneWidget);
    expect(t.getRect(find.text('Restore a backup')).overlaps(FocusManager.instance.primaryFocus!.rect), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.byType(RowMenuSheet), findsNothing);
    expect(log, ['restore']);
  });

  testWidgets('a long press opens it too; a disabled entry does nothing; B closes', (t) async {
    final log = <String>[];
    await pumpKit(t, row(log));
    await t.longPress(find.text('Stardew Valley row'));
    await t.pumpAndSettle();
    await t.tap(find.text('Check now'));
    await t.pumpAndSettle();
    expect(find.byType(RowMenuSheet), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(find.byType(RowMenuSheet), findsNothing);
    expect(log, isEmpty);
  });
}
