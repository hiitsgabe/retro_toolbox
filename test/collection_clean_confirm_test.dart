import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';

void main() {
  testWidgets('applying asks first (with the count); Cancel keeps everything', (t) async {
    var applied = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CleanSection(
          title: 'Dedupe Games',
          icon: Icons.copy_all,
          description: 'd',
          applyLabel: 'Delete selected',
          scan: () async => [
            CleanRow(path: '/a', title: 'a', subtitle: 's'),
            CleanRow(path: '/b', title: 'b', subtitle: 's'),
          ],
          apply: (rows) async => applied = rows.length,
        ),
      ),
    ));
    await t.tap(find.text('Scan'));
    await t.pumpAndSettle();

    await t.tap(find.textContaining('Delete selected (2)'));
    await t.pumpAndSettle();
    expect(find.textContaining('2 item'), findsOneWidget);
    expect(applied, 0);

    await t.sendKeyEvent(LogicalKeyboardKey.enter); // Cancel is focused
    await t.pumpAndSettle();
    expect(applied, 0);

    await t.tap(find.textContaining('Delete selected (2)'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Delete selected'));
    await t.pumpAndSettle();
    expect(applied, 2);
  });
}
