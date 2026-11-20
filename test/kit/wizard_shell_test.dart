import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  testWidgets('the header says the wizard and the step; Next and Back are in the bar', (t) async {
    await pumpKit(
      t,
      WizardShell(name: 'Setup', step: 1, count: 3, stepName: 'Downloads', body: const SizedBox(), onNext: () {}, onBack: () {}),
      mode: InputMode.gamepad,
    );
    expect(find.text('Step 2 of 3 · Downloads'), findsOneWidget);
    final bar = find.byType(ActionBar);
    expect(find.descendant(of: bar, matching: find.text('NEXT')), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('BACK')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kit-secondary')), matching: find.text('B')), findsOneWidget);
    expect(find.byKey(const ValueKey('kit-back')), findsNothing);
  });

  testWidgets('Start goes next, B goes back a step and does not leave', (t) async {
    var next = 0, back = 0;
    await pumpKit(t, pushed(WizardShell(name: 'Setup', step: 1, count: 3, stepName: 'Downloads', body: const SizedBox(), onNext: () => next++, onBack: () => back++)));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(next, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(back, 1);
    expect(find.text('first page'), findsNothing);
  });

  testWidgets('with no back, B leaves and there is no Back button', (t) async {
    await pumpKit(t, pushed(WizardShell(name: 'Setup', step: 0, count: 3, stepName: 'Catalog', body: const SizedBox(), onNext: () {})));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kit-secondary')), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(find.text('first page'), findsOneWidget);
  });

  testWidgets('Next disabled: Start does nothing', (t) async {
    var pressed = 0;
    await pumpKit(
      t,
      WizardShell(
        name: 'Setup',
        step: 0,
        count: 2,
        stepName: 'Catalog',
        body: Center(child: TextButton(autofocus: true, onPressed: () => pressed++, child: const Text('row'))),
        onNext: null,
      ),
    );
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(pressed, 0);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNull);
  });
}
