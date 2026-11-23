import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
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
/// set, and counts them.
class CountingDetector implements EmulatorDetector {
  CountingDetector(this.next);

  List<DetectedEmulator> next;
  Completer<void>? gate;
  int runs = 0;

  @override
  Future<List<DetectedEmulator>> detect(List<LaunchPreset> presets) async {
    runs++;
    await gate?.future;
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
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
    ProviderContainer container({Map<String, LaunchChoice> overrides = const {}, List<DetectedEmulator> detected = const []}) {
      final c = ProviderContainer(overrides: [
        launchOverridesProvider.overrideWith((ref) => LaunchOverridesNotifier(MemoryOverrides(overrides))),
        launcherSessionProvider.overrideWith((ref) async => LauncherSession(presets: const [], detected: detected)),
        gameSystemProvider.overrideWith((ref, consoleId) => (slug: 'psx', name: 'PlayStation')),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<LaunchChoice?> resolve(ProviderContainer c) async {
      c.listen(resolveChoiceProvider(_game), (_, __) {});
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
}
