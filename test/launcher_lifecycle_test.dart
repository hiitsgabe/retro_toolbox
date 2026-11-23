import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
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

/// Counts the library rescans asked of it.
class RescanCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  RescanCatalog() : super(const CatalogState());
  int rescans = 0;

  @override
  Future<void> rescanLibrary() async => rescans++;

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
  late RescanCatalog catalog;
  late int onDiskBuilds;

  Future<void> pump(WidgetTester t, {required bool enabled}) async {
    presets = CountingStore();
    detections = 0;
    catalog = RescanCatalog();
    onDiskBuilds = 0;
    await t.pumpWidget(ProviderScope(
      overrides: [
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(LaunchConfig(enabled: enabled)))),
        launchPresetStoreProvider.overrideWithValue(presets),
        detectEmulatorsProvider.overrideWithValue(() async {
          detections++;
          return const <DetectedEmulator>[];
        }),
        catalogProvider.overrideWith((ref) => catalog),
        gamesOnDiskProvider.overrideWith((ref, consoleId) async {
          onDiskBuilds++;
          return true;
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

  ProviderContainer container(WidgetTester t) => ProviderScope.containerOf(t.element(find.byType(LauncherLifecycle)));

  testWidgets('with launcher mode on, each resume reads the library again, and which consoles have games', (t) async {
    await pump(t, enabled: true);
    container(t).listen(gamesOnDiskProvider('psx'), (_, __) {});
    await t.pump();
    expect((catalog.rescans, onDiskBuilds), (0, 1), reason: 'the start uses what the catalog load reads');
    resume(t);
    await t.pump();
    expect((catalog.rescans, onDiskBuilds), (1, 2));
  });

  testWidgets('with launcher mode off, a resume reads nothing again', (t) async {
    await pump(t, enabled: false);
    resume(t);
    await t.pump();
    expect(catalog.rescans, 0);
  });

  testWidgets('turning launcher mode on reads the library again; turning it off does not', (t) async {
    await pump(t, enabled: false);
    await container(t).read(launchConfigProvider.notifier).setEnabled(true);
    await t.pump();
    expect(catalog.rescans, 1);
    await container(t).read(launchConfigProvider.notifier).setEnabled(false);
    await t.pump();
    expect(catalog.rescans, 1);
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
