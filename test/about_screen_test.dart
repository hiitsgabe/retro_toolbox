import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/screens/about_screen.dart';

void main() {
  testWidgets('leaving the About screen before package info loads does not setState after dispose', (t) async {
    final gate = Completer<void>();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/package_info'),
      (_) async {
        await gate.future;
        return <String, dynamic>{'appName': 'x', 'packageName': 'x', 'version': '1', 'buildNumber': '1'};
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'), null));

    await t.pumpWidget(const MaterialApp(home: AboutScreen()));
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await t.pump(const Duration(milliseconds: 10));
    expect(t.takeException(), isNull);
  });
}
