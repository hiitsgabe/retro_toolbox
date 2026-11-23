import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/screens/app_drawer_screen.dart';
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit/kit_support.dart';

/// The apps Android would list, in its order.
class FakeApps implements InstalledApps {
  FakeApps(this.apps);

  final List<({String package, AppInfo info})> apps;

  @override
  Future<List<({String package, AppInfo info})>> launchable() async => apps;

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

void main() {
  late OpeningChannel channel;

  Future<void> pump(WidgetTester t, List<({String package, AppInfo info})> apps) async {
    channel = OpeningChannel();
    await pumpKit(t, const AppDrawerScreen(), overrides: [
      installedAppsProvider.overrideWithValue(FakeApps(apps)),
      launcherChannelProvider.overrideWithValue(channel),
    ]);
    await t.pump();
  }

  testWidgets('the drawer shows each app by its name, and choosing one opens it', (t) async {
    await pump(t, const [
      (package: 'org.a', info: AppInfo('Alpha', null)),
      (package: 'org.b', info: AppInfo('Beta', null)),
    ]);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    await t.tap(find.text('Beta'));
    await t.pump();
    expect(channel.opened, ['org.b']);
  });

  testWidgets('with no other app, one line says so', (t) async {
    await pump(t, const []);
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('No other app to open'), findsOneWidget);
  });
}
