import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/screens/console_info_screen.dart';
import 'package:retro_toolbox/services/process_list.dart';
import 'package:retro_toolbox/services/system_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Reader extends SystemInfoReader {
  _Reader(this.snap);
  final SystemSnapshot snap;
  @override
  Future<SystemSnapshot> read() async => snap;
}

class _Procs extends ProcessList {
  _Procs(this.entries);
  final List<ProcessEntry> entries;
  final ended = <int>[];
  @override
  Future<List<ProcessEntry>> list() async => entries;
  @override
  Future<EndResult> end(int pid, {bool force = false}) async {
    ended.add(pid);
    return EndResult.ended;
  }
}

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'a', packageName: 'p', version: '1.0.0', buildNumber: '1', buildSignature: '');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => Directory.systemTemp.path);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));

  Future<void> pump(WidgetTester t, SystemSnapshot snap, {ProcessList? procs}) async {
    await t.binding.setSurfaceSize(const Size(640, 480));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: ConsoleInfoScreen(
          reader: _Reader(snap),
          processes: procs ?? _Procs(const []),
          mounts: () async => [(label: 'Internal', mount: '/', total: 8 << 30, free: 2 << 30)],
          addresses: () async => ['192.168.1.20'],
          ssid: () async => null,
        ),
      ),
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('shows device, battery and Advanced', (t) async {
    await pump(t, const SystemSnapshot(deviceName: 'Test Device', firmware: 'Knulli', battery: BatteryInfo(percent: 87, charging: true)));
    expect(find.text('Test Device'), findsOneWidget);
    expect(find.text('87%'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Advanced'), 200);
    expect(find.text('Advanced'), findsOneWidget);
  });

  testWidgets('all-null snapshot still renders', (t) async {
    await pump(t, const SystemSnapshot());
    expect(find.text('—'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('protected rows get a lock, others an end button with confirm', (t) async {
    final procs = _Procs(const [
      ProcessEntry(pid: 10, ppid: 1, name: 'gptokeyb', cmdline: '/usr/bin/gptokeyb -1 app', rssBytes: 4 << 20, protected: true),
      ProcessEntry(pid: 11, ppid: 1, name: 'tailscaled', cmdline: '/usr/sbin/tailscaled --state=mem:', rssBytes: 30 << 20, protected: false),
    ]);
    await pump(t, const SystemSnapshot(), procs: procs);
    await t.scrollUntilVisible(find.text('Advanced'), 200);
    await t.tap(find.text('Advanced'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('gptokeyb'), 200);

    final tailRow = find.ancestor(of: find.text('tailscaled'), matching: find.byType(ListTile));
    final gpRow = find.ancestor(of: find.text('gptokeyb'), matching: find.byType(ListTile));
    expect(find.descendant(of: tailRow, matching: find.widgetWithIcon(IconButton, Icons.close)), findsOneWidget);
    expect(find.descendant(of: gpRow, matching: find.byIcon(Icons.lock)), findsOneWidget);
    expect(find.descendant(of: gpRow, matching: find.byType(IconButton)), findsNothing);

    await t.tap(find.descendant(of: tailRow, matching: find.byIcon(Icons.close)));
    await t.pumpAndSettle();
    expect(find.text('End tailscaled?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(procs.ended, isEmpty);
  });

  testWidgets('d-pad steps through the cards to Advanced and opens it', (t) async {
    await pump(t, const SystemSnapshot(),
        procs: _Procs(const [ProcessEntry(pid: 11, ppid: 1, name: 'tailscaled', cmdline: 't', rssBytes: 1, protected: false)]));
    bool onAdvanced() => FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<ExpansionTile>() != null;
    var steps = 0;
    for (; steps < 8 && !onAdvanced(); steps++) {
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
    }
    expect(onAdvanced(), isTrue);
    expect(steps, greaterThan(2), reason: 'cards are focus stops on the way');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('tailscaled'), findsOneWidget);
  });

  test('readMounts merges paths on the same mount', () async {
    final dir = Directory.systemTemp.createTempSync('mounts');
    addTearDown(() => dir.deleteSync());
    final m = await readMounts([(label: 'A', path: dir.path), (label: 'B', path: dir.path), (label: 'Gone', path: '${dir.path}/missing')]);
    expect(m.map((e) => e.label), ['A']);
    expect(m.single.total, greaterThan(0));
    expect(m.single.free, inInclusiveRange(0, m.single.total));
  });
}
