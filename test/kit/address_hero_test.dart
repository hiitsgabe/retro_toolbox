import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  tearDown(() => Handheld.current = false);

  String shown(WidgetTester t) => t.widget<Text>(find.byKey(const ValueKey('kit-address'))).textSpan!.toPlainText();

  testWidgets('a URL: scheme and path small around host and port', (t) async {
    await pumpKit(t, Scaffold(body: AddressHero.url('http://192.168.1.42:8080/consoles.json', state: ServerState.on, stateDetail: '1 transfer')));
    final spans = (t.widget<Text>(find.byKey(const ValueKey('kit-address'))).textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.map((s) => s.text), ['http://', '192.168.1.42:8080', '/consoles.json']);
    expect(spans[1].style!.fontSize, greaterThan(spans[0].style!.fontSize!));
    expect(find.text('On · 1 transfer'), findsOneWidget);
  });

  testWidgets('host and port apart, each with Copy, which copies it', (t) async {
    String? copied;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpKit(t, Scaffold(body: AddressHero.hostPort(host: '192.168.1.42', port: 9092, state: ServerState.on)));
    expect(shown(t), '192.168.1.42:9092');
    expect(find.text('Host'), findsOneWidget);
    expect(find.text('9092'), findsOneWidget);
    expect(find.text('Copy'), findsNWidgets(2));
    await t.tap(find.text('Copy').last);
    await t.pump();
    expect(copied, '9092');
    expect(find.text('Copied'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('no Copy on the Linux handheld, which has no clipboard', (t) async {
    Handheld.current = true;
    await pumpKit(t, Scaffold(body: AddressHero.hostPort(host: '10.0.0.2', port: 9092, state: ServerState.on)));
    expect(find.text('Copy'), findsNothing);
    await pumpKit(t, Scaffold(body: AddressHero.url('ftp://10.0.0.2:2121', state: ServerState.on)));
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('the pill says the state', (t) async {
    for (final s in ServerState.values) {
      await pumpKit(t, Scaffold(body: AddressHero.url('ftp://10.0.0.2:2121', state: s)));
      expect(find.descendant(of: find.byKey(const ValueKey('kit-server-pill')), matching: find.text(AddressHero.stateWord(s))), findsOneWidget);
    }
  });

  testWidgets('a push target is the other device, with Change and no Copy', (t) async {
    var changed = 0;
    await pumpKit(t, Scaffold(body: AddressHero.pushTarget(address: '192.168.1.50', state: ServerState.off, onChange: () => changed++)));
    expect(find.text('SEND TO'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    await t.tap(find.text('Change'));
    expect(changed, 1);
  });

  testWidgets('a config file variant names the file; other addresses open on demand', (t) async {
    var others = 0;
    await pumpKit(t, Scaffold(body: Column(children: [
      AddressHero.configFile(address: 'http://192.168.1.42:8000', fileName: 'config.json', state: ServerState.on),
      AddressHero.url('http://192.168.1.42:8000', state: ServerState.on, otherAddresses: 2, onOtherAddresses: () => others++),
    ])));
    expect(find.text('IN CONFIG.JSON'), findsOneWidget);
    await t.tap(find.text('Other addresses (2)'));
    expect(others, 1);
  });
}
