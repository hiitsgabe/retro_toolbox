import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

/// A server screen in miniature: the pill and Start, over a start that
/// finishes when the test says.
class _Server extends StatefulWidget {
  const _Server({required this.start});

  final Completer<void> Function() start;

  @override
  State<_Server> createState() => _ServerState();
}

class _ServerState extends State<_Server> with ServerToggle {
  bool running = false;

  @override
  Widget build(BuildContext context) => KitScaffold(
        title: 'Server',
        body: AddressHero(state: serverStateOf(running: running, starting: starting), address: running ? '10.0.0.2:9092' : ''),
        actionBar: ActionBar(
          primary: serverAction(
            running: running,
            starting: starting,
            onToggle: () => toggleServer(
              running: running,
              start: () async {
                await widget.start().future;
                setState(() => running = true);
              },
              stop: () async => setState(() => running = false),
            ),
          ),
        ),
      );
}

void main() {
  tearDown(() => Handheld.current = false);

  test('the pill: on wins, then starting, then the last error, else off', () {
    expect(serverStateOf(running: true, starting: true, error: 'x'), ServerState.on);
    expect(serverStateOf(running: false, starting: true, error: 'x'), ServerState.starting);
    expect(serverStateOf(running: false, error: 'Port in use'), ServerState.error);
    expect(serverStateOf(running: false, error: ''), ServerState.off);
    expect(serverStateOf(running: false), ServerState.off);
  });

  test('transfers read as words, and nothing when none move', () {
    expect(transfersLabel(0), isNull);
    expect(transfersLabel(1), '1 transfer');
    expect(transfersLabel(3), '3 transfers');
  });

  testWidgets('Start says Starting while the server comes up, then Stop server; a second press meanwhile does nothing', (t) async {
    final starts = <Completer<void>>[];
    await pumpKit(t, _Server(start: () => (starts..add(Completer<void>())).last));
    String label() => t.widget<Text>(find.descendant(of: find.byKey(const ValueKey('kit-primary')), matching: find.byType(Text))).data!.toLowerCase();

    expect(label(), 'start server');
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await t.pump();
    expect(label(), 'starting…');
    expect(find.text('Starting'), findsOneWidget, reason: 'the pill');
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNull);
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    expect(starts, hasLength(1));

    starts.single.complete();
    await t.pump();
    await t.pump();
    expect(label(), 'stop server');
    expect(find.text('On'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await t.pump();
    expect(label(), 'start server');
  });

  testWidgets('the port opens a field in place; a port out of range is said, not taken', (t) async {
    final got = <int>[];
    await pumpKit(t, Scaffold(body: OptionList(children: [PortOption(port: 9092, onChanged: got.add)])));
    expect(find.text('9092'), findsOneWidget);
    await t.tap(find.text('Port'));
    await t.pump();
    final field = find.descendant(of: find.byType(FieldSlot), matching: find.byType(TextField));
    await t.enterText(field, '70000');
    await t.pump();
    expect(find.text('Use a port from 1 to 65535'), findsOneWidget);
    expect(got, isEmpty);
    await t.enterText(field, '9100');
    await t.pump();
    expect(find.text('Use a port from 1 to 65535'), findsNothing);
    expect(got, [9100]);
  });

  testWidgets('a locked port shows its value and why, and does not open', (t) async {
    await pumpKit(t, Scaffold(body: OptionList(children: [PortOption(port: 2121, onChanged: (_) {}, lockedReason: lockedWhileRunning)])));
    expect(find.text('2121'), findsOneWidget);
    expect(find.text(lockedWhileRunning), findsOneWidget);
    await t.tap(find.text('Port'));
    await t.pump();
    expect(find.byType(FieldSlot), findsNothing);
  });

  testWidgets('other addresses list every one with Copy, and their own actions', (t) async {
    var saved = 0;
    await pumpKit(
      t,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showOtherAddresses(context, addresses: [
              const AddressChoice('http://10.0.0.7:9091'),
              AddressChoice('http://172.16.0.4:9091', actions: [KitAction('Save file', () => saved++)]),
            ]),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('http://10.0.0.7:9091'), findsOneWidget);
    expect(find.text('http://172.16.0.4:9091'), findsOneWidget);
    expect(find.text('Copy'), findsNWidgets(2));
    expect(find.textContaining('Settings > Network & servers > Address'), findsOneWidget);
    await t.tap(find.text('Save file'));
    expect(saved, 1);
  });

  testWidgets('on the Linux handheld the sheet has no Copy and no setting to point to', (t) async {
    Handheld.current = true;
    await pumpKit(
      t,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () => showOtherAddresses(context, addresses: const [AddressChoice('ftp://10.0.0.7:2121')]), child: const Text('open')),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('ftp://10.0.0.7:2121'), findsOneWidget);
    expect(find.text('Copy'), findsNothing);
    expect(find.textContaining('Settings >'), findsNothing);
  });
}
