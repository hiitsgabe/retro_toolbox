import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';

void main() {
  // The Linux handheld has no touchscreen: its hints show from the start.
  test('gamepad before any input on Linux, touch on the other platforms', () {
    InputMode first(TargetPlatform p) {
      debugDefaultTargetPlatformOverride = p;
      try {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        return c.read(inputModeProvider);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    expect(first(TargetPlatform.linux), InputMode.gamepad);
    for (final p in TargetPlatform.values.where((p) => p != TargetPlatform.linux)) {
      expect(first(p), InputMode.touch, reason: p.name);
    }
  });

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
