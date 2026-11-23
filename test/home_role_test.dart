import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/launcher/home_role.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';

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

/// Answers setHome(true) and isHomeHeld with [held], and records each
/// setHome.
class FakeHomeChannel implements LauncherChannel {
  FakeHomeChannel({this.held = false});

  bool held;
  final setHomeCalls = <bool>[];
  int heldChecks = 0;

  @override
  Future<bool> setHome(bool on) async {
    setHomeCalls.add(on);
    return on && held;
  }

  @override
  Future<bool> isHomeHeld() async {
    heldChecks++;
    return held;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the retro_toolbox/launcher channel, HOME methods', () {
    const channel = MethodChannel('retro_toolbox/launcher');
    late List<MethodCall> calls;

    void answer(Object? Function(MethodCall call) reply) {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return reply(call);
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    }

    test('isHomeHeld asks with no arguments and reads the answer; no answer is false', () async {
      answer((_) => true);
      expect(await const LauncherChannel().isHomeHeld(), isTrue);
      expect((calls.single.method, calls.single.arguments), ('isHomeHeld', null));
      answer((_) => null);
      expect(await const LauncherChannel().isHomeHeld(), isFalse);
    });

    test('setHome sends on, and reads whether Retro Toolbox is the home app', () async {
      answer((call) => (call.arguments as Map)['on']);
      expect(await const LauncherChannel().setHome(true), isTrue);
      expect(await const LauncherChannel().setHome(false), isFalse);
      expect([for (final c in calls) c.method], ['setHome', 'setHome']);
      expect([for (final c in calls) c.arguments], [
        {'on': true},
        {'on': false},
      ]);
    });

    test('with no platform side, or a native error, both answer false', () async {
      expect(await const LauncherChannel().isHomeHeld(), isFalse);
      expect(await const LauncherChannel().setHome(true), isFalse);
      answer((_) => throw PlatformException(code: 'x'));
      expect(await const LauncherChannel().isHomeHeld(), isFalse);
      expect(await const LauncherChannel().setHome(true), isFalse);
    });

    test('a Home press from Android runs the handler; none after it is cleared, and other calls never', () async {
      var presses = 0;
      Future<void> send(String method) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
            'retro_toolbox/launcher',
            const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
            (_) {},
          );
      const LauncherChannel().setHomeHandler(() => presses++);
      addTearDown(() => const LauncherChannel().setHomeHandler(null));
      await send('home');
      await send('other');
      expect(presses, 1);
      const LauncherChannel().setHomeHandler(null);
      await send('home');
      expect(presses, 1);
    });
  });

  group('HomeRole', () {
    late FakeHomeChannel channel;
    late MemoryConfig store;
    late LaunchConfigNotifier config;

    HomeRole role({bool held = false, bool home = false, bool available = true}) {
      channel = FakeHomeChannel(held: held);
      store = MemoryConfig(LaunchConfig(enabled: true, home: home));
      config = LaunchConfigNotifier(store);
      addTearDown(config.dispose);
      return HomeRole(channel: channel, config: config, available: available);
    }

    bool home() => store.saved.isEmpty ? store.initial.home : store.saved.last.home;

    test('turning on asks Android, and home follows its answer', () async {
      expect(await role(held: true).turnOn(), isTrue);
      expect(channel.setHomeCalls, [true]);
      expect(home(), isTrue);
    });

    test('a user who says no leaves home off', () async {
      expect(await role(held: false).turnOn(), isFalse);
      expect(home(), isFalse);
    });

    test('turning off gives the role up and clears home', () async {
      await role(held: true, home: true).turnOff();
      expect(channel.setHomeCalls, [false]);
      expect(home(), isFalse);
    });

    test('sync takes what Android says, both ways', () async {
      final r = role(held: false, home: true);
      await r.sync();
      expect(home(), isFalse, reason: 'another home app was picked in system Settings');
      channel.held = true;
      await r.sync();
      expect(home(), isTrue);
    });

    test('where it is not available nothing is asked, and nothing turns on', () async {
      final r = role(held: true, available: false);
      expect(await r.turnOn(), isFalse);
      await r.sync();
      await r.turnOff();
      expect(channel.setHomeCalls, isEmpty);
      expect(channel.heldChecks, 0);
      expect(home(), isFalse);
    });
  });

  test('home mode needs the role available, launcher mode on and home on', () async {
    for (final (available, enabled, home, expected) in [
      (true, true, true, true),
      (false, true, true, false),
      (true, false, true, false),
      (true, true, false, false),
    ]) {
      final c = ProviderContainer(overrides: [
        launcherAvailableProvider.overrideWithValue(true),
        homeRoleAvailableProvider.overrideWithValue(available),
        launchConfigProvider.overrideWith((ref) => LaunchConfigNotifier(MemoryConfig(LaunchConfig(enabled: enabled, home: home)))),
      ]);
      addTearDown(c.dispose);
      await c.read(launchConfigProvider.notifier).loaded;
      expect(c.read(homeModeProvider), expected, reason: '($available, $enabled, $home)');
    }
  });
}
