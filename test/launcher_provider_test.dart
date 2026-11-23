import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_overrides.dart';
import 'package:retro_toolbox/services/launcher/launcher_gate.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';

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
      final c = container(overrides: {_game.gameId: override}, detected: [emu('ra', ['psx'])]);
      expect(await resolve(c), override);
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
}
