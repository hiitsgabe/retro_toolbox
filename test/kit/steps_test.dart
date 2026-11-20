import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  testWidgets('every-time steps are numbered; first-time setup opens on demand', (t) async {
    await pumpKit(
      t,
      const Scaffold(
        body: Steps(
          steps: ['Open File Browser', 'Pick this server'],
          firstTime: ['Add a new location', 'Protocol http, host and port as shown', 'Save'],
        ),
      ),
    );
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Open File Browser'), findsOneWidget);
    expect(find.text('Add a new location'), findsNothing);
    expect(find.text('First time setup'), findsOneWidget);

    await t.tap(find.text('First time setup'));
    await t.pump();
    expect(find.text('Add a new location'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('kit-steps-first-time')), matching: find.text('3')), findsOneWidget);
  });

  testWidgets('no first-time row when there is no first-time setup', (t) async {
    await pumpKit(t, const Scaffold(body: Steps(steps: ['One'])));
    expect(find.text('First time setup'), findsNothing);
  });
}
