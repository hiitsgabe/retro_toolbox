import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_store.dart';
import 'package:retro_toolbox/widgets/launcher/launcher_lifecycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class CountingStore implements LaunchPresetStore {
  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late CountingStore presets;
  late int detections;

  Future<void> pump(WidgetTester t, {required bool enabled}) async {
    presets = CountingStore();
    detections = 0;
    await t.pumpWidget(ProviderScope(
      overrides: [
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(LaunchConfig(enabled: enabled)))),
        launchPresetStoreProvider.overrideWithValue(presets),
        detectEmulatorsProvider.overrideWithValue(() async {
          detections++;
          return const <DetectedEmulator>[];
        }),
      ],
      child: const LauncherLifecycle(child: SizedBox()),
    ));
    await t.pump();
  }

  void resume(WidgetTester t) {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('with launcher mode on, the app start refreshes the presets and each resume detects again', (t) async {
    await pump(t, enabled: true);
    expect(presets.refreshes, 1);
    expect(detections, 0, reason: 'the start uses the saved detection');
    resume(t);
    await t.pump();
    resume(t);
    await t.pump();
    expect(detections, 2);
    expect(presets.refreshes, 1, reason: 'the refresh is once a session');
  });

  testWidgets('with launcher mode off, neither happens', (t) async {
    await pump(t, enabled: false);
    resume(t);
    await t.pump();
    expect((presets.refreshes, detections), (0, 0));
  });

  for (final available in [true, false]) {
    testWidgets('the app runs the launcher lifecycle ${available ? 'where launching works' : 'nowhere else'}', (t) async {
      SharedPreferences.setMockInitialValues({'setup_wizard_seen': true});
      await t.pumpWidget(ProviderScope(
        overrides: [
          patchersProvider.overrideWith((ref) async => []),
          launcherAvailableProvider.overrideWithValue(available),
          launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(const LaunchConfig()))),
        ],
        child: const RetroToolboxApp(),
      ));
      await t.pump();
      expect(find.byType(LauncherLifecycle), available ? findsOneWidget : findsNothing);
    });
  }
}
