import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/launcher_wizard_screen.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/home_role.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/settings/launcher_setting.dart';
import 'package:retro_toolbox/widgets/settings/rows/switch_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';

/// Answers setHome(true) with [held] and records each call.
class FakeHomeChannel implements LauncherChannel {
  bool held = true;
  final setHomeCalls = <bool>[];

  @override
  Future<bool> setHome(bool on) async {
    setHomeCalls.add(on);
    return on && held;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeDualScreen extends StateNotifier<DualScreenState> implements DualScreenNotifier {
  FakeDualScreen(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  FakeApp(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class NoDirSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  NoDirSettings() : super(const AppSettings());

  @override
  String getDownloadDir(String? consoleId) => '';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class MemoryConfig implements LaunchConfigStore {
  MemoryConfig(this.initial);

  final LaunchConfig initial;

  @override
  Future<LaunchConfig> load() async => initial;

  @override
  Future<void> save(LaunchConfig config) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _session = LauncherSession(
  presets: [
    LaunchPreset.fromJson({
      'id': 'ra',
      'name': 'RetroArch',
      'systems': {
        'psx': {'extensions': ['chd'], 'cores': ['swanstation', 'pcsx_rearmed']},
      },
      'linux': {
        'find': [
          {'type': 'path', 'names': ['retroarch']},
        ],
        'args': ['-L', '{retroarch.core}', '{rom}'],
      },
    }),
    LaunchPreset.fromJson({
      'id': 'ds',
      'name': 'DuckStation',
      'systems': {
        'psx': {'extensions': ['chd']},
      },
    }),
  ],
  detected: const [
    DetectedEmulator(presetId: 'ra', variant: '/usr/bin/retroarch', label: 'RetroArch', systems: ['psx']),
    DetectedEmulator(presetId: 'ds', variant: '/usr/bin/duckstation', label: 'DuckStation', systems: ['psx']),
  ],
);

const _psx = Console(id: 'sony-psx', name: 'PlayStation', urls: []);

void main() {
  test('the card shows on Android and desktop, never on the handheld or the server', () {
    expect(showLauncherCard(isAndroid: true, isDesktop: false, handheld: false, server: false), isTrue);
    expect(showLauncherCard(isAndroid: false, isDesktop: true, handheld: false, server: false), isTrue);
    expect(showLauncherCard(isAndroid: false, isDesktop: true, handheld: true, server: false), isFalse);
    expect(showLauncherCard(isAndroid: false, isDesktop: true, handheld: false, server: true), isFalse);
    expect(showLauncherCard(isAndroid: false, isDesktop: false, handheld: false, server: false), isFalse);
  });

  late ProviderContainer c;

  Future<void> pump(WidgetTester t, LaunchConfig saved, {Widget? child, List<Override> overrides = const []}) async {
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    c = ProviderContainer(overrides: [
      launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(saved))),
      launcherSessionProvider.overrideWith((ref) async => _session),
      detectEmulatorsProvider.overrideWithValue(() async => _session.detected),
      appStateProvider.overrideWith((ref) => FakeApp(const AppState(consoles: {'sony-psx': _psx}))),
      settingsProvider.overrideWith((ref) => NoDirSettings()),
      gamesOnDiskProvider.overrideWith((ref, id) async => false),
      gameSystemProvider.overrideWith((ref, id) => (slug: 'psx', name: 'PlayStation')),
      ...overrides,
    ]);
    addTearDown(c.dispose);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (context, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(body: ListView(children: [child ?? const LauncherSetting()])),
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('turning the mode on with no console set up opens the wizard and turns nothing on', (t) async {
    await pump(t, const LaunchConfig());
    await t.tap(find.text('Launcher mode'));
    await t.pumpAndSettle();
    expect(find.byType(LauncherWizardScreen), findsOneWidget);
    expect(c.read(launchConfigProvider).enabled, isFalse);
  });

  testWidgets('with a console set up the switch turns the mode on and off', (t) async {
    await pump(t, const LaunchConfig(defaults: {'sony-psx': LaunchChoice(presetId: 'ds', variant: '/usr/bin/duckstation')}));
    await t.tap(find.text('Launcher mode'));
    await t.pumpAndSettle();
    expect(find.byType(LauncherWizardScreen), findsNothing);
    expect(c.read(launchConfigProvider).enabled, isTrue);
    await t.tap(find.text('Launcher mode'));
    await t.pumpAndSettle();
    expect(c.read(launchConfigProvider).enabled, isFalse);
  });

  // Finish turns the mode on with no defaults when no console has games on
  // disk, so off from that state must not detour through the wizard.
  testWidgets('turning the mode off with no console set up turns it off and opens no wizard', (t) async {
    await pump(t, const LaunchConfig(enabled: true));
    await t.tap(find.text('Launcher mode'));
    await t.pumpAndSettle();
    expect(find.byType(LauncherWizardScreen), findsNothing);
    expect(c.read(launchConfigProvider).enabled, isFalse);
  });

  testWidgets('Set up opens the wizard', (t) async {
    await pump(t, const LaunchConfig(enabled: true, defaults: {'sony-psx': LaunchChoice(presetId: 'ds', variant: '/usr/bin/duckstation')}));
    await t.tap(find.text('Set up'));
    await t.pumpAndSettle();
    expect(find.byType(LauncherWizardScreen), findsOneWidget);
  });

  testWidgets('the card lists no console; Consoles opens a page with each one\'s emulator and folder switch', (t) async {
    await pump(t, const LaunchConfig(enabled: true, defaults: {'sony-psx': LaunchChoice(presetId: 'ra', variant: '/usr/bin/retroarch', core: 'swanstation')}));
    expect(find.byKey(const ValueKey('default-emulator sony-psx')), findsNothing);
    expect(t.widget<SettingsValueRow>(find.byKey(const ValueKey('launcher-consoles'))).value, '1 set');
    await t.tap(find.text('Consoles'));
    await t.pumpAndSettle();
    expect(find.byType(LauncherConsolesPage), findsOneWidget);
    final row = t.widget<SettingsValueRow>(find.byKey(const ValueKey('default-emulator sony-psx')));
    expect((row.title, row.value), ('Emulator', 'RetroArch (swanstation)'));
    expect(t.widget<SettingsSwitchRow>(find.byKey(const ValueKey('folder-games sony-psx'))).value, isTrue);
    await t.tap(find.text('Folders are games'));
    await t.pumpAndSettle();
    expect(c.read(launchConfigProvider).noFolders, {'sony-psx'});
    expect(t.widget<SettingsSwitchRow>(find.byKey(const ValueKey('folder-games sony-psx'))).value, isFalse);
  });

  testWidgets('an emulator added by hand is listed on the page; a generic one offers Edit command, which saves the new one', (t) async {
    const viewer = ManualEmulator(variant: 'org.fork', label: 'Fork', recipe: ManualEmulator.generic, systems: ['psx'], activity: 'org.fork.Main');
    final added = <ManualEmulator>[];
    await pump(t, const LaunchConfig(enabled: true, manual: [viewer]), overrides: [
      addManualEmulatorProvider.overrideWithValue((m) async => added.add(m)),
      launcherOsProvider.overrideWithValue('android'),
    ]);
    await t.tap(find.text('Consoles'));
    await t.pumpAndSettle();
    expect(t.widget<SettingsValueRow>(find.byKey(ValueKey('launcher-manual ${viewer.id}'))).value, 'Just open the file');
    await t.tap(find.text('Fork'));
    await t.pumpAndSettle();
    await t.tap(find.text('Edit command'));
    await t.pumpAndSettle();
    expect(find.text('-n org.fork/org.fork.Main -a android.intent.action.VIEW -d {rom.uri}'), findsOneWidget);
    await t.enterText(find.byType(TextField), '-n org.fork/.Play -x');
    await t.pump();
    expect(find.text('Unknown option -x'), findsOneWidget);
    await t.enterText(find.byType(TextField), '-n org.fork/.Play -e path {rom.path}');
    await t.pump();
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await t.pumpAndSettle();
    expect(added.single.command, '-n org.fork/.Play -e path {rom.path}');
  });

  testWidgets('the default row offers each emulator, RetroArch once per core, and None', (t) async {
    await pump(t, const LaunchConfig(enabled: true), child: const DefaultEmulatorRow(console: _psx));
    expect(t.widget<SettingsValueRow>(find.byType(SettingsValueRow)).value, 'None');
    await t.tap(find.text('Default emulator'));
    await t.pumpAndSettle();
    final sheet = find.byType(RowMenuSheet);
    for (final label in ['RetroArch (swanstation)', 'RetroArch (pcsx_rearmed)', 'DuckStation', 'None']) {
      expect(find.descendant(of: sheet, matching: find.text(label)), findsOneWidget, reason: label);
    }
    await t.tap(find.descendant(of: sheet, matching: find.text('RetroArch (pcsx_rearmed)')));
    await t.pumpAndSettle();
    expect(c.read(launchConfigProvider).defaults, {'sony-psx': const LaunchChoice(presetId: 'ra', variant: '/usr/bin/retroarch', core: 'pcsx_rearmed')});
    await t.tap(find.text('Default emulator'));
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(RowMenuSheet), matching: find.text('None')));
    await t.pumpAndSettle();
    expect(c.read(launchConfigProvider).defaults, isEmpty);
  });

  testWidgets('a default whose emulator is gone says so and is kept', (t) async {
    await pump(t, const LaunchConfig(enabled: true), child: const DefaultEmulatorRow(console: _psx));
    await c.read(launchConfigProvider.notifier).setDefault('sony-psx', const LaunchChoice(presetId: 'mednafen', variant: 'x'));
    await t.pumpAndSettle();
    expect(find.text('Not found on this device: Play uses another one'), findsOneWidget);
    expect(t.widget<SettingsValueRow>(find.byType(SettingsValueRow)).value, 'mednafen');
  });

  group('the home screen switch', () {
    late FakeHomeChannel channel;
    List<Override> homeOverrides({bool available = true, DualScreenMode dual = DualScreenMode.off}) {
      channel = FakeHomeChannel();
      return [
        homeRoleAvailableProvider.overrideWithValue(available),
        launcherChannelProvider.overrideWithValue(channel),
        dualScreenProvider.overrideWith((ref) => FakeDualScreen(DualScreenState(mode: dual))),
      ];
    }

    Finder homeRow() => find.widgetWithText(SettingsSwitchRow, homeSwitchTitle);

    testWidgets('with the mode on, it asks Android to make the app the home screen, and gives the role up', (t) async {
      await pump(t, const LaunchConfig(enabled: true), overrides: homeOverrides());
      expect(t.widget<SettingsSwitchRow>(homeRow()).value, isFalse);
      await t.tap(homeRow());
      await t.pumpAndSettle();
      expect(channel.setHomeCalls, [true]);
      expect(c.read(launchConfigProvider).home, isTrue);
      expect(t.widget<SettingsSwitchRow>(homeRow()).value, isTrue);
      await t.tap(homeRow());
      await t.pumpAndSettle();
      expect(channel.setHomeCalls, [true, false]);
      expect(c.read(launchConfigProvider).home, isFalse);
    });

    testWidgets('a user who says no leaves it off', (t) async {
      await pump(t, const LaunchConfig(enabled: true), overrides: homeOverrides());
      channel.held = false;
      await t.tap(homeRow());
      await t.pumpAndSettle();
      expect(t.widget<SettingsSwitchRow>(homeRow()).value, isFalse);
    });

    testWidgets('under dual screen Main on bottom it is shown, locked, with the reason', (t) async {
      await pump(t, const LaunchConfig(enabled: true), overrides: homeOverrides(dual: DualScreenMode.mainOnBottom));
      expect(t.widget<SettingsSwitchRow>(homeRow()).onChanged, isNull);
      expect(find.text(homeLockedReason), findsOneWidget);
      await t.tap(homeRow());
      await t.pumpAndSettle();
      expect(channel.setHomeCalls, isEmpty);
    });

    testWidgets('not with the mode off, nor where the app cannot be the home app', (t) async {
      await pump(t, const LaunchConfig(), overrides: homeOverrides());
      expect(homeRow(), findsNothing);
      await pump(t, const LaunchConfig(enabled: true), overrides: homeOverrides(available: false));
      expect(homeRow(), findsNothing);
    });
  });
}
