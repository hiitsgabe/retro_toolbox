import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';

void main() {
  testWidgets('touch until a key arrives; a key makes it gamepad, a tap touch again', (t) async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        builder: (context, child) => InputModeListener(child: child!),
        home: Scaffold(body: Center(child: TextButton(onPressed: () {}, child: const Text('here')))),
      ),
    ));
    expect(c.read(inputModeProvider), InputMode.touch);

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await t.pump();
    expect(c.read(inputModeProvider), InputMode.gamepad);

    await t.tap(find.text('here'));
    await t.pump();
    expect(c.read(inputModeProvider), InputMode.touch);

    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(c.read(inputModeProvider), InputMode.gamepad);
  });
}
