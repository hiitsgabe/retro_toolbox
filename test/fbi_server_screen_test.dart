import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/screens/fbi_server_screen.dart';

class _FakeFbi extends StateNotifier<FbiServerState> implements FbiServerNotifier {
  _FakeFbi(super.state);
  void set(FbiServerState s) => state = s;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _openThenLeave(WidgetTester t, FbiServerState state) async {
  await t.pumpWidget(ProviderScope(
    overrides: [fbiServerProvider.overrideWith((ref) => _FakeFbi(state))],
    child: const MaterialApp(home: FbiServerScreen()),
  ));
  await t.pump();
  await t.pumpWidget(const SizedBox());
}

void main() {
  // The IP field is only built while the server runs, so leaving with it off
  // is the case that used to reach ref from dispose.
  testWidgets('leaving the screen with the server off throws nothing', (t) async {
    await _openThenLeave(t, const FbiServerState(threeDsIp: '10.0.0.7'));
    expect(t.takeException(), isNull);
  });

  testWidgets('leaving the screen with the server on throws nothing', (t) async {
    await _openThenLeave(t, const FbiServerState(running: true, threeDsIp: '10.0.0.7', addresses: ['10.0.0.2']));
    expect(t.takeException(), isNull);
  });

  // The address is typed in a sheet now; its field starts from the saved one.
  Future<void> openChange(WidgetTester t) async {
    await t.tap(find.text('Change'));
    await t.pumpAndSettle();
  }

  testWidgets('the IP field still starts from the saved 3DS address', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [fbiServerProvider.overrideWith((ref) => _FakeFbi(const FbiServerState(running: true, threeDsIp: '10.0.0.7', addresses: ['10.0.0.2'])))],
      child: const MaterialApp(home: FbiServerScreen()),
    ));
    await t.pump();
    expect(find.text('10.0.0.7'), findsOneWidget, reason: 'the hero shows the 3DS address');
    await openChange(t);
    expect(find.widgetWithText(TextField, '10.0.0.7'), findsOneWidget);
  });
  testWidgets('an IP saved before the server is switched on still fills the field', (t) async {
    final fbi = _FakeFbi(const FbiServerState());
    await t.pumpWidget(ProviderScope(
      overrides: [fbiServerProvider.overrideWith((ref) => fbi)],
      child: const MaterialApp(home: FbiServerScreen()),
    ));
    await t.pump();
    fbi.set(const FbiServerState(threeDsIp: '10.0.0.7'));
    await t.pump();
    fbi.set(const FbiServerState(running: true, threeDsIp: '10.0.0.7', addresses: ['10.0.0.2']));
    await t.pump();
    await openChange(t);
    expect(find.widgetWithText(TextField, '10.0.0.7'), findsOneWidget);
  });
}
