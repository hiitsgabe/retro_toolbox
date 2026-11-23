import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/launcher_wizard_screen.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
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

class CountingDetector implements EmulatorDetector {
  CountingDetector(this.next);

  List<DetectedEmulator> next;
  int runs = 0;

  @override
  Future<List<DetectedEmulator>> detect(List<LaunchPreset> presets) async {
    runs++;
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeChannel implements LauncherChannel {
  final opened = <String>[];
  final allFiles = <String>[];

  @override
  Future<bool> openApp(String package) async {
    opened.add(package);
    return true;
  }

  @override
  Future<bool> openAllFilesAccess(String package) async {
    allFiles.add(package);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

LaunchPreset preset(String id, String name, Map<String, Object?> systems, Map<String, Object?> rom, {bool verified = false}) => LaunchPreset.fromJson({
      'id': id,
      'name': name,
      'verified': verified,
      'systems': systems,
      'android': {
        'packages': ['org.example.$id'],
        'activity': 'org.example.$id.Main',
        'action': 'android.intent.action.VIEW',
        'rom': rom,
        if (id == 'ra')
          'extras': [
            {'key': 'LIBRETRO', 'type': 'string', 'value': '{retroarch.core}'},
          ],
      },
    });

// RetroArch first, as the seed lists it.
final _presets = LaunchPresetFile(schema: 1, version: 1, presets: [
  preset('ra', 'RetroArch', {
    'psx': {'extensions': ['chd'], 'cores': ['swanstation', 'pcsx_rearmed']},
    'snes': {'extensions': ['sfc'], 'cores': ['snes9x']},
  }, {'mode': 'path', 'scopedMode': 'saf', 'extra': 'ROM'}),
  preset('ds', 'DuckStation', {'psx': {'extensions': ['chd']}}, {'mode': 'path', 'extra': 'bootPath'}, verified: true),
  preset('ppsspp', 'PPSSPP', {'psp': {'extensions': ['iso']}}, {'mode': 'saf'}),
  preset('melonds', 'melonDS', {'nds': {'extensions': ['nds']}}, {'mode': 'provider'}),
]);

DetectedEmulator emu(String id, String label, List<String> systems, {bool pathAccess = true, bool manageGrant = false}) =>
    DetectedEmulator(presetId: id, variant: 'org.example.$id', label: label, systems: systems, version: '1.0', pathAccess: pathAccess, manageGrant: manageGrant);

final _ra = emu('ra', 'RetroArch', ['psx', 'snes']);
final _ds = emu('ds', 'DuckStation', ['psx']);
final _ppsspp = emu('ppsspp', 'PPSSPP', ['psp']);

const _consoles = {
  'sony-psx': Console(id: 'sony-psx', name: 'PlayStation', urls: []),
  'nintendo-snes': Console(id: 'nintendo-snes', name: 'Super Nintendo', urls: []),
  'sony-psp': Console(id: 'sony-psp', name: 'PSP', urls: []),
  'sega-saturn': Console(id: 'sega-saturn', name: 'Saturn', urls: []),
};

const _slugs = {'sony-psx': 'psx', 'nintendo-snes': 'snes', 'sony-psp': 'psp', 'sega-saturn': 'saturn'};

void main() {
  late CountingDetector detector;
  late MemoryConfig config;
  late FakeChannel channel;
  late List<Object?> popped;

  Future<void> pump(
    WidgetTester t, {
    List<DetectedEmulator>? detected,
    Set<String> onDisk = const {'sony-psx', 'nintendo-snes'},
    String os = 'linux',
    String root = '/storage/emulated/0/ROMs',
    LaunchConfig saved = const LaunchConfig(),
  }) async {
    detector = CountingDetector(detected ?? [_ra, _ds]);
    config = MemoryConfig(saved);
    channel = FakeChannel();
    popped = [];
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [
        appStateProvider.overrideWith((ref) => FakeApp(const AppState(consoles: _consoles))),
        settingsProvider.overrideWith((ref) => DirSettings(root)),
        gamesOnDiskProvider.overrideWith((ref, id) async => onDisk.contains(id)),
        gameSystemProvider.overrideWith((ref, id) => (slug: _slugs[id], name: _consoles[id]?.name ?? id)),
        launchPresetsProvider.overrideWith((ref) async => _presets),
        emulatorDetectorProvider.overrideWithValue(detector),
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(config)),
        launcherOsProvider.overrideWithValue(os),
        primaryStorageRootProvider.overrideWith((ref) async => '/storage/emulated/0'),
        launcherChannelProvider.overrideWithValue(channel),
      ],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => popped.add(await Navigator.of(c).push(MaterialPageRoute<bool>(builder: (_) => const LauncherWizardScreen()))),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  Finder primaryButton() => find.byKey(const ValueKey('kit-primary'));
  bool nextEnabled(WidgetTester t) => t.widget<FilledButton>(primaryButton()).onPressed != null;

  Future<void> next(WidgetTester t) async {
    await t.tap(primaryButton());
    await t.pumpAndSettle();
  }

  Finder inSheet(String text) => find.descendant(of: find.byType(RowMenuSheet), matching: find.text(text));

  String? valueOf(WidgetTester t, String key) => t.widget<OptionAction>(find.byKey(ValueKey(key))).value;

  testWidgets('Emulators detects on arrival, saves the detection and lists it with the not tested tag', (t) async {
    // A saved detection that misses RetroArch: only the arrival's own detection can list it.
    await pump(t, saved: LaunchConfig(lastDetected: [_ds]));
    expect(find.text('Step 1 of 3 · Emulators'), findsOneWidget);
    expect(detector.runs, 1);
    expect([for (final d in config.saved.last.lastDetected!) d.presetId], ['ra', 'ds']);
    expect(find.byKey(const ValueKey('launcher-found-ra')), findsOneWidget);
    expect(find.text('1.0 · not tested'), findsOneWidget, reason: 'RetroArch is unverified, DuckStation verified');
    expect(find.text('1.0'), findsOneWidget);
    expect(nextEnabled(t), isTrue);
    await t.tap(find.text('Detect again'));
    await t.pumpAndSettle();
    expect(detector.runs, 2);
  });

  testWidgets('nothing found: three emulators to install for the systems on disk, and Next stays off', (t) async {
    await pump(t, os: 'android', detected: const [], onDisk: {'sony-psx', 'nintendo-snes', 'sony-psp'});
    // RetroArch opens two of them, the other two one each: the file's order breaks the tie.
    expect(find.text('No emulator found. Install RetroArch, DuckStation or PPSSPP, then Detect again.'), findsOneWidget);
    expect(nextEnabled(t), isFalse);
  });

  testWidgets('Cancel on the first step leaves and saves no choice', (t) async {
    await pump(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(LauncherWizardScreen), findsNothing);
    expect(popped, [null]);
    expect(config.saved.every((c) => c.defaults.isEmpty && !c.enabled), isTrue, reason: 'only the detection was written');
  });

  testWidgets('Systems: one row per console with games, the first detected emulator preselected, No emulator found where none', (t) async {
    await pump(t, onDisk: {'sony-psx', 'nintendo-snes', 'sega-saturn'});
    await next(t);
    expect(find.text('Step 2 of 3 · Systems'), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-system-sony-psp')), findsNothing, reason: 'no games on disk');
    expect(valueOf(t, 'launcher-system-sony-psx'), 'RetroArch');
    expect(valueOf(t, 'launcher-system-nintendo-snes'), 'RetroArch');
    expect(valueOf(t, 'launcher-system-sega-saturn'), 'No emulator found');
    expect(t.widget<OptionAction>(find.byKey(const ValueKey('launcher-system-sega-saturn'))).onTap, isNull);
    expect(valueOf(t, 'launcher-core-sony-psx'), 'swanstation');
  });

  testWidgets('Systems starts on the saved default', (t) async {
    await pump(t, saved: const LaunchConfig(defaults: {'sony-psx': LaunchChoice(presetId: 'ds', variant: 'org.example.ds')}));
    await next(t);
    expect(valueOf(t, 'launcher-system-sony-psx'), 'DuckStation');
    expect(find.byKey(const ValueKey('launcher-core-sony-psx')), findsNothing, reason: 'DuckStation has no cores');
  });

  testWidgets('Systems lets nothing through while its consoles have games and no row has an emulator', (t) async {
    await pump(t, detected: [emu('melonds', 'melonDS', ['nds'])]);
    await next(t);
    expect(valueOf(t, 'launcher-system-sony-psx'), 'No emulator found');
    expect(nextEnabled(t), isFalse);
  });

  testWidgets('no games on disk yet: Systems says so, and Finish turns the mode on with no defaults', (t) async {
    await pump(t, onDisk: const {});
    await next(t);
    expect(find.textContaining('No games in your library folders yet. Finish still turns launcher mode on'), findsOneWidget);
    expect(nextEnabled(t), isTrue);
    await next(t);
    expect(find.text('Step 3 of 3 · Done'), findsOneWidget);
    expect(find.text('No console set up yet.'), findsOneWidget);
    await next(t);
    expect(popped, [true]);
    expect(config.saved.last.enabled, isTrue);
    expect(config.saved.last.defaults, isEmpty);
  });

  testWidgets('another emulator and a core, then Finish saves the defaults, keeps the others and turns the mode on', (t) async {
    const kept = LaunchChoice(presetId: 'ra', variant: 'org.example.ra');
    await pump(t, saved: const LaunchConfig(defaults: {'sega-saturn': kept}));
    await next(t);
    await t.tap(find.byKey(const ValueKey('launcher-system-sony-psx')));
    await t.pumpAndSettle();
    await t.tap(inSheet('DuckStation'));
    await t.pumpAndSettle();
    expect(valueOf(t, 'launcher-system-sony-psx'), 'DuckStation');
    await t.tap(find.byKey(const ValueKey('launcher-system-sony-psx')));
    await t.pumpAndSettle();
    await t.tap(inSheet('RetroArch'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('launcher-core-sony-psx')));
    await t.pumpAndSettle();
    await t.tap(inSheet('pcsx_rearmed'));
    await t.pumpAndSettle();
    await next(t);
    expect(find.text('Step 3 of 3 · Done'), findsOneWidget, reason: 'no saf choice on the desktop');
    expect(find.text('RetroArch (pcsx_rearmed)'), findsOneWidget);
    expect(config.saved.where((c) => c.enabled), isEmpty, reason: 'nothing is saved before Finish');
    await next(t);
    expect(popped, [true]);
    final last = config.saved.last;
    expect(last.enabled, isTrue);
    expect(last.defaults, {
      'sega-saturn': kept,
      'sony-psx': const LaunchChoice(presetId: 'ra', variant: 'org.example.ra', core: 'pcsx_rearmed'),
      'nintendo-snes': const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'),
    });
  });

  testWidgets('Finish puts the pick over the saved default it started on', (t) async {
    await pump(t, onDisk: {'sony-psx'}, saved: const LaunchConfig(defaults: {'sony-psx': LaunchChoice(presetId: 'ds', variant: 'org.example.ds')}));
    await next(t);
    expect(valueOf(t, 'launcher-system-sony-psx'), 'DuckStation');
    await t.tap(find.byKey(const ValueKey('launcher-system-sony-psx')));
    await t.pumpAndSettle();
    await t.tap(inSheet('RetroArch'));
    await t.pumpAndSettle();
    await next(t);
    expect(find.text('Step 3 of 3 · Done'), findsOneWidget);
    await next(t);
    expect(popped, [true]);
    expect(config.saved.last.defaults['sony-psx'], const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'));
  });

  testWidgets('Android: a saf choice brings the Folder access step, with Open <emulator>', (t) async {
    await pump(t, os: 'android', detected: [_ra, _ds, _ppsspp], onDisk: {'sony-psx', 'sony-psp'});
    await next(t);
    expect(find.text('Step 2 of 4 · Systems'), findsOneWidget);
    await next(t);
    expect(find.text('Step 3 of 4 · Folder access'), findsOneWidget);
    expect(find.text('Inside PPSSPP, give access to /storage/emulated/0/ROMs/sony-psp'), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-folder-ra')), findsNothing, reason: 'RetroArch reaches paths here');
    await t.tap(find.text('Inside PPSSPP, give access to /storage/emulated/0/ROMs/sony-psp'));
    await t.pumpAndSettle();
    expect(channel.opened, ['org.example.ppsspp']);
    expect(t.widget<OptionToggle>(find.widgetWithText(OptionToggle, 'Done')).value, isFalse, reason: 'never ticked for the user');
    await next(t);
    expect(find.text('Step 4 of 4 · Done'), findsOneWidget);
  });

  testWidgets('Android: no saf choice, no Folder access step', (t) async {
    await pump(t, os: 'android', detected: [_ra, _ds], onDisk: {'sony-psx'});
    await next(t);
    expect(find.text('Step 2 of 3 · Systems'), findsOneWidget);
    await next(t);
    expect(find.text('Step 3 of 3 · Done'), findsOneWidget);
  });

  testWidgets('Android: the RetroArch core line, the Android/data warning and Allow all files access', (t) async {
    await pump(
      t,
      os: 'android',
      root: '/storage/emulated/0/Android/data/name.rafaismy.retrotoolbox/files',
      detected: [emu('ra', 'RetroArch', ['psx', 'snes'], manageGrant: true)],
      onDisk: {'sony-psx'},
    );
    await next(t);
    expect(find.text('If the screen stays black, install the swanstation core in RetroArch'), findsOneWidget);
    expect(find.text('Other apps cannot read this folder. Move your library out of Android/data'), findsOneWidget);
    await t.tap(find.text('Allow all files access for RetroArch'));
    await t.pumpAndSettle();
    expect(channel.allFiles, ['org.example.ra']);
  });

  testWidgets('desktop: no Android warning, core line or all files row', (t) async {
    await pump(t, root: '/storage/emulated/0/Android/data/x', detected: [emu('ra', 'RetroArch', ['psx'], manageGrant: true)], onDisk: {'sony-psx'});
    await next(t);
    expect(find.textContaining('install the swanstation core'), findsNothing);
    expect(find.textContaining('Android/data'), findsNothing);
    expect(find.textContaining('Allow all files access'), findsNothing);
  });
  testWidgets('desktop: a saf emulator brings no Folder access step', (t) async {
    await pump(t, detected: [_ppsspp], onDisk: {'sony-psp'});
    await next(t);
    expect(find.text('Step 2 of 3 · Systems'), findsOneWidget);
    expect(valueOf(t, 'launcher-system-sony-psp'), 'PPSSPP');
    await next(t);
    expect(find.text('Step 3 of 3 · Done'), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-folder-ppsspp')), findsNothing);
  });
}
