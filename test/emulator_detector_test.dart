import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';

const _channel = MethodChannel('retro_toolbox/launcher');

LaunchPreset preset(String id, List<String> packages, {Map<String, Object?> systems = const {'psx': {'extensions': ['chd']}}}) => LaunchPreset.fromJson({
      'id': id,
      'name': 'Preset $id',
      'systems': systems,
      'android': {
        'packages': packages,
        'activity': 'org.example.$id.Main',
        'action': 'android.intent.action.MAIN',
        'rom': {'mode': 'saf'},
      },
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  group('pathAccess', () {
    test('MANAGE_EXTERNAL_STORAGE requested', () {
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 35, sdkInt: 34, requestsManage: true)), isTrue);
    });
    test('below API 29 READ_EXTERNAL_STORAGE is enough', () {
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 35, sdkInt: 28, requestsRead: true)), isTrue);
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 35, sdkInt: 28)), isFalse);
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 35, sdkInt: 29, requestsRead: true)), isFalse);
    });
    test('legacy storage: targetSdk 28 or below, or 29 with the legacy flag', () {
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 28, sdkInt: 34, requestsRead: true)), isTrue);
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 29, sdkInt: 34, requestsRead: true, legacyStorage: true)), isTrue);
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 29, sdkInt: 34, requestsRead: true)), isFalse);
    });
    test('a modern READ_EXTERNAL_STORAGE app, or none at all, gets the scoped mode', () {
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 30, sdkInt: 34, requestsRead: true, legacyStorage: true)), isFalse);
      expect(pathAccess(const AndroidPackageFacts(targetSdk: 35, sdkInt: 34)), isFalse);
    });
  });

  group('Android detection over the channel', () {
    test('sends id, packages and activity, and the first variant in preset order wins', () async {
      Object? sent;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        expect(call.method, 'detect');
        sent = call.arguments;
        return [
          {'id': 'ra', 'package': 'com.retroarch', 'label': 'RetroArch', 'versionName': '1.20', 'dataDir': '/data/user/0/com.retroarch', 'targetSdk': 34, 'sdkInt': 34},
          {'id': 'ra', 'package': 'com.retroarch.aarch64', 'label': 'RetroArch Plus', 'targetSdk': 28, 'sdkInt': 34, 'requestsRead': true, 'icon': Uint8List.fromList([1, 2])},
        ];
      });
      final found = await EmulatorDetector(os: 'android').detect([
        preset('ra', ['com.retroarch.aarch64', 'com.retroarch'], systems: {'psx': {'extensions': ['chd']}, 'snes': {'extensions': ['sfc']}}),
        preset('gone', ['org.example.gone']),
      ]);
      expect(sent, {
        'presets': [
          {'id': 'ra', 'packages': ['com.retroarch.aarch64', 'com.retroarch'], 'activity': 'org.example.ra.Main'},
          {'id': 'gone', 'packages': ['org.example.gone'], 'activity': 'org.example.gone.Main'},
        ],
      });
      final ra = found.single;
      expect(ra.presetId, 'ra');
      expect(ra.variant, 'com.retroarch.aarch64');
      expect(ra.label, 'RetroArch Plus');
      expect(ra.icon, [1, 2]);
      expect(ra.dataDir, isNull);
      expect(ra.pathAccess, isTrue);
      expect(ra.systems, ['psx', 'snes']);
      expect(ra.choice, const LaunchChoice(presetId: 'ra', variant: 'com.retroarch.aarch64'));
    });

    test('pathAccess and requestsManage come from the reported facts', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async => [
            {'id': 'a', 'package': 'org.example.a', 'targetSdk': 35, 'sdkInt': 35, 'requestsManage': true, 'dataDir': '/data/user/0/org.example.a'},
            {'id': 'b', 'package': 'org.example.b', 'targetSdk': 35, 'sdkInt': 35, 'requestsRead': true},
          ]);
      final found = await EmulatorDetector(os: 'android').detect([preset('a', ['org.example.a']), preset('b', ['org.example.b'])]);
      expect([for (final d in found) (d.presetId, d.pathAccess, d.requestsManage)], [('a', true, true), ('b', false, false)]);
      expect(found.first.dataDir, '/data/user/0/org.example.a');
    });

    test('no plugin (desktop, tests) detects nothing instead of throwing', () async {
      expect(await EmulatorDetector(os: 'android').detect([preset('a', ['org.example.a'])]), isEmpty);
    });
  });

  group('the launch reply', () {
    test('a code maps to its result, an unknown one to refused', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async => {'code': 'componentGone'});
      expect((await const LauncherChannel().launch(const {})).code, LaunchCode.componentGone);
      messenger.setMockMethodCallHandler(_channel, (call) async => {'code': 'refused', 'message': 'SecurityException: nope'});
      final refused = await const LauncherChannel().launch(const {});
      expect((refused.code, refused.message), (LaunchCode.refused, 'SecurityException: nope'));
      messenger.setMockMethodCallHandler(_channel, (call) async => {'code': 'exploded'});
      expect((await const LauncherChannel().launch(const {})).code, LaunchCode.refused);
    });

    test('no plugin is unsupported, a native error is refused', () async {
      expect((await const LauncherChannel().launch(const {})).code, LaunchCode.unsupported);
      messenger.setMockMethodCallHandler(_channel, (call) async => throw PlatformException(code: 'x', message: 'boom'));
      final r = await const LauncherChannel().launch(const {});
      expect((r.code, r.message), (LaunchCode.refused, 'boom'));
    });
  });

  test('every code has the message and fix the spec table gives it', () {
    String? text(LaunchResult r) => r.describe('RetroArch').text;
    LaunchFix fix(LaunchResult r) => r.describe('RetroArch').fix;
    expect(text(LaunchResult.ok), isNull);
    expect((text(const LaunchResult(LaunchCode.notInstalled)), fix(const LaunchResult(LaunchCode.notInstalled))), ('RetroArch is not installed anymore', LaunchFix.detectAgain));
    expect((text(const LaunchResult(LaunchCode.componentGone)), fix(const LaunchResult(LaunchCode.componentGone))), ('RetroArch changed in this version', LaunchFix.chooseAnother));
    expect(text(const LaunchResult(LaunchCode.romUnreadable)), 'Cannot read the file');
    expect((text(const LaunchResult(LaunchCode.romPrivate)), fix(const LaunchResult(LaunchCode.romPrivate))), ('Move your library out of Android/data', LaunchFix.chooseFolder));
    expect(text(const LaunchResult(LaunchCode.unsupportedFile, extension: 'zip')), 'RetroArch does not open .zip');
    expect(text(const LaunchResult(LaunchCode.unsupportedFile, core: 'swanstation')), 'RetroArch has no swanstation core');
    expect(text(const LaunchResult(LaunchCode.refused, message: 'ActivityNotFoundException')), 'ActivityNotFoundException');
    expect(text(const LaunchResult(LaunchCode.crashed, message: 'segfault')), 'RetroArch closed right away:\nsegfault');
  });

  test('a saved choice round-trips, and junk reads as null', () {
    const c = LaunchChoice(presetId: 'ra', variant: 'com.retroarch', core: 'snes9x');
    expect(LaunchChoice.fromJson(c.toJson()), c);
    expect(LaunchChoice.fromJson(const {'presetId': 'ra'}), isNull);
    expect(LaunchChoice.fromJson('ra'), isNull);
  });
}
