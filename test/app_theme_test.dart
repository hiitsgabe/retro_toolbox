import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

void main() {
  tearDown(() => Handheld.framebuffer = false);

  // Pushes a page with lib/app.dart's theme and shows its first onstage frame
  // without advancing time; returns where the new page is drawn then.
  Future<Rect> pushOneFrame(WidgetTester t) async {
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: appTheme(),
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: const Scaffold(body: Text('first')),
    ));
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('second'))));
    await t.pump(); // the route's first frame is offstage (hero measurement)
    await t.pump(); // no time passes: a transition would be at its start
    expect(find.text('second'), findsOneWidget);
    return t.getRect(find.ancestor(of: find.text('second'), matching: find.byType(Scaffold)));
  }

  testWidgets('framebuffer mode: a pushed page is in place on its first frame', (t) async {
    Handheld.framebuffer = true;
    expect(await pushOneFrame(t), Offset.zero & t.view.physicalSize / t.view.devicePixelRatio);
  });

  testWidgets('normal mode keeps the page transition', (t) async {
    expect(await pushOneFrame(t), isNot(Offset.zero & t.view.physicalSize / t.view.devicePixelRatio));
    await t.pumpAndSettle();
    expect(find.text('first'), findsNothing);
  });
}
