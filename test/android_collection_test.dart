import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/screens/android_collection_screen.dart';
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit/kit_support.dart';

/// The apps Android would list, and what it can show of each package.
class FakeApps implements InstalledApps {
  FakeApps(this.apps);

  final List<({String package, AppInfo info})> apps;

  @override
  Future<List<({String package, AppInfo info})>> launchable() async => apps;

  @override
  Future<Map<String, AppInfo>> info(Iterable<String> packages) async => {
        for (final a in apps)
          if (packages.contains(a.package)) a.package: a.info,
      };

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class OpeningChannel implements LauncherChannel {
  final opened = <String>[];

  @override
  Future<bool> openApp(String package) async {
    opened.add(package);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class MemoryConfig implements LaunchConfigStore {
  MemoryConfig(this.initial);

  final LaunchConfig initial;
  final saved = <LaunchConfig>[];

  @override
  Future<LaunchConfig> load() async => initial;

  @override
  Future<void> save(LaunchConfig config) async => saved.add(config);

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _apps = [
  (package: 'org.alpha', info: AppInfo('Alpha', null)),
  (package: 'org.beta', info: AppInfo('Beta', null)),
  (package: 'org.gamma', info: AppInfo('Gamma', null)),
];

void main() {
  test('the shelves round-trip, in their order, and a bad entry is left out', () {
    const c = LaunchConfig(androidGames: ['org.b', 'org.a'], androidApps: ['org.c']);
    final back = LaunchConfig.fromJson(c.toJson());
    expect(back.collection(AndroidCollection.games), ['org.b', 'org.a']);
    expect(back.collection(AndroidCollection.apps), ['org.c']);
    expect(LaunchConfig.fromJson({'androidGames': ['org.a', 3, null]}).androidGames, ['org.a']);
    expect(const LaunchConfig().toJson().containsKey('androidGames'), isFalse);
  });

  late OpeningChannel channel;
  late MemoryConfig store;

  Future<void> pump(WidgetTester t, LaunchConfig saved, AndroidCollection kind) async {
    channel = OpeningChannel();
    store = MemoryConfig(saved);
    await pumpKit(t, AndroidCollectionScreen(kind: kind), overrides: [
      installedAppsProvider.overrideWithValue(FakeApps(_apps)),
      launcherChannelProvider.overrideWithValue(channel),
      launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(store)),
    ]);
    await t.pumpAndSettle();
  }

  testWidgets('a shelf shows its apps in its order, leaves out one not installed, and choosing one opens it', (t) async {
    await pump(t, const LaunchConfig(androidGames: ['org.gamma', 'org.gone', 'org.alpha']), AndroidCollection.games);
    expect(t.getTopLeft(find.text('Gamma')).dx, lessThan(t.getTopLeft(find.text('Alpha')).dx));
    expect(find.text('Beta'), findsNothing);
    await t.tap(find.text('Alpha'));
    await t.pump();
    expect(channel.opened, ['org.alpha']);
  });

  testWidgets('an empty shelf says so; Choose apps ticks apps and Save keeps them, the ones it had first', (t) async {
    await pump(t, const LaunchConfig(androidApps: ['org.gamma']), AndroidCollection.apps);
    await t.tap(find.byKey(const ValueKey('kit-secondary')));
    await t.pumpAndSettle();
    expect(find.byType(AndroidCollectionPickerScreen), findsOneWidget);
    await t.tap(find.text('Alpha'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kit-primary')));
    await t.pumpAndSettle();
    expect(store.saved.last.androidApps, ['org.gamma', 'org.alpha']);
    expect(find.text('Alpha'), findsOneWidget, reason: 'the shelf shows what was saved');

    await pump(t, const LaunchConfig(), AndroidCollection.apps);
    expect(find.byType(EmptyState), findsOneWidget);
  });
}
