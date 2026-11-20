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

  // A desktop has no back key: the first step still needs a button out.
  testWidgets('leaveLabel on the first step: a button that leaves, and B leaves too', (t) async {
    await pumpKit(t, pushed(WizardShell(name: 'Setup', step: 0, count: 3, stepName: 'Catalog', body: const SizedBox(), onNext: () {}, leaveLabel: 'Cancel')),
        mode: InputMode.gamepad);
    await t.pumpAndSettle();
    final leave = find.byKey(const ValueKey('kit-secondary'));
    expect(find.descendant(of: leave, matching: find.text('CANCEL')), findsOneWidget);
    expect(find.descendant(of: leave, matching: find.text('B')), findsOneWidget);
    await t.tap(leave);
    await t.pumpAndSettle();
    expect(find.text('first page'), findsOneWidget);
  });

  testWidgets('leaveLabel gives way to Back once there is a step to go back to', (t) async {
    var back = 0;
    await pumpKit(t, WizardShell(name: 'Setup', step: 1, count: 3, stepName: 'Downloads', body: const SizedBox(), onNext: () {}, onBack: () => back++, leaveLabel: 'Cancel'));
    expect(find.text('CANCEL'), findsNothing);
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    expect(back, 1);
  });

  // Work in flight: going back would leave it running behind a page that
  // no longer shows it.
  testWidgets('backEnabled false: Back is disabled and B neither steps back nor leaves', (t) async {
    var back = 0;
    await pumpKit(t, pushed(WizardShell(name: 'Setup', step: 1, count: 3, stepName: 'Downloads', body: const SizedBox(), onNext: null, onBack: () => back++, backEnabled: false)));
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('kit-secondary'))).onPressed, isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(back, 0);
    expect(find.text('first page'), findsNothing);
  });

  testWidgets('backEnabled false on a first step: B does not leave', (t) async {
    await pumpKit(t, pushed(WizardShell(name: 'Setup', step: 0, count: 3, stepName: 'Catalog', body: const SizedBox(), onNext: null, leaveLabel: 'Cancel', backEnabled: false)));
    await t.pumpAndSettle();
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('kit-secondary'))).onPressed, isNull);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await t.pumpAndSettle();
    expect(find.text('first page'), findsNothing);
  });
}
