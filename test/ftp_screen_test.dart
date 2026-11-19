import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/screens/ftp_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFtp extends StateNotifier<FtpState> implements FtpNotifier {
  _FakeFtp(super.s);
  @override
  void setMode(FtpMode mode) => state = state.copyWith(mode: mode);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<FtpMode> _openWith(WidgetTester t, FtpState s) async {
  SharedPreferences.setMockInitialValues({});
  await t.pumpWidget(ProviderScope(
    overrides: [ftpProvider.overrideWith((ref) => _FakeFtp(s))],
    child: const MaterialApp(home: FtpScreen()),
  ));
  await t.pump();
  return t.widget<SegmentedButton<FtpMode>>(find.byType(SegmentedButton<FtpMode>)).selected.single;
}

void main() {
  testWidgets('opens in Server mode when the server is running', (t) async {
    expect(await _openWith(t, const FtpState(serverRunning: true, serverDir: '/srv', serverAddresses: ['10.0.0.2'])), FtpMode.server);
    expect(find.text('/srv'), findsOneWidget, reason: 'the server view is shown');
  });

  testWidgets('opens in Client mode when the server is not running', (t) async {
    expect(await _openWith(t, const FtpState()), FtpMode.client);
  });
}
