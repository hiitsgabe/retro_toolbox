import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/widgets/backdrop/backdrop.dart';

Future<void> pump(WidgetTester t, BackdropStyle s, {bool still = false}) async {
  await t.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Backdrop(style: s, still: still, child: const Text('menu'))));
  // AnimatedMeshGradient starts a zero-duration Future in initState; a short pump lets it run before the test ends.
  await t.pump(const Duration(milliseconds: 1));
}

void main() {
  for (final kind in [BackdropKind.flat, BackdropKind.paint, BackdropKind.aurora, BackdropKind.drift, BackdropKind.dots]) {
    testWidgets('${kind.name} draws its backdrop under the child', (t) async {
      await pump(t, BackdropStyle(kind: kind));
      expect(find.byKey(ValueKey('backdrop-${kind.name}')), findsOneWidget);
      expect(find.text('menu'), findsOneWidget);
    });
  }

  testWidgets('a still screen draws Flat for the shader kinds', (t) async {
    await pump(t, const BackdropStyle(kind: BackdropKind.paint), still: true);
    expect(find.byKey(const ValueKey('backdrop-flat')), findsOneWidget);
    await pump(t, const BackdropStyle(kind: BackdropKind.aurora), still: true);
    expect(find.byKey(const ValueKey('backdrop-flat')), findsOneWidget);
  });

  testWidgets('a still drift has no running animation', (t) async {
    await pump(t, const BackdropStyle(kind: BackdropKind.drift), still: true);
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('Image without a path is Flat', (t) async {
    await pump(t, const BackdropStyle(kind: BackdropKind.image));
    expect(find.byKey(const ValueKey('backdrop-flat')), findsOneWidget);
  });

  testWidgets('Image with a path draws the file', (t) async {
    final dir = Directory.systemTemp.createTempSync('bd');
    addTearDown(() => dir.deleteSync(recursive: true));
    await pump(t, BackdropStyle(kind: BackdropKind.image, imagePath: '${dir.path}/x.jpg'));
    expect(find.byKey(const ValueKey('backdrop-image')), findsOneWidget);
  });
}
