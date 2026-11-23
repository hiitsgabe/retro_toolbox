import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/screens/console_grid_screen.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_store.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/widgets/launcher/launcher_lifecycle.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryConfig implements LaunchConfigStore {
  MemoryConfig(this.initial);

  final LaunchConfig initial;
  LaunchConfig? last;

  @override
  Future<LaunchConfig> load() async => initial;

  @override
  Future<void> save(LaunchConfig config) async => last = config;

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

/// Says Retro Toolbox is the home app when [held], records each setHome,
/// and keeps the Home press handler it was given.
class FakeHomeChannel implements LauncherChannel {
  bool held = false;
  final setHomeCalls = <bool>[];
  int heldChecks = 0;
  void Function()? onHome;

  @override
  Future<bool> isHomeHeld() async {
    heldChecks++;
    return held;
  }

  @override
  Future<bool> setHome(bool on) async {
    setHomeCalls.add(on);
    return on && held;
  }

  @override
  void setHomeHandler(void Function()? onHome) => this.onHome = onHome;

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
  late FakeHomeChannel channel;
  late MemoryConfig config;
  late int homePresses;

  Future<void> pump(WidgetTester t, {required bool enabled, bool home = false, bool homeRole = false}) async {
    presets = CountingStore();
    detections = 0;
    catalog = RescanCatalog();
    onDiskBuilds = 0;
    channel = FakeHomeChannel();
    config = MemoryConfig(LaunchConfig(enabled: enabled, home: home));
    homePresses = 0;
    await t.pumpWidget(ProviderScope(
      overrides: [
        homeRoleAvailableProvider.overrideWithValue(homeRole),
        launcherChannelProvider.overrideWithValue(channel),
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(config)),
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
      child: LauncherLifecycle(onHome: () => homePresses++, child: const SizedBox()),
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

  testWidgets('as a possible home app, the start and each resume take home from what Android says', (t) async {
    await pump(t, enabled: true, home: true, homeRole: true);
    expect(channel.heldChecks, 1);
    expect(config.last?.home, isFalse, reason: 'another home app was picked while the app was closed');
    channel.held = true;
    resume(t);
    await t.pump();
    expect(channel.heldChecks, 2);
    expect(config.last?.home, isTrue);
  });

  testWidgets('with launcher mode off a resume still takes home from Android', (t) async {
    await pump(t, enabled: false, homeRole: true);
    resume(t);
    await t.pump();
    expect(channel.heldChecks, 2);
  });

  testWidgets('launcher mode turning off gives the home role up', (t) async {
    await pump(t, enabled: true, homeRole: true);
    channel.held = true;
    await container(t).read(launchConfigProvider.notifier).setHome(true);
    await container(t).read(launchConfigProvider.notifier).setEnabled(false);
    await t.pump();
    expect(channel.setHomeCalls, [false]);
    expect(config.last?.home, isFalse);
  });

  testWidgets('a Home press runs onHome; once the lifecycle is gone, nothing listens', (t) async {
    await pump(t, enabled: true, homeRole: true);
    expect(channel.onHome, isNotNull);
    channel.onHome!();
    expect(homePresses, 1);
    await t.pumpWidget(const SizedBox());
    expect(channel.onHome, isNull);
  });

  testWidgets('where the app cannot be the home app, Android is never asked', (t) async {
    await pump(t, enabled: true);
    resume(t);
    await t.pump();
    await container(t).read(launchConfigProvider.notifier).setEnabled(false);
    await t.pump();
    expect(channel.heldChecks, 0);
    expect(channel.setHomeCalls, isEmpty);
    expect(channel.onHome, isNull);
  });

  testWidgets('in the app, a Home press opens the console list', (t) async {
    SharedPreferences.setMockInitialValues({'setup_wizard_seen': true});
    final channel = FakeHomeChannel();
    await t.pumpWidget(ProviderScope(
      overrides: [
        patchersProvider.overrideWith((ref) async => []),
        launcherAvailableProvider.overrideWithValue(true),
        homeRoleAvailableProvider.overrideWithValue(true),
        launcherChannelProvider.overrideWithValue(channel),
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(const LaunchConfig(enabled: true, home: true)))),
      ],
      child: const RetroToolboxApp(),
    ));
    await t.pump();
    expect(find.byType(ConsoleGridScreen), findsNothing);
    expect(channel.onHome, isNotNull);
    channel.onHome!();
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.byType(ConsoleGridScreen), findsOneWidget);
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
