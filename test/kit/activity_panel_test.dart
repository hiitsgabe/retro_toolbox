import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  testWidgets('the count and the session log, newest first as given', (t) async {
    await pumpKit(
      t,
      const Scaffold(
        body: ActivityPanel(count: 1, countLabel: '1 transfer', entries: [
          ActivityEntry('Celeste.nsz', detail: 'Sending, 40%', time: '12:04', tone: KitTone.accent),
          ActivityEntry('Hollow Knight.nsp', detail: 'Sent', time: '11:58', tone: KitTone.success),
        ]),
      ),
    );
    expect(find.text('1 TRANSFER'), findsOneWidget);
    expect(t.getTopLeft(find.text('Celeste.nsz')).dy, lessThan(t.getTopLeft(find.text('Hollow Knight.nsp')).dy));
    expect(find.text('11:58'), findsOneWidget);
    expect(find.byKey(const ValueKey('kit-activity-empty')), findsNothing);
  });

  testWidgets('says so when nothing happened yet', (t) async {
    await pumpKit(t, const Scaffold(body: ActivityPanel(count: 0)));
    expect(find.byKey(const ValueKey('kit-activity-empty')), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });
}
