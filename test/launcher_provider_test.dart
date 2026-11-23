import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launch_overrides.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_gate.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';

/// Keeps overrides in memory; [saved] records what would be written.
class MemoryOverrides implements LaunchOverridesStore {
  MemoryOverrides([this.initial = const {}]);

  final Map<String, LaunchChoice> initial;
  final saved = <Map<String, LaunchChoice>>[];

  @override
  Future<Map<String, LaunchChoice>> load() async => initial;

  @override
  void save(Map<String, LaunchChoice> overrides) => saved.add(overrides);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// The PlayStation's download dir is [dir]; no other console has one.
class DirSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  DirSettings(this.dir) : super(const AppSettings());

  final String dir;

  @override
  String getDownloadDir(String? consoleId) => consoleId == 'sony-psx' ? dir : '';

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Keeps the config in memory. Its load waits for [gate] when one is given.
class MemoryConfig implements LaunchConfigStore {
  MemoryConfig([this.initial = const LaunchConfig(), this.gate]);

  final LaunchConfig initial;
  final Completer<void>? gate;
  final saved = <LaunchConfig>[];

  @override
  Future<LaunchConfig> load() async {
    await gate?.future;
    return initial;
  }

  @override
  Future<void> save(LaunchConfig config) async => saved.add(config);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Answers every detection with [next], once [gate] completes when one is
/// set, counts them, and keeps the preset ids each one was asked about.
class CountingDetector implements EmulatorDetector {
  CountingDetector(this.next);

  List<DetectedEmulator> next;
  Completer<void>? gate;
  int runs = 0;
  final asked = <List<String>>[];

  @override
  Future<List<DetectedEmulator>> detect(List<LaunchPreset> presets) async {
    runs++;
    asked.add([for (final p in presets) p.id]);
    await gate?.future;
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeApp extends StateNotifier<AppState> implements AppStateNotifier {
  FakeApp(super.state);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// A detector as a device is: of [next] it finds only what it was asked
/// about, so a detection started before an add cannot find the new one.
class AskedOnlyDetector extends CountingDetector {
  AskedOnlyDetector(super.next);

  @override
  Future<List<DetectedEmulator>> detect(List<LaunchPreset> presets) async {
    final found = await super.detect(presets);
    final ids = {for (final p in presets) p.id};
    return [
      for (final d in found)
        if (ids.contains(d.presetId)) d,
    ];
  }
}

LaunchPreset _preset(String id, List<String> systems) => LaunchPreset.fromJson({
      'id': id,
      'name': id,
      'systems': {
        for (final s in systems) s: {'extensions': ['chd']},
      },
    });

/// The preset file in use. RetroArch opens the SNES here, which a detection
/// saved with an older file may not list.
final _file = LaunchPresetFile(schema: 1, version: 1, presets: [_preset('ra', ['psx', 'snes']), _preset('ds', ['psx']), _preset('melonds', ['nds'])]);

DetectedEmulator emu(String id, List<String> systems) => DetectedEmulator(presetId: id, variant: 'org.example.$id', label: id, systems: systems);

const _game = Game(title: 'Crash', url: 'https://example.com/psx/Crash.chd', size: 1, consoleId: 'sony-psx');

void main() {
  group('launcherSupported', () {
    test('Android and desktop are supported', () {
      expect(launcherSupported(isAndroid: true, isDesktop: false, handheld: false, server: false), isTrue);
      expect(launcherSupported(isAndroid: false, isDesktop: true, handheld: false, server: false), isTrue);
    });
    test('the PortMaster handheld and the Docker server are not, though both report Linux', () {
      expect(launcherSupported(isAndroid: false, isDesktop: true, handheld: true, server: false), isFalse);
      expect(launcherSupported(isAndroid: false, isDesktop: true, handheld: false, server: true), isFalse);
    });
    test('anything else (iOS, web) is not', () {
      expect(launcherSupported(isAndroid: false, isDesktop: false, handheld: false, server: false), isFalse);
    });
  });

  group('LaunchOverridesStore', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('rt-overrides-'));
    tearDown(() => tmp.delete(recursive: true));

    File file() => File('${tmp.path}/launcher/overrides.json');

    test('a burst of saves is one write after 300 ms, of the last state', () async {
      final store = LaunchOverridesStore(supportDir: () async => tmp);
      store.save({'a': const LaunchChoice(presetId: 'ra', variant: 'com.retroarch')});
      await Future<void>.delayed(const Duration(milliseconds: 150));
      store.save({'a': const LaunchChoice(presetId: 'ds', variant: 'com.github.stenzek.duckstation')});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(file().existsSync(), isFalse, reason: 'the second save restarted the wait');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(jsonDecode(file().readAsStringSync()), {
        'a': {'presetId': 'ds', 'variant': 'com.github.stenzek.duckstation'},
      });
    });

    test('load reads what was saved and skips a bad entry', () async {
      file()
        ..createSync(recursive: true)
        ..writeAsStringSync(jsonEncode({
          'psx/Crash.chd': {'presetId': 'ra', 'variant': 'com.retroarch', 'core': 'swanstation'},
          'psx/Bad.chd': {'presetId': 7},
        }));
      expect(await LaunchOverridesStore(supportDir: () async => tmp).load(), {
        'psx/Crash.chd': const LaunchChoice(presetId: 'ra', variant: 'com.retroarch', core: 'swanstation'),
      });
    });
  });

  group('resolveChoice', () {
    late MemoryConfig config;

    ProviderContainer container({
      Map<String, LaunchChoice> overrides = const {},
      Map<String, LaunchChoice> defaults = const {},
      List<DetectedEmulator> detected = const [],
    }) {
      config = MemoryConfig(LaunchConfig(defaults: defaults));
      final c = ProviderContainer(overrides: [
        launchOverridesProvider.overrideWith((ref) => LaunchOverridesNotifier(MemoryOverrides(overrides))),
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(config)),
        launcherSessionProvider.overrideWith((ref) async => LauncherSession(presets: const [], detected: detected)),
        gameSystemProvider.overrideWith((ref, consoleId) => (slug: 'psx', name: 'PlayStation')),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<LaunchChoice?> resolve(ProviderContainer c) async {
      c.listen(resolveChoiceProvider(_game), (_, __) {});
      await c.read(launchConfigProvider.notifier).loaded;
      await c.read(launcherSessionProvider.future);
      await Future<void>.delayed(Duration.zero);
      return c.read(resolveChoiceProvider(_game));
    }

    test('the per-game override comes first', () async {
      const override = LaunchChoice(presetId: 'ds', variant: 'com.github.stenzek.duckstation');
      final c = container(overrides: {_game.gameId: override}, detected: [emu('ra', ['psx']), emu('ds', ['psx'])]);
      expect(await resolve(c), override);
    });

    test('an override whose emulator is not detected falls through to the single covering one, and is kept', () async {
      const override = LaunchChoice(presetId: 'ds', variant: 'com.github.stenzek.duckstation');
      final c = container(overrides: {_game.gameId: override}, detected: [emu('ra', ['psx'])]);
      expect(await resolve(c), const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'));
      expect(c.read(launchOverridesProvider)[_game.gameId], override);
    });

    test('while detection runs the override is the choice', () async {
      const override = LaunchChoice(presetId: 'ds', variant: 'com.github.stenzek.duckstation');
      final c = ProviderContainer(overrides: [
        launchOverridesProvider.overrideWith((ref) => LaunchOverridesNotifier(MemoryOverrides({_game.gameId: override}))),
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig())),
        launcherSessionProvider.overrideWith((ref) => Completer<LauncherSession>().future),
        gameSystemProvider.overrideWith((ref, consoleId) => (slug: 'psx', name: 'PlayStation')),
      ]);
      addTearDown(c.dispose);
      c.listen(resolveChoiceProvider(_game), (_, __) {});
      await Future<void>.delayed(Duration.zero);
      expect(c.read(launcherSessionProvider).isLoading, isTrue);
      expect(c.read(resolveChoiceProvider(_game)), override);
    });

    test('with no override, the single detected emulator that covers the system', () async {
      final c = container(detected: [emu('ra', ['psx', 'snes']), emu('melonds', ['nds'])]);
      expect(await resolve(c), const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'));
    });

    test('with no override the console default comes before the single covering emulator', () async {
      final c = container(defaults: {'sony-psx': const LaunchChoice(presetId: 'ds', variant: 'org.example.ds')}, detected: [emu('ra', ['psx']), emu('ds', ['psx'])]);
      expect(await resolve(c), const LaunchChoice(presetId: 'ds', variant: 'org.example.ds'));
    });

    test('a default takes the variant detected now and keeps its core', () async {
      final c = container(defaults: {'sony-psx': const LaunchChoice(presetId: 'ra', variant: 'com.retroarch', core: 'swanstation')}, detected: [emu('ra', ['psx'])]);
      expect(await resolve(c), const LaunchChoice(presetId: 'ra', variant: 'org.example.ra', core: 'swanstation'));
    });

    test('the per-game override still beats the default', () async {
      const override = LaunchChoice(presetId: 'ra', variant: 'org.example.ra');
      final c = container(
        overrides: {_game.gameId: override},
        defaults: {'sony-psx': const LaunchChoice(presetId: 'ds', variant: 'org.example.ds')},
        detected: [emu('ra', ['psx']), emu('ds', ['psx'])],
      );
      expect(await resolve(c), override);
    });

    test('a default whose emulator is not detected is skipped, and kept', () async {
      const gone = LaunchChoice(presetId: 'ds', variant: 'org.example.ds');
      final c = container(defaults: {'sony-psx': gone}, detected: [emu('ra', ['psx'])]);
      expect(await resolve(c), const LaunchChoice(presetId: 'ra', variant: 'org.example.ra'));
      expect(c.read(launchConfigProvider).defaults, {'sony-psx': gone});
    });

    test("another console's default is not this game's", () async {
      final c = container(defaults: {'nintendo-snes': const LaunchChoice(presetId: 'ds', variant: 'org.example.ds')}, detected: [emu('ra', ['psx']), emu('ds', ['psx'])]);
      expect(await resolve(c), isNull);
    });

    test('two covering emulators and no override is no choice yet', () async {
      final c = container(detected: [emu('ra', ['psx']), emu('ds', ['psx'])]);
      expect(await resolve(c), isNull);
    });

    test('none covering is no choice', () async {
      final c = container(detected: [emu('melonds', ['nds'])]);
      expect(await resolve(c), isNull);
    });
  });

  group('ownedGameProvider', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('rt-owned-'));
    tearDown(() => tmp.delete(recursive: true));

    Future<OwnedGame?> owned(Game game) {
      final c = ProviderContainer(overrides: [settingsProvider.overrideWith((ref) => DirSettings(tmp.path))]);
      addTearDown(c.dispose);
      return c.read(ownedGameProvider(game).future);
    }

    void touch(String rel) => File(p.join(tmp.path, rel)).createSync(recursive: true);

    test('a downloaded file is its absolute path in the console dir', () async {
      touch('Crash.chd');
      final game = await owned(_game);
      expect(game?.dir, tmp.path);
      expect(game?.paths, [p.join(tmp.path, 'Crash.chd')]);
    });

    test('an extracted archive is the files of its folder, by path', () async {
      touch('Spyro/Spyro.cue');
      touch('Spyro/Spyro.bin');
      const zip = Game(title: 'Spyro', url: 'https://example.com/psx/Spyro.zip', size: 1, consoleId: 'sony-psx');
      expect((await owned(zip))?.paths, [p.join(tmp.path, 'Spyro', 'Spyro.bin'), p.join(tmp.path, 'Spyro', 'Spyro.cue')]);
    });

    test('a game not on disk has none', () async {
      touch('Other.chd');
      expect(await owned(_game), isNull);
    });
  });

  group('the detection cache', () {
    late CountingDetector detector;
    late MemoryConfig store;

    ProviderContainer container(LaunchConfig saved, {Completer<void>? gate}) {
      store = MemoryConfig(saved, gate);
      final c = ProviderContainer(overrides: [
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(store)),
        launchPresetsProvider.overrideWith((ref) async => _file),
        emulatorDetectorProvider.overrideWithValue(detector),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => detector = CountingDetector([emu('ra', ['psx'])]));

    test('a saved detection is the session, and nothing is detected', () async {
      final c = container(LaunchConfig(lastDetected: [emu('ds', ['psx'])]));
      final session = await c.read(launcherSessionProvider.future);
      expect([for (final d in session.detected) d.presetId], ['ds']);
      expect(detector.runs, 0);
    });

    test('a saved detection that loads late still wins over detecting', () async {
      final gate = Completer<void>();
      final c = container(LaunchConfig(lastDetected: [emu('ds', ['psx'])]), gate: gate);
      final session = c.read(launcherSessionProvider.future);
      await Future<void>.delayed(Duration.zero);
      gate.complete();
      expect([for (final d in (await session).detected) d.presetId], ['ds']);
      expect(detector.runs, 0);
    });

    test('with none saved the session detects once and saves what it found', () async {
      final c = container(const LaunchConfig());
      final session = await c.read(launcherSessionProvider.future);
      expect([for (final d in session.detected) d.presetId], ['ra']);
      expect([for (final d in c.read(launchConfigProvider).lastDetected!) d.presetId], ['ra']);
      expect(store.saved.last.lastDetected, hasLength(1));
      await c.read(launcherSessionProvider.future);
      expect(detector.runs, 1);
    });

    test('a detection already running is joined, not run twice', () async {
      final c = container(const LaunchConfig());
      detector.gate = Completer<void>();
      final session = c.read(launcherSessionProvider.future);
      await Future<void>.delayed(Duration.zero);
      final again = c.read(detectEmulatorsProvider)();
      detector.gate!.complete();
      await again;
      await session;
      expect(detector.runs, 1);
      detector.gate = null;
      await c.read(detectEmulatorsProvider)();
      expect(detector.runs, 2, reason: 'once it is over, the next one runs');
    });

    test('detecting again replaces the saved detection, and the session follows', () async {
      final c = container(LaunchConfig(lastDetected: [emu('ds', ['psx'])]));
      await c.read(launcherSessionProvider.future);
      detector.next = [emu('ra', ['psx']), emu('melonds', ['nds'])];
      await c.read(detectEmulatorsProvider)();
      final session = await c.read(launcherSessionProvider.future);
      expect([for (final d in session.detected) d.presetId], ['ra', 'melonds']);
      expect(detector.runs, 1);
    });

    test('a saved detection opens what its preset opens in the file in use, and keeps the rest', () async {
      final icon = Uint8List.fromList(const [1, 2, 3]);
      final c = container(LaunchConfig(lastDetected: [
        DetectedEmulator(
          presetId: 'ra',
          variant: 'org.example.ra',
          label: 'RetroArch',
          systems: const ['psx'],
          icon: icon,
          version: '1.19',
          dataDir: '/data/ra',
          requestsManage: true,
          pathAccess: false,
          manageGrant: true,
          exe: '/usr/bin/flatpak',
          prefixArgs: const ['run', 'org.example.ra'],
        ),
      ]));
      final session = await c.read(launcherSessionProvider.future);
      final ra = session.covering('snes').single;
      expect(ra.systems, ['psx', 'snes']);
      // Every launch after the first session reads this copy: a lost exe or dataDir is a dead Play.
      expect(
        (ra.variant, ra.label, ra.icon, ra.version, ra.dataDir, ra.requestsManage, ra.pathAccess, ra.manageGrant, ra.exe),
        ('org.example.ra', 'RetroArch', icon, '1.19', '/data/ra', true, false, true, '/usr/bin/flatpak'),
      );
      expect(ra.prefixArgs, ['run', 'org.example.ra']);
      expect(detector.runs, 0);
    });

    test('a saved detection whose preset left the file is dropped, and the rest follow the file order', () async {
      final c = container(LaunchConfig(lastDetected: [emu('ds', ['psx']), emu('gone', ['psx']), emu('ra', ['psx'])]));
      final session = await c.read(launcherSessionProvider.future);
      expect([for (final d in session.detected) d.presetId], ['ra', 'ds']);
    });
  });

  group('LaunchOverridesNotifier.dropPreset', () {
    const mine = LaunchChoice(presetId: 'manual-org.example.fork', variant: 'org.example.fork');
    const other = LaunchChoice(presetId: 'ds', variant: 'org.example.ds');

    test('drops every override that names the preset and saves the rest', () async {
      final store = MemoryOverrides({'psx/a.chd': mine, 'psx/b.chd': other, 'psx/c.chd': mine});
      final n = LaunchOverridesNotifier(store);
      addTearDown(n.dispose);
      await n.loaded;
      n.dropPreset(mine.presetId);
      expect(n.state, {'psx/b.chd': other});
      expect(store.saved.single, {'psx/b.chd': other});
    });

    test('with none naming it nothing is written', () async {
      final store = MemoryOverrides({'psx/b.chd': other});
      final n = LaunchOverridesNotifier(store);
      addTearDown(n.dispose);
      await n.loaded;
      n.dropPreset(mine.presetId);
      expect(n.state, {'psx/b.chd': other});
      expect(store.saved, isEmpty);
    });
  });

  group('manual emulators', () {
    LaunchPreset android(String id, List<String> systems) => LaunchPreset.fromJson({
          'id': id,
          'name': id,
          'systems': {
            for (final s in systems) s: {'extensions': ['chd']},
          },
          'android': {'packages': ['org.example.$id'], 'activity': 'org.example.$id.Main', 'action': 'android.intent.action.VIEW', 'rom': {'mode': 'provider'}},
        });
    final file = LaunchPresetFile(schema: 1, version: 1, presets: [android('ra', ['psx', 'snes']), android('ds', ['psx'])]);
    const fork = ManualEmulator(variant: 'org.example.fork', label: 'Fork', recipe: 'ds');

    late CountingDetector detector;
    late MemoryConfig store;
    late MemoryOverrides overrides;

    ProviderContainer container(LaunchConfig saved, {Map<String, LaunchChoice> games = const {}, Map<String, List<String>> extensions = const {}}) {
      store = MemoryConfig(saved);
      overrides = MemoryOverrides(games);
      final c = ProviderContainer(overrides: [
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(store)),
        launchOverridesProvider.overrideWith((ref) => LaunchOverridesNotifier(overrides)),
        launchPresetsProvider.overrideWith((ref) async => file),
        emulatorDetectorProvider.overrideWithValue(detector),
        launcherOsProvider.overrideWithValue('android'),
        consoleExtensionsProvider.overrideWithValue(extensions),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    setUp(() => detector = CountingDetector([emu('ds', ['psx'])]));

    test('the session lists a manual emulator after the file presets, and the detection is asked about it', () async {
      final c = container(const LaunchConfig(manual: [fork]));
      final session = await c.read(launcherSessionProvider.future);
      expect([for (final p in session.presets) p.id], ['ra', 'ds', fork.id]);
      expect(detector.asked.single, ['ra', 'ds', fork.id]);
      expect(session.preset(fork.id)!.android!.packages, ['org.example.fork']);
    });

    test('a saved detection of a manual emulator stays while it is configured, in preset order', () async {
      final c = container(LaunchConfig(manual: const [fork], lastDetected: [emu(fork.id, ['psx']), emu('ds', ['psx'])]));
      final session = await c.read(launcherSessionProvider.future);
      expect([for (final d in session.detected) d.presetId], ['ds', fork.id]);
      expect(detector.runs, 0);
    });

    test('adding one saves it, detects again and the session has it; removing it rebuilds the session without it', () async {
      final c = container(LaunchConfig(lastDetected: [emu('ds', ['psx'])]));
      expect([for (final p in (await c.read(launcherSessionProvider.future)).presets) p.id], ['ra', 'ds']);
      detector.next = [emu('ds', ['psx']), emu(fork.id, ['psx'])];
      await c.read(addManualEmulatorProvider)(fork);
      final added = await c.read(launcherSessionProvider.future);
      expect([for (final p in added.presets) p.id], ['ra', 'ds', fork.id]);
      expect(added.detectedFor(fork.id), isNotNull);
      expect(detector.asked.single, contains(fork.id), reason: 'the detection after the add knows the new preset');
      expect(store.saved.last.manual.single.id, fork.id);
      await c.read(removeManualEmulatorProvider)(fork.id);
      final removed = await c.read(launcherSessionProvider.future);
      expect([for (final p in removed.presets) p.id], ['ra', 'ds']);
      expect(removed.detectedFor(fork.id), isNull);
      expect(detector.runs, 1, reason: 'removing detects nothing');
    });

    test('an add while a detection runs waits for it, then detects again with the new preset', () async {
      detector = AskedOnlyDetector([emu('ds', ['psx']), emu(fork.id, ['psx'])]);
      final c = container(LaunchConfig(lastDetected: [emu('ds', ['psx'])]));
      await c.read(launcherSessionProvider.future);
      // What a resume in launcher mode starts, and the desktop file dialog's
      // focus coming back is a resume.
      detector.gate = Completer<void>();
      final resumed = c.read(detectEmulatorsProvider)();
      await pumpEventQueue();
      expect(detector.asked.single, ['ra', 'ds'], reason: 'the running detection read its presets before the add');
      final added = c.read(addManualEmulatorProvider)(fork);
      await pumpEventQueue();
      detector.gate!.complete();
      await resumed;
      await added;
      expect(detector.asked.last, contains(fork.id), reason: 'the add did not join the detection that predates it');
      expect((await c.read(launcherSessionProvider.future)).detectedFor(fork.id), isNotNull);
    });

    test('removing one drops the console defaults and the game overrides that name it, and keeps the rest', () async {
      final mine = LaunchChoice(presetId: fork.id, variant: 'org.example.fork');
      const other = LaunchChoice(presetId: 'ds', variant: 'org.example.ds');
      final c = container(
        LaunchConfig(manual: const [fork], defaults: {'sony-psx': mine, 'nintendo-snes': other}, lastDetected: const []),
        games: {'psx/a.chd': mine, 'psx/b.chd': other},
      );
      await c.read(removeManualEmulatorProvider)(fork.id);
      expect(c.read(launchConfigProvider).defaults, {'nintendo-snes': other});
      expect(c.read(launchOverridesProvider), {'psx/b.chd': other});
      expect(overrides.saved.last, {'psx/b.chd': other});
    });

    test('a generic one opens its ticked consoles with the catalog formats of each, and any file where none is known', () async {
      const viewer = ManualEmulator(variant: 'org.example.viewer', label: 'Viewer', recipe: ManualEmulator.generic, systems: ['psx', 'saturn'], activity: 'org.example.viewer.Open');
      final c = container(const LaunchConfig(manual: [viewer], lastDetected: []), extensions: {'psx': ['chd', 'cue']});
      final preset = (await c.read(launcherSessionProvider.future)).preset(viewer.id)!;
      expect(preset.systems['psx']!.extensions, ['chd', 'cue']);
      expect(preset.systems['saturn']!.extensions, isEmpty);
    });

    test('consoleExtensionsProvider: each art slug and the on-disk formats of its consoles, without the dot, merged', () {
      final c = ProviderContainer(overrides: [
        appStateProvider.overrideWith((ref) => FakeApp(const AppState(consoles: {
              'a': Console(id: 'a', name: 'PS one', urls: [], originalFormat: ['.zip'], gameFilesFormat: ['.CUE']),
              'b': Console(id: 'b', name: 'PS two', urls: [], gameFilesFormat: ['.pbp']),
              'c': Console(id: 'c', name: 'Unknown', urls: [], gameFilesFormat: ['.bin']),
            }))),
        gameSystemProvider.overrideWith((ref, id) => (slug: id == 'c' ? null : 'psx', name: id)),
      ]);
      addTearDown(c.dispose);
      // a: the zip it comes as, the cue inside, and the chd that Convert to CHD writes from a cue.
      expect(c.read(consoleExtensionsProvider), {'psx': ['chd', 'cue', 'pbp', 'zip']});
    });
  });
}
