import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/update_provider.dart';
import 'package:retro_toolbox/services/update_service.dart';

Map<String, dynamic> releaseJson({String tag = 'v0.3.0', List<Map<String, dynamic>> assets = const []}) => {
      'tag_name': tag,
      'html_url': 'https://github.com/hiitsgabe/retro_toolbox/releases/tag/$tag',
      'body': '',
      'assets': assets
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('android installer', () {
    const channel = MethodChannel('retro_toolbox/updater');
    String? installer;
    setUp(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'installerPackage' ? installer : null,
        ));
    tearDown(() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

    final release = ReleaseInfo.fromJson(releaseJson(assets: [
      {'name': 'retro_toolbox_arm64.apk', 'browser_download_url': 'https://x/a.apk', 'size': 10, 'digest': 'sha256:ab'},
      {'name': 'retro_toolbox_arm32.apk', 'browser_download_url': 'https://x/b.apk', 'size': 10},
    ]));

    Future<UpdateState> check({Abi abi = Abi.androidArm64, ReleaseInfo? latest}) async {
      final n = UpdateNotifier(_Fetching(latest ?? release), handheld: false, os: 'android', abi: abi);
      await n.check('0.2.8');
      return n.state;
    }

    test('Play installs link out instead of downloading', () async {
      installer = playStoreInstaller;
      expect(await _Fetching(release).installerPackage(), playStoreInstaller);
      final s = await check();
      expect(s.phase, UpdatePhase.available);
      expect(s.asset, isNull);
    });

    test('sideloaded installs download the APK', () async {
      installer = 'com.google.android.packageinstaller';
      final s = await check();
      expect(s.phase, UpdatePhase.available);
      expect(s.asset?.name, 'retro_toolbox_arm64.apk');
    });

    test('an asset without a checksum is refused', () async {
      installer = null;
      final s = await check(abi: Abi.androidArm);
      expect(s.phase, UpdatePhase.error);
      expect(s.message, cantVerifyMessage);
    });

    test('an unreadable tag is an error, not "up to date"', () async {
      final s = await check(latest: ReleaseInfo.fromJson(releaseJson(tag: 'latest')));
      expect(s.phase, UpdatePhase.error);
      expect(s.message, contains("Can't read"));
    });
  });

  group('PortMaster install', () {
    final release = ReleaseInfo.fromJson(releaseJson(tag: 'v9.9.9'));

    test('a port.json in the port folder hands updates to PortMaster', () async {
      final root = Directory.systemTemp.createTempSync('pm_port');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/port.json').writeAsStringSync('{}');
      final service = _Fetching(release, portRoot: root.path);
      final n = UpdateNotifier(service, handheld: true, os: 'linux', abi: Abi.linuxArm64);
      expect(n.state.phase, UpdatePhase.portMaster);
      await n.checkOnOpen('0.1.0');
      await n.check('0.1.0');
      expect(n.state.phase, UpdatePhase.portMaster);
      expect(service.fetches, 0);
    });

    test('without port.json the handheld updater still checks', () async {
      final root = Directory.systemTemp.createTempSync('gh_port');
      addTearDown(() => root.deleteSync(recursive: true));
      final service = _Fetching(release, portRoot: root.path);
      final n = UpdateNotifier(service, handheld: true, os: 'linux', abi: Abi.linuxArm64);
      expect(n.state.phase, UpdatePhase.idle);
      await n.check('0.1.0');
      expect(service.fetches, 1);
    });
  });
}

/// Talks to the (mocked) platform channel; only the release fetch is faked.
class _Fetching extends UpdateService {
  _Fetching(this.release, {super.portRoot = '/nowhere'});
  final ReleaseInfo release;
  int fetches = 0;
  @override
  Future<ReleaseInfo> fetchLatest() async {
    fetches++;
    return release;
  }
}
