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

/// A real notifier over [_FakeService], seeded as if a scan had found [hosts].
class _Scanned extends SmbNotifier {
  _Scanned(SmbService service, List<SmbHost> hosts) : super(service: service) {
    state = state.copyWith(discovered: hosts);
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

  testWidgets('a refused login opens Advanced with the host filled and the error', (t) async {
    SharedPreferences.setMockInitialValues({});
    final service = _FakeService(fail: true);
    await _pump(t, _Scanned(service, const [_nas]));

    await t.tap(find.text('nas'));
    await _settle(t);

    expect(service.logins, hasLength(1));
    expect(find.text('Shares'), findsNothing);
    final host = t.widget<TextField>(find.widgetWithText(TextField, 'Host / IP'));
    expect(host.controller!.text, '10.0.0.5');
    expect(find.text('Connect'), findsOneWidget, reason: 'Advanced is open');
    expect(find.textContaining('Login refused'), findsWidgets);
  });
}
