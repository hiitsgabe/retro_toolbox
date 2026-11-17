import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeGames extends StateNotifier<Map<String, GameState>> implements GameStateManager {
  _FakeGames() : super(const {});
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _channel = MethodChannel('retro_toolbox/dual_screen');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late int current;
  late List<Map<String, Object>> displays;
  late String? failOn;
  final containers = <ProviderContainer>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    current = 0;
    displays = [
      {'id': 0, 'isDefault': true, 'on': true},
      {'id': 4, 'isDefault': false, 'on': true},
    ];
    failOn = null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      if (call.method == failOn) throw PlatformException(code: 'boom');
      if (call.method == 'displays') return {'current': current, 'displays': displays};
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
  });

  DualScreenNotifier notifier({bool enabled = true}) {
    final c = ProviderContainer(overrides: [
      gameStateManagerProvider.overrideWith((ref) => _FakeGames()),
      dualScreenProvider.overrideWith((ref) => DualScreenNotifier(ref, channel: _channel, enabled: enabled)),
    ]);
    containers.add(c);
    return c.read(dualScreenProvider.notifier);
  }

  List<String> methods() => [for (final c in calls) c.method];

  test('the mode survives a new notifier', () async {
    await notifier().setMode(DualScreenMode.mainOnBottom);
    final next = notifier();
    expect(next.state.mode, DualScreenMode.off);
    await next.init();
    expect(next.state.mode, DualScreenMode.mainOnBottom);
  });

  test('an unknown saved mode reads as off', () async {
    SharedPreferences.setMockInitialValues({'dual_screen_mode': 'sideways'});
    final n = notifier();
    await n.init();
    expect(n.state.mode, DualScreenMode.off);
    expect(methods(), ['displays', 'closeCompanion']);
  });

  test('main on top with the app on 0 opens the companion on 4 and feeds it', () async {
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnTop);
    await pumpEventQueue();
    expect(methods(), ['displays', 'openCompanion', 'send']);
    expect(calls[1].arguments, {'displayId': 4});
    expect((calls[2].arguments as Map)['json'], contains('"mode":"tasks"'));
    expect(n.state.companionOpen, isTrue);
    expect(n.state.hasSecondDisplay, isTrue);
    expect(n.state.error, isNull);
  });

  test('main on bottom with the app on 0 moves the app to 4 and opens nothing', () async {
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnBottom);
    expect(methods(), ['displays', 'moveMain']);
    expect(calls[1].arguments, {'displayId': 4});
    expect(n.state.companionOpen, isFalse);
  });

  test('main on bottom with the app already on 4 opens the companion on 0', () async {
    current = 4;
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnBottom);
    await pumpEventQueue();
    expect(methods(), ['displays', 'openCompanion', 'send']);
    expect(calls[1].arguments, {'displayId': 0});
  });

  test('off closes the companion and still reports the second display', () async {
    final n = notifier();
    await n.setMode(DualScreenMode.off);
    expect(methods(), ['displays', 'closeCompanion']);
    expect(n.state.hasSecondDisplay, isTrue);
  });

  test('a second display that is off closes the companion and reports none', () async {
    displays = [
      displays.first,
      {'id': 4, 'isDefault': false, 'on': false}
    ];
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnTop);
    expect(methods(), ['displays', 'closeCompanion']);
    expect(n.state.hasSecondDisplay, isFalse);
  });

  test('a failing launch sets the error and closes, never throws', () async {
    failOn = 'openCompanion';
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnTop);
    expect(n.state.error, 'Second screen unavailable');
    expect(n.state.companionOpen, isFalse);
    expect(methods(), ['displays', 'openCompanion', 'closeCompanion']);

    failOn = null;
    await n.apply();
    expect(n.state.error, isNull);
    expect(n.state.companionOpen, isTrue);
  });

  test('a missing plugin is the same failure', () async {
    messenger.setMockMethodCallHandler(_channel, null);
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnTop);
    expect(n.state.error, 'Second screen unavailable');
  });

  test('disabled, nothing reaches the channel', () async {
    SharedPreferences.setMockInitialValues({'dual_screen_mode': 'mainOnTop'});
    final n = notifier(enabled: false);
    await n.init();
    await n.setMode(DualScreenMode.mainOnTop);
    await n.apply();
    n.onLifecycle(AppLifecycleState.paused);
    n.onLifecycle(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(calls, isEmpty);
    expect(n.state.hasSecondDisplay, isFalse);
    expect(n.state.mode, DualScreenMode.off);
  });

  test('paused, hidden and detached close; inactive does not; resumed applies', () async {
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnTop);
    await pumpEventQueue();
    calls.clear();
    n.onLifecycle(AppLifecycleState.inactive);
    await pumpEventQueue();
    expect(calls, isEmpty);
    for (final s in [AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.detached]) {
      n.onLifecycle(s);
      await pumpEventQueue();
      expect(methods(), ['closeCompanion'], reason: '$s');
      expect(n.state.companionOpen, isFalse);
      calls.clear();
    }
    n.onLifecycle(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(methods(), ['displays', 'openCompanion', 'send']);
  });

  test('applies never overlap and a second one runs once more after', () async {
    final n = notifier();
    await n.setMode(DualScreenMode.mainOnTop);
    await pumpEventQueue();
    calls.clear();
    var inFlight = 0, most = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      inFlight++;
      most = most > inFlight ? most : inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
      return call.method == 'displays' ? {'current': current, 'displays': displays} : null;
    });
    final first = n.apply();
    await Future<void>.delayed(const Duration(milliseconds: 1)); // first is now inside 'displays'
    await Future.wait([first, n.apply(), n.apply()]);
    expect(most, 1);
    expect(methods().where((m) => m == 'displays'), hasLength(2));
  });

  test('a display change applies after 300 ms of quiet', () async {
    final n = notifier();
    await n.init();
    calls.clear();
    Future<void> changed() =>
        messenger.handlePlatformMessage(_channel.name, const StandardMethodCodec().encodeMethodCall(const MethodCall('displaysChanged')), (_) {});
    await changed();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await changed();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(calls, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(methods(), ['displays', 'closeCompanion']);
  });
}
