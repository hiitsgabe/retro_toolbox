import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/installed_apps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const native = MethodChannel('retrotoolbox/native');
  final icon = Uint8List.fromList([1, 2, 3]);
  late List<MethodCall> calls;

  void answer(Object? Function(MethodCall call) reply) {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, (call) async {
      calls.add(call);
      return reply(call);
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(native, null));
  }

  setUp(InstalledApps.clearCache);

  test('the launchable apps come by label, whatever case, a missing label read as the package', () async {
    answer((call) => [
          {'package': 'org.b', 'label': 'beta', 'icon': icon},
          {'package': 'org.a', 'label': 'Alpha'},
          {'package': 'org.none'},
          'junk',
        ]);
    final apps = await const InstalledApps().launchable();
    expect([for (final a in apps) (a.package, a.info.label)], [('org.a', 'Alpha'), ('org.b', 'beta'), ('org.none', 'org.none')]);
    expect(apps[1].info.icon, icon);
    expect([for (final c in calls) c.method], ['launchableApps']);
  });

  test('what launchable read is not asked again: info asks only for the packages it has not seen', () async {
    answer((call) => call.method == 'launchableApps'
        ? [
            {'package': 'org.a', 'label': 'Alpha'},
          ]
        : {
            'org.c': {'label': 'Gamma'},
          });
    final listed = await const InstalledApps().launchable();
    final info = await const InstalledApps().info(['org.a', 'org.c', 'org.gone']);
    expect(calls.last.method, 'appInfo');
    expect(calls.last.arguments, {
      'packages': ['org.c', 'org.gone'],
    });
    expect(info.keys, unorderedEquals(['org.a', 'org.c']), reason: 'a package Android did not answer for is left out');
    expect(identical(info['org.a'], listed.single.info), isTrue, reason: 'one instance, so its icon decodes once');
    calls.clear();
    await const InstalledApps().info(['org.gone']);
    expect(calls, isEmpty, reason: 'a package that answered nothing is remembered too');
  });

  test('with no platform side both answer empty, never an error', () async {
    expect(await const InstalledApps().launchable(), isEmpty);
    expect(await const InstalledApps().info(['org.a']), isEmpty);
  });

  test('a platform error answers empty too', () async {
    answer((call) => throw PlatformException(code: 'x'));
    expect(await const InstalledApps().launchable(), isEmpty);
    expect(await const InstalledApps().info(['org.a']), isEmpty);
  });
}
