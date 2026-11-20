import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/rts_folder_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/screens/fbi_server_screen.dart';
import 'package:retro_toolbox/screens/fpkgi_server_screen.dart';
import 'package:retro_toolbox/screens/ftp_screen.dart';
import 'package:retro_toolbox/screens/jdkv_server_screen.dart';
import 'package:retro_toolbox/screens/rts_server_screen.dart';
import 'package:retro_toolbox/screens/smb_screen.dart';
import 'package:retro_toolbox/screens/tinfoil_server_screen.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kit/kit_support.dart';

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  String? getConsoleAuthToken(String consoleId) => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeApp(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeQueue extends StateNotifier<TaskQueueState> implements TaskQueueNotifier {
  _FakeQueue() : super(const TaskQueueState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Counts starts and stops, and runs as a real server would after either.
mixin _Counts {
  var starts = 0, stops = 0;
}

class _Tinfoil extends StateNotifier<TinfoilServerState> with _Counts implements TinfoilServerNotifier {
  _Tinfoil(super.state);
  @override
  Future<void> enable() async {
    starts++;
    state = state.copyWith(running: true, addresses: const ['10.0.0.2']);
  }

  @override
  Future<void> disable() async {
    stops++;
    state = state.copyWith(running: false);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Fbi extends StateNotifier<FbiServerState> with _Counts implements FbiServerNotifier {
  _Fbi(super.state);
  @override
  Future<void> enable() async {
    starts++;
    state = state.copyWith(running: true, addresses: const ['10.0.0.2']);
  }

  @override
  Future<void> disable() async {
    stops++;
    state = state.copyWith(running: false);
  }

  @override
  Future<void> refreshGames() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Fpkgi extends StateNotifier<FpkgiServerState> with _Counts implements FpkgiServerNotifier {
  _Fpkgi(super.state);
  @override
  Future<void> enable() async {
    starts++;
    state = state.copyWith(running: true, addresses: const ['10.0.0.2']);
  }

  @override
  Future<void> disable() async {
    stops++;
    state = state.copyWith(running: false);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Rts extends StateNotifier<RtsServerState> with _Counts implements RtsServerNotifier {
  _Rts(super.state);
  @override
  Future<void> enable() async {
    starts++;
    state = state.copyWith(running: true, addresses: const ['10.0.0.2']);
  }

  @override
  Future<void> disable() async {
    stops++;
    state = state.copyWith(running: false);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Jdkv extends StateNotifier<JdkvServerState> with _Counts implements JdkvServerNotifier {
  _Jdkv(super.state);
  @override
  Future<void> enable() async {
    starts++;
    state = state.copyWith(running: true, addresses: const ['10.0.0.2']);
  }

  @override
  Future<void> disable() async {
    stops++;
    state = state.copyWith(running: false);
  }

  @override
  Future<void> loadHubRecipes() async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Ftp extends StateNotifier<FtpState> with _Counts implements FtpNotifier {
  _Ftp(super.state);
  var disconnects = 0;
  @override
  Future<void> startServer() async {
    starts++;
    state = state.copyWith(serverRunning: true, serverAddresses: const ['10.0.0.2']);
  }

  @override
  Future<void> stopServer() async {
    stops++;
    state = state.copyWith(serverRunning: false);
  }

  @override
  void setMode(FtpMode mode) => state = state.copyWith(mode: mode);
  @override
  Future<void> disconnect() async => disconnects++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Smb extends StateNotifier<SmbState> implements SmbNotifier {
  _Smb(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _ps4 = Console(id: 'ps4', name: 'PlayStation 4', urls: [], platform: 'ps4', originalFormat: ['.pkg']);
const _snes = RtsFolder(path: '/storage/emulated/0/ROMs/snes', name: 'SNES', formats: ['.sfc'], romsSubfolder: 'snes');

/// A server screen with its notifier, off ([running] false) or on with two
/// transfers.
typedef _Case = ({Widget screen, _Counts counts, List<Override> overrides});

_Case _tinfoil(bool on) {
  final n = _Tinfoil(TinfoilServerState(running: on, addresses: const ['10.0.0.2'], activeTransfers: on ? 2 : 0));
  return (screen: const TinfoilServerScreen(), counts: n, overrides: [tinfoilServerProvider.overrideWith((ref) => n)]);
}

_Case _fbi(bool on) {
  final n = _Fbi(FbiServerState(running: on, addresses: const ['10.0.0.2'], activeTransfers: on ? 2 : 0));
  return (screen: const FbiServerScreen(), counts: n, overrides: [fbiServerProvider.overrideWith((ref) => n)]);
}

_Case _fpkgi(bool on) {
  final n = _Fpkgi(FpkgiServerState(running: on, addresses: const ['10.0.0.2'], activeTransfers: on ? 2 : 0));
  return (screen: const FpkgiServerScreen(), counts: n, overrides: [fpkgiServerProvider.overrideWith((ref) => n)]);
}

_Case _rts(bool on) {
  final n = _Rts(RtsServerState(running: on, addresses: const ['10.0.0.2'], activeTransfers: on ? 2 : 0, folders: const [_snes]));
  return (screen: const RtsServerScreen(), counts: n, overrides: [rtsServerProvider.overrideWith((ref) => n)]);
}

_Case _jdkv(bool on) {
  final n = _Jdkv(JdkvServerState(running: on, addresses: const ['10.0.0.2'], activeTransfers: on ? 2 : 0, folder: '/storage/emulated/0/JKSV'));
  return (screen: const JdkvServerScreen(), counts: n, overrides: [jdkvServerProvider.overrideWith((ref) => n)]);
}

_Case _ftp(bool on) {
  final n = _Ftp(FtpState(mode: FtpMode.server, serverRunning: on, serverDir: '/storage/emulated/0/ROMs', serverAddresses: const ['10.0.0.2']));
  return (screen: const FtpScreen(), counts: n, overrides: [ftpProvider.overrideWith((ref) => n)]);
}

final _servers = <String, (_Case Function(bool), bool)>{
  // name: (case, counts transfers)
  'Tinfoil': (_tinfoil, true),
  'FBI': (_fbi, true),
  'FPKGi': (_fpkgi, true),
  'Retro Tools Server': (_rts, true),
  'JDKV': (_jdkv, true),
  'FTP server': (_ftp, false),
};

Future<void> _show(WidgetTester t, _Case c, {InputMode mode = InputMode.touch, (Size, double) device = odin2}) async {
  SharedPreferences.setMockInitialValues({});
  await pumpKit(t, c.screen, mode: mode, device: device, overrides: [
    settingsProvider.overrideWith((ref) => _FakeSettings()),
    appStateProvider.overrideWith((ref) => _FakeApp(const AppState(consoles: {'ps4': _ps4}))),
    taskQueueProvider.overrideWith((ref) => _FakeQueue()),
    ...c.overrides,
  ]);
  await t.pump();
}

Finder _bar(String key, String label) => find.descendant(of: find.byKey(ValueKey(key)), matching: find.textContaining(RegExp(label, caseSensitive: false)));

void main() {
  for (final MapEntry(key: name, value: (make, transfers)) in _servers.entries) {
    group(name, () {
      testWidgets('Start starts it and, running, stops it', (t) async {
        final off = make(false);
        await _show(t, off);
        expect(_bar('kit-primary', 'Start server'), findsOneWidget);
        await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
        await t.pump();
        await t.pump();
        expect(off.counts.starts, 1);
        expect(_bar('kit-primary', 'Stop server'), findsOneWidget, reason: 'the bar follows the server');
        await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
        await t.pump();
        expect(off.counts.stops, 1);
      });

      testWidgets('no floating button; the pill says On${transfers ? ' and the transfers' : ''}', (t) async {
        await _show(t, make(true));
        expect(find.byType(FloatingActionButton), findsNothing);
        final pill = find.byKey(const ValueKey('kit-server-pill'));
        expect(find.descendant(of: pill, matching: find.text(transfers ? 'On · 2 transfers' : 'On')), findsOneWidget);
      });

      testWidgets('the port is locked while it runs, with the reason, and open when off', (t) async {
        await _show(t, make(true));
        expect(find.widgetWithText(OptionAction, 'Port'), findsOneWidget);
        expect(find.descendant(of: find.widgetWithText(OptionAction, 'Port'), matching: find.text(lockedWhileRunning)), findsOneWidget);
        await _show(t, make(false));
        expect(find.text(lockedWhileRunning), findsNothing);
        expect(find.widgetWithText(OptionExpander, 'Port'), findsOneWidget);
      });
    });
  }

  testWidgets('Retro Tools Server: Add folder is in the bar, locked while it runs', (t) async {
    await _show(t, _rts(false));
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('kit-secondary'))).onPressed, isNotNull);
    expect(_bar('kit-secondary', 'Add folder'), findsOneWidget);
    await _show(t, _rts(true));
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('kit-secondary'))).onPressed, isNull);
    expect(find.text('Stop the server to change what is shared'), findsOneWidget);
    // The folder and the library toggle stay on the page, locked.
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text(lockedWhileRunning), findsNWidgets(3), reason: 'port, library toggle, folder');
  });

  testWidgets('FBI: Install a file is in the bar, only while the server runs', (t) async {
    await _show(t, _fbi(false));
    expect(_bar('kit-secondary', 'Install a file'), findsOneWidget);
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('kit-secondary'))).onPressed, isNull);
    await _show(t, _fbi(true));
    expect(t.widget<OutlinedButton>(find.byKey(const ValueKey('kit-secondary'))).onPressed, isNotNull);
  });

  testWidgets('JDKV: the step for a pull says tap on touch and A on a pad', (t) async {
    final c = _jdkv(true);
    await _show(t, c);
    expect(find.textContaining('then tap it under From the Switch'), findsOneWidget);
    final container = ProviderScope.containerOf(t.element(find.byType(JdkvServerScreen)));
    container.read(inputModeProvider.notifier).state = InputMode.gamepad;
    await t.pump();
    expect(find.textContaining('then press A on it under From the Switch'), findsOneWidget);
    expect(find.textContaining('tap it'), findsNothing);
  });

  testWidgets('JDKV: Start waits for a save folder, and the bar says so', (t) async {
    final n = _Jdkv(const JdkvServerState());
    await _show(t, (screen: const JdkvServerScreen(), counts: n, overrides: [jdkvServerProvider.overrideWith((ref) => n)]));
    expect(find.text('Choose the save exports folder first'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(n.starts, 0);
  });

  testWidgets('FTP client: connected, Upload here is the primary and Disconnect has a name', (t) async {
    final n = _Ftp(const FtpState(connected: true, host: '10.0.0.9'));
    await _show(t, (screen: const FtpScreen(), counts: n, overrides: [ftpProvider.overrideWith((ref) => n)]));
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(_bar('kit-primary', 'Upload here'), findsOneWidget);
    expect(find.text('Connected to 10.0.0.9'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    await t.pump();
    expect(n.disconnects, 1);
  });

  testWidgets('SMB: Upload here waits for a share, then is the primary', (t) async {
    final smb = _Smb(const SmbState(connected: true, host: '10.0.0.5'));
    final o = [smbProvider.overrideWith((ref) => smb)];
    await _show(t, (screen: const SmbScreen(), counts: _Ftp(const FtpState()), overrides: o));
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNull);
    expect(find.text('Open a share first'), findsOneWidget);
    smb.state = const SmbState(connected: true, host: '10.0.0.5', path: '/share');
    await t.pump();
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNotNull);
  });

  testWidgets('Tinfoil: a Switch source that needs a sign-in is the first panel, and Sign in opens it in a sheet', (t) async {
    const sw = Console(id: 'switch', name: 'Switch', urls: [], platform: 'switch', auth: {'auth_message': 'Paste your token'});
    final n = _Tinfoil(const TinfoilServerState());
    SharedPreferences.setMockInitialValues({});
    await pumpKit(t, const TinfoilServerScreen(), overrides: [
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      appStateProvider.overrideWith((ref) => _FakeApp(const AppState(consoles: {'switch': sw}))),
      tinfoilServerProvider.overrideWith((ref) => n),
    ]);
    await t.pump();
    final panel = find.byKey(const ValueKey('kit-status-missingRequirement'));
    expect(find.descendant(of: panel, matching: find.text('Sign in to Switch to serve its games')), findsOneWidget);
    expect(t.getTopLeft(panel).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('kit-server-pill'))).dy), reason: 'above the address');
    await t.tap(find.text('Sign in'));
    await t.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Switch sign-in'), findsOneWidget);
  });
}
