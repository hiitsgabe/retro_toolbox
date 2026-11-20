import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  tearDown(() => Handheld.current = false);

  testWidgets('name, where it goes on the console, Save and Copy', (t) async {
    var saved = 0, copied = 0;
    await pumpKit(
      t,
      Scaffold(body: ConfigFileSlot(fileName: 'webdav.json', destination: 'sd:/switch/JKSV', onSave: () => saved++, onCopy: () => copied++)),
    );
    expect(find.text('webdav.json'), findsOneWidget);
    expect(find.text('Goes to sd:/switch/JKSV'), findsOneWidget);
    expect(find.byKey(const ValueKey('kit-config-stale')), findsNothing);
    await t.tap(find.text('Save file'));
    await t.tap(find.text('Copy'));
    expect((saved, copied), (1, 1));
  });

  testWidgets('warns when the saved file has an old address', (t) async {
    await pumpKit(t, Scaffold(body: ConfigFileSlot(fileName: 'config.json', destination: 'ps4:/data', onSave: () {}, stale: true)));
    expect(find.byKey(const ValueKey('kit-config-stale')), findsOneWidget);
  });

  testWidgets('no Copy on the Linux handheld', (t) async {
    Handheld.current = true;
    await pumpKit(t, Scaffold(body: ConfigFileSlot(fileName: 'config.json', destination: 'ps4:/data', onSave: () {}, onCopy: () {})));
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Save file'), findsOneWidget);
  });
}
