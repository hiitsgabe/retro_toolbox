import 'dart:async';

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
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

class FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  FakeApp(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Each console's library dir is `<root>/<id>`.
class DirSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  DirSettings(this.root) : super(const AppSettings());

  final String root;

  @override
  String getDownloadDir(String? consoleId) => '$root/$consoleId';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class MemoryConfig implements LaunchConfigStore {
  MemoryConfig([this.initial = const LaunchConfig()]);

  final LaunchConfig initial;
  final saved = <LaunchConfig>[];

  @override
  Future<LaunchConfig> load() async => initial;

  @override
  Future<void> save(LaunchConfig config) async => saved.add(config);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeDualScreen extends StateNotifier<DualScreenState> implements DualScreenNotifier {
  FakeDualScreen(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// [found] for the file presets, and every manual preset it is asked about,
/// as the native detect finds an installed package; [asked] keeps the
/// preset ids of each run.
class ManualDetector implements EmulatorDetector {
  ManualDetector(this.found);

  final List<DetectedEmulator> found;
  final asked = <List<String>>[];

  @override
  Future<List<DetectedEmulator>> detect(List<LaunchPreset> presets) async {
    asked.add([for (final p in presets) p.id]);
    return [
      for (final preset in presets)
        if (preset.id.startsWith('manual-'))
          DetectedEmulator(presetId: preset.id, variant: _variant(preset), label: preset.name, systems: preset.systems.keys.toList())
        else
          ...found.where((d) => d.presetId == preset.id),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The one package of a manual preset, or the one path its desktop block finds.
String _variant(LaunchPreset preset) =>
    preset.android?.packages.single ?? [preset.linux, preset.windows, preset.macos].whereType<DesktopBlock>().single.find.single.paths.single;

/// The recipe test and viewActivity as the native side answers for one
/// installed app: [fits] are the recipe ids whose activity it exports.
class FakeChannel implements LauncherChannel {
  Set<String> fits = const {};
  String? view;
  Completer<void>? gate;
  final detectCalls = <List<Map<String, Object?>>>[];
  final viewCalls = <String>[];

  @override
  Future<List<Map<String, Object?>>> detect(List<Map<String, Object?>> presets) async {
    detectCalls.add(presets);
    await gate?.future;
    return [
      for (final e in presets)
        if (fits.contains(e['id'])) {'id': e['id'], 'package': (e['packages'] as List).single},
    ];
  }

  @override
  Future<String?> viewActivity(String package) async {
    viewCalls.add(package);
    return view;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeInstalledApps implements InstalledApps {
  FakeInstalledApps(this.apps);

  final List<({String package, AppInfo info})> apps;

  @override
  Future<List<({String package, AppInfo info})>> launchable() async => apps;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

LaunchPreset preset(String id, String name, Map<String, Object?> systems, {bool verified = false, Map<String, Object?>? linux}) => LaunchPreset.fromJson({
      'id': id,
      'name': name,
      'verified': verified,
      'systems': systems,
      'android': {'packages': ['org.example.$id'], 'activity': 'org.example.$id.Main', 'action': 'android.intent.action.VIEW', 'rom': {'mode': 'provider'}},
      if (linux != null) 'linux': linux,
    });

final _presets = LaunchPresetFile(schema: 1, version: 1, presets: [
  preset('ra', 'RetroArch', {'psx': {'extensions': ['chd']}}, linux: {
    'find': [
      {'type': 'path', 'names': ['retroarch']},
    ],
    'args': ['{rom}'],
  }),
  preset('eden', 'Eden', {'switch': {'extensions': ['nsp']}}, verified: true),
  preset('melonds', 'melonDS', {'nds': {'extensions': ['nds']}}),
  preset('ds', 'DuckStation', {'psx': {'extensions': ['chd']}}, linux: {
    'find': [
      {'type': 'path', 'names': ['duckstation-qt']},
    ],
    'args': ['-batch', '{rom}'],
  }),
]);

const _ra = DetectedEmulator(presetId: 'ra', variant: 'org.example.ra', label: 'RetroArch', systems: ['psx'], version: '1.0');

const _apps = [
  (package: 'dev.igawa6.edenduo', info: AppInfo('Eden Duo', null)),
  (package: 'org.example.ra', info: AppInfo('RetroArch', null)),
  (package: 'com.example.notes', info: AppInfo('Notes', null)),
];

const _consoles = {
  'sony-psx': Console(id: 'sony-psx', name: 'PlayStation', urls: []),
  'nintendo-switch': Console(id: 'nintendo-switch', name: 'Switch', urls: []),
  'sega-saturn': Console(id: 'sega-saturn', name: 'Saturn', urls: []),
  'other': Console(id: 'other', name: 'No slug', urls: []),
};

const _slugs = {'sony-psx': 'psx', 'nintendo-switch': 'switch', 'sega-saturn': 'saturn'};

const _duoId = 'manual-dev.igawa6.edenduo';

void main() {
  late ManualDetector detector;
  late MemoryConfig config;
  late FakeChannel channel;
  late GlobalKey<NavigatorState> nav;

  Future<void> pump(
    WidgetTester t, {
    List<DetectedEmulator> detected = const [],
    String os = 'android',
    Set<String> onDisk = const {'sony-psx'},
    LaunchConfig saved = const LaunchConfig(),
    List<Override> extra = const [],
  }) async {
    detector = ManualDetector(detected);
    config = MemoryConfig(saved);
    channel = FakeChannel();
    nav = GlobalKey<NavigatorState>();
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => FakeApp(const AppState(consoles: _consoles))),
        settingsProvider.overrideWith((ref) => DirSettings('/storage/emulated/0/ROMs')),
        gamesOnDiskProvider.overrideWith((ref, id) async => onDisk.contains(id)),
        gameSystemProvider.overrideWith((ref, id) => (slug: _slugs[id], name: _consoles[id]?.name ?? id)),
        launchPresetsProvider.overrideWith((ref) async => _presets),
        emulatorDetectorProvider.overrideWithValue(detector),
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(config)),
        launcherOsProvider.overrideWithValue(os),
        primaryStorageRootProvider.overrideWith((ref) async => '/storage/emulated/0'),
        launcherChannelProvider.overrideWithValue(channel),
        homeRoleAvailableProvider.overrideWithValue(false),
        dualScreenProvider.overrideWith((ref) => FakeDualScreen(const DualScreenState())),
        installedAppsProvider.overrideWithValue(FakeInstalledApps(_apps)),
        ...extra,
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: const LauncherWizardScreen(),
      ),
    ));
    await t.pumpAndSettle();
  }

  bool nextEnabled(WidgetTester t) => t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed != null;

  Finder inSheet(String text) => find.descendant(of: find.byType(RowMenuSheet), matching: find.text(text));

  Future<void> tapAndSettle(WidgetTester t, Finder f) async {
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<void> pickApp(WidgetTester t, String package) async {
    await tapAndSettle(t, find.byKey(const ValueKey('launcher-add')));
    await tapAndSettle(t, find.byKey(ValueKey('launcher-app-$package')));
  }

  testWidgets('Add an emulator lists the launchable apps but the ones already detected', (t) async {
    await pump(t, detected: [_ra]);
    await tapAndSettle(t, find.byKey(const ValueKey('launcher-add')));
    expect(find.text('Pick the app that runs your games'), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-app-dev.igawa6.edenduo')), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-app-com.example.notes')), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-app-org.example.ra')), findsNothing, reason: 'RetroArch is already detected');
  });

  testWidgets('a picked app is tested against every Android recipe while Testing <label> shows', (t) async {
    await pump(t);
    channel.fits = {'eden'};
    channel.gate = Completer<void>();
    await tapAndSettle(t, find.byKey(const ValueKey('launcher-add')));
    await t.tap(find.byKey(const ValueKey('launcher-app-dev.igawa6.edenduo')));
    // The working bar never settles: pump frames instead of settling.
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Testing Eden Duo'), findsOneWidget);
    expect([for (final e in channel.detectCalls.single) e['id']], ['ra', 'eden', 'melonds', 'ds']);
    expect({for (final e in channel.detectCalls.single) ...(e['packages'] as List)}, {'dev.igawa6.edenduo'});
    channel.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Testing Eden Duo'), findsNothing);
    expect(inSheet('Opens like Eden'), findsOneWidget);
  });

  testWidgets('one fitting recipe still opens the menu, first and focused; picking it saves the emulator, detects again and lists it', (t) async {
    await pump(t);
    expect(nextEnabled(t), isFalse, reason: 'nothing detected yet');
    channel.fits = {'eden'};
    await pickApp(t, 'dev.igawa6.edenduo');
    expect(t.widget<InkWell>(find.ancestor(of: inSheet('Opens like Eden'), matching: find.byType(InkWell)).first).autofocus, isTrue);
    await tapAndSettle(t, inSheet('Opens like Eden'));
    final m = config.saved.last.manual.single;
    expect((m.variant, m.label, m.recipe, m.activity), ('dev.igawa6.edenduo', 'Eden Duo', 'eden', null));
    expect(m.systems, isEmpty);
    expect(detector.asked.last, contains(_duoId));
    expect(find.byKey(const ValueKey('launcher-found-$_duoId')), findsOneWidget);
    expect(nextEnabled(t), isTrue, reason: 'a manual emulator lets the step advance');
  });

  testWidgets('several fitting recipes are offered in file order, an unverified one tagged not tested', (t) async {
    await pump(t);
    channel.fits = {'melonds', 'ra'};
    await pickApp(t, 'dev.igawa6.edenduo');
    expect(t.getTopLeft(inSheet('Opens like RetroArch')).dy, lessThan(t.getTopLeft(inSheet('Opens like melonDS')).dy));
    expect(inSheet('not tested'), findsNWidgets(2));
    expect(inSheet('Opens like Eden'), findsNothing);
  });

  testWidgets('nothing fits: the step says so and nothing is saved', (t) async {
    await pump(t);
    await pickApp(t, 'dev.igawa6.edenduo');
    expect(find.byType(RowMenuSheet), findsNothing);
    expect(find.text('Eden Duo cannot be opened by Retro Toolbox.'), findsOneWidget);
    expect(config.saved.where((c) => c.manual.isNotEmpty), isEmpty);
  });

  testWidgets('Back on the app picker, or the menu closed, changes nothing', (t) async {
    await pump(t);
    channel.fits = {'eden'};
    await tapAndSettle(t, find.byKey(const ValueKey('launcher-add')));
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('launcher-app-dev.igawa6.edenduo')), findsNothing);
    expect(channel.detectCalls, isEmpty);
    await pickApp(t, 'dev.igawa6.edenduo');
    expect(find.byType(RowMenuSheet), findsOneWidget);
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.byType(RowMenuSheet), findsNothing);
    expect(config.saved.where((c) => c.manual.isNotEmpty), isEmpty);
    expect(detector.asked, hasLength(1), reason: 'only the arrival detection ran');
  });
}
