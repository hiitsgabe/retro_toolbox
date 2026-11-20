import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/browser_layout_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/smb_screen.dart';
import 'package:retro_toolbox/services/smb_service.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';

/// Records logins; [fail] makes every connect throw like a refused login.
class _FakeService extends SmbService {
  _FakeService({this.fail = false});
  final bool fail;
  final logins = <({String host, String username, String password, String domain})>[];

  @override
  Future<void> connect({required String host, required String username, required String password, String domain = ''}) async {
    logins.add((host: host, username: username, password: password, domain: domain));
    if (fail) throw Exception('Login refused');
  }

  @override
  Future<List<SmbFile>> list(String path) async => const [];

  @override
  Future<void> disconnect() async {}
}

/// A real notifier over [_FakeService], seeded as if a scan had found [hosts]
/// (and failed with [error], when given).
class _Scanned extends SmbNotifier {
  _Scanned(SmbService service, List<SmbHost> hosts, {String? error}) : super(service: service) {
    state = state.copyWith(discovered: hosts, error: error);
  }
}

class _FakeQueue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _FakeQueue() : super(const TaskQueueState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeExtraction extends StateNotifier<ExtractionState> implements ExtractionNotifier {
  _FakeExtraction() : super(const ExtractionState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, SmbNotifier notifier) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      smbProvider.overrideWith((ref) => notifier),
      taskQueueProvider.overrideWith((ref) => _FakeQueue()),
      extractionProvider.overrideWith((ref) => _FakeExtraction()),
      browserLayoutProvider.overrideWith((ref) => BrowserLayoutNotifier()..state = BrowserLayout.list),
    ],
    child: const MaterialApp(home: SmbScreen()),
  ));
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

const _nas = SmbHost(ip: '10.0.0.5', name: 'nas');

void main() {
  testWidgets('tapping a found host connects as guest when nothing is saved for it', (t) async {
    SharedPreferences.setMockInitialValues({'smb_host': '10.0.0.9', 'smb_user': 'other', 'smb_domain': 'X'});
    final service = _FakeService();
    await _pump(t, _Scanned(service, const [_nas]));

    await t.tap(find.text('nas'));
    await _settle(t);

    expect(service.logins, [(host: '10.0.0.5', username: '', password: '', domain: '')]);
    expect(find.text('Shares'), findsOneWidget, reason: 'the browser opened');
  });

  testWidgets('tapping a found host uses the saved user and domain for that host', (t) async {
    SharedPreferences.setMockInitialValues({'smb_host': '10.0.0.5', 'smb_user': 'gabe', 'smb_domain': 'WG'});
    final service = _FakeService();
    await _pump(t, _Scanned(service, const [_nas]));

    await t.tap(find.text('nas'));
    await _settle(t);

    expect(service.logins, [(host: '10.0.0.5', username: 'gabe', password: '', domain: 'WG')]);
  });

  /// The address sheet's field [label].
  TextField field(WidgetTester t, String label) =>
      t.widget<TextField>(find.descendant(of: find.widgetWithText(FieldSlot, label), matching: find.byType(TextField)));

  testWidgets('a refused login opens the address sheet with the host filled and the error', (t) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeService(fail: true);
    await _pump(t, _Scanned(service, const [_nas]));

    await t.tap(find.text('nas'));
    await _settle(t);

    expect(service.logins, hasLength(1));
    expect(find.text('Shares'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'the address sheet is up');
    expect(field(t, 'Host / IP').controller!.text, '10.0.0.5');
    expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    expect(find.textContaining('Login refused'), findsWidgets);
  });
  testWidgets('the error shows once, in the sheet, while the sheet is up', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(t, _Scanned(_FakeService(fail: true), const [_nas]));

    await t.tap(find.text('nas'));
    await _settle(t);

    expect(find.textContaining('Login refused'), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining('Login refused')), findsOneWidget);
  });

  testWidgets('the error shows once, under the list, when the sheet is closed', (t) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(t, _Scanned(_FakeService(), const [_nas], error: 'Scan failed'));

    expect(find.text('Scan failed'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    await t.tap(find.text('Enter address').first);
    await _settle(t);

    expect(find.text('Scan failed'), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Scan failed')), findsOneWidget);
  });

  testWidgets('Connect in the sheet logs in with what was typed and opens the browser', (t) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeService();
    await _pump(t, _Scanned(service, const []));

    await t.tap(find.text('Enter address').first);
    await _settle(t);
    await t.enterText(find.descendant(of: find.widgetWithText(FieldSlot, 'Host / IP'), matching: find.byType(TextField)), '10.0.0.8');
    await t.enterText(find.descendant(of: find.widgetWithText(FieldSlot, 'Username'), matching: find.byType(TextField)), 'gabe');
    await t.enterText(find.descendant(of: find.widgetWithText(FieldSlot, 'Password'), matching: find.byType(TextField)), 'pw');
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Connect'));
    await _settle(t);

    expect(service.logins, [(host: '10.0.0.8', username: 'gabe', password: 'pw', domain: '')]);
    expect(find.byType(BottomSheet), findsNothing, reason: 'the sheet closes once connected');
    expect(find.text('Shares'), findsOneWidget);
  });
}
