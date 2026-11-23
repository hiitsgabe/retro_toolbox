import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hands out [config] when [gate] completes; [saved] records each write.
class GatedStore implements LaunchConfigStore {
  GatedStore(this.config);

  final LaunchConfig config;
  final gate = Completer<void>();
  final saved = <LaunchConfig>[];

  @override
  Future<LaunchConfig> load() async {
    await gate.future;
    return config;
  }

  @override
  Future<void> save(LaunchConfig config) async => saved.add(config);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _ra = DetectedEmulator(
  presetId: 'retroarch',
  variant: 'com.retroarch.aarch64',
  label: 'RetroArch Plus',
  systems: ['psx', 'snes'],
  version: '1.20',
  dataDir: '/data/user/0/com.retroarch.aarch64',
  requestsManage: true,
  pathAccess: true,
  manageGrant: true,
);

const _duck = LaunchChoice(presetId: 'duckstation', variant: 'com.github.stenzek.duckstation');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh config is off, has no defaults and has never detected', () {
    const c = LaunchConfig();
    expect((c.enabled, c.home, c.lastDetected), (false, false, null));
    expect(c.defaults, isEmpty);
  });

  test('a detection round-trips without its icon', () {
    final withIcon = DetectedEmulator(presetId: 'ra', variant: 'com.retroarch', label: 'RetroArch', systems: const ['psx'], icon: Uint8List.fromList([1]));
    expect(withIcon.toJson().containsKey('icon'), isFalse);
    final back = DetectedEmulator.fromJson(jsonDecode(jsonEncode(_ra.toJson())))!;
    expect((back.presetId, back.variant, back.label, back.version, back.dataDir), ('retroarch', 'com.retroarch.aarch64', 'RetroArch Plus', '1.20', _ra.dataDir));
    expect((back.requestsManage, back.pathAccess, back.manageGrant), (true, true, true));
    expect(back.systems, ['psx', 'snes']);
    expect(back.icon, isNull);
  });

  test('a desktop detection keeps its executable and prefix arguments', () {
    const flatpak = DetectedEmulator(presetId: 'ra', variant: 'org.libretro.RetroArch', label: 'RetroArch', systems: ['psx'], exe: 'flatpak', prefixArgs: ['run', 'org.libretro.RetroArch']);
    final back = DetectedEmulator.fromJson(jsonDecode(jsonEncode(flatpak.toJson())))!;
    expect((back.exe, back.pathAccess), ('flatpak', true));
    expect(back.prefixArgs, ['run', 'org.libretro.RetroArch']);
    final bare = DetectedEmulator.fromJson(const {'presetId': 'ra', 'variant': '/usr/bin/retroarch', 'label': 'RetroArch', 'systems': ['psx']})!;
    expect(bare.pathAccess, isTrue, reason: 'a missing pathAccess is the constructor default');
  });

  test('a config round-trips through JSON', () {
    const c = LaunchConfig(enabled: true, home: true, defaults: {'sony-psx': _duck}, lastDetected: [_ra]);
    final back = LaunchConfig.fromJson(jsonDecode(jsonEncode(c.toJson())));
    expect((back.enabled, back.home), (true, true));
    expect(back.defaults, {'sony-psx': _duck});
    expect([for (final d in back.lastDetected!) d.toJson()], [_ra.toJson()]);
  });

  test('a bad default or detection is left out, and junk is the default config', () {
    final back = LaunchConfig.fromJson({
      'enabled': true,
      'defaults': {'sony-psx': _duck.toJson(), 'nintendo-snes': {'presetId': 7}},
      'lastDetected': [_ra.toJson(), {'presetId': 'x'}, 'junk'],
    });
    expect(back.defaults, {'sony-psx': _duck});
    expect([for (final d in back.lastDetected!) d.presetId], ['retroarch']);
    expect(LaunchConfig.fromJson('junk').enabled, isFalse);
    expect(LaunchConfig.fromJson(const {'enabled': true}).lastDetected, isNull, reason: 'never detected stays apart from detected nothing');
  });

  group('LaunchConfigStore', () {
    test('saves under launcher_config_v1 and loads it back', () async {
      SharedPreferences.setMockInitialValues({});
      await LaunchConfigStore().save(const LaunchConfig(enabled: true, defaults: {'sony-psx': _duck}));
      final raw = (await SharedPreferences.getInstance()).getString('launcher_config_v1');
      expect(jsonDecode(raw!)['enabled'], isTrue);
      final loaded = await LaunchConfigStore().load();
      expect(loaded.enabled, isTrue);
      expect(loaded.defaults, {'sony-psx': _duck});
    });

    test('an unreadable value or a failing store is the default config', () async {
      SharedPreferences.setMockInitialValues({'launcher_config_v1': '{not json'});
      expect((await LaunchConfigStore().load()).enabled, isFalse);
      expect((await LaunchConfigStore(prefs: () => Future.error(StateError('no prefs'))).load()).enabled, isFalse);
    });
  });

  group('LaunchConfigNotifier', () {
    test('loads the saved config', () async {
      final store = GatedStore(const LaunchConfig(enabled: true, defaults: {'sony-psx': _duck}));
      final n = LaunchConfigNotifier(store);
      addTearDown(n.dispose);
      store.gate.complete();
      await n.loaded;
      expect(n.state.enabled, isTrue);
      expect(n.state.defaults, {'sony-psx': _duck});
    });

    test('a change made while loading lands over the saved config, not under it', () async {
      final store = GatedStore(const LaunchConfig(defaults: {'sony-psx': _duck}));
      final n = LaunchConfigNotifier(store);
      addTearDown(n.dispose);
      final change = n.setEnabled(true);
      store.gate.complete();
      await change;
      expect(n.state.enabled, isTrue);
      expect(n.state.defaults, {'sony-psx': _duck});
      expect(store.saved.single.enabled, isTrue);
    });

    test('setDefault sets and drops one console, and finishSetup merges and turns the mode on', () async {
      const ra = LaunchChoice(presetId: 'retroarch', variant: 'com.retroarch', core: 'snes9x');
      final store = GatedStore(const LaunchConfig(defaults: {'sony-psx': _duck}))..gate.complete();
      final n = LaunchConfigNotifier(store);
      addTearDown(n.dispose);
      await n.setDefault('nintendo-snes', ra);
      expect(n.state.defaults, {'sony-psx': _duck, 'nintendo-snes': ra});
      await n.setDefault('sony-psx', null);
      expect(n.state.defaults, {'nintendo-snes': ra});
      await n.finishSetup({'sony-psx': _duck});
      expect(n.state.enabled, isTrue);
      expect(n.state.defaults, {'nintendo-snes': ra, 'sony-psx': _duck});
      expect(store.saved, hasLength(3));
    });

    test('setDetected keeps the icons in memory', () async {
      final store = GatedStore(const LaunchConfig())..gate.complete();
      final n = LaunchConfigNotifier(store);
      addTearDown(n.dispose);
      final icon = Uint8List.fromList([9]);
      await n.setDetected([DetectedEmulator(presetId: 'ra', variant: 'com.retroarch', label: 'RetroArch', systems: const ['psx'], icon: icon)]);
      expect(n.state.lastDetected!.single.icon, icon);
    });
  });

  test('launchConfigProvider reads the saved config', () async {
    SharedPreferences.setMockInitialValues({'launcher_config_v1': jsonEncode(const LaunchConfig(enabled: true).toJson())});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(launchConfigProvider.notifier).loaded;
    expect(c.read(launchConfigProvider).enabled, isTrue);
  });
}
