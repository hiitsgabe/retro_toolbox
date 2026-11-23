import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/services/launcher/manual_recipes.dart';

const _channel = MethodChannel('retro_toolbox/launcher');

LaunchPreset android(String id) => LaunchPreset.fromJson({
      'id': id,
      'name': id,
      'systems': {
        'psx': {'extensions': ['chd']},
      },
      'android': {'packages': ['org.example.$id'], 'activity': 'org.example.$id.Main', 'action': 'android.intent.action.VIEW', 'rom': {'mode': 'provider'}},
    });

LaunchPreset desktop(String id, {List<Map<String, Object?>>? linux, List<Map<String, Object?>>? windows}) => LaunchPreset.fromJson({
      'id': id,
      'name': id,
      'systems': {
        'psx': {'extensions': ['chd']},
      },
      if (linux != null) 'linux': {'find': linux, 'args': ['{rom}']},
      if (windows != null) 'windows': {'find': windows, 'args': ['{rom}']},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  group('viewActivity', () {
    test('sends the package and passes the activity on', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return 'org.example.viewer.Open';
      });
      expect(await const LauncherChannel().viewActivity('org.example.viewer'), 'org.example.viewer.Open');
      expect(calls.single.method, 'viewActivity');
      expect(calls.single.arguments, {'package': 'org.example.viewer'});
    });

    test('no plugin, no activity, an answer that is not a name or a native error is null, never a throw', () async {
      expect(await const LauncherChannel().viewActivity('org.example.viewer'), isNull);
      messenger.setMockMethodCallHandler(_channel, (call) async => null);
      expect(await const LauncherChannel().viewActivity('org.example.viewer'), isNull);
      messenger.setMockMethodCallHandler(_channel, (call) async => 7);
      expect(await const LauncherChannel().viewActivity('org.example.viewer'), isNull);
      messenger.setMockMethodCallHandler(_channel, (call) async => throw PlatformException(code: 'x'));
      expect(await const LauncherChannel().viewActivity('org.example.viewer'), isNull);
    });
  });

  group('androidRecipesFor', () {
    final presets = [android('a'), desktop('d', linux: const [{'type': 'path', 'names': ['d']}]), android('b'), android('c')];

    test('asks detect about every Android recipe activity in the one package, and keeps the ones that came back, in file order', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(_channel, (call) async {
        calls.add(call);
        return [
          {'id': 'c', 'package': 'org.example.fork'},
          {'id': 'a', 'package': 'org.example.fork'},
        ];
      });
      final fit = await androidRecipesFor(const LauncherChannel(), presets, 'org.example.fork');
      expect(calls.single.method, 'detect');
      expect(calls.single.arguments, {
        'presets': [
          {'id': 'a', 'packages': ['org.example.fork'], 'activity': 'org.example.a.Main'},
          {'id': 'b', 'packages': ['org.example.fork'], 'activity': 'org.example.b.Main'},
          {'id': 'c', 'packages': ['org.example.fork'], 'activity': 'org.example.c.Main'},
        ],
      });
      expect([for (final r in fit) r.id], ['a', 'c']);
    });

    test('an answer about another package does not count', () async {
      messenger.setMockMethodCallHandler(_channel, (call) async => [
            {'id': 'a', 'package': 'org.example.a'},
          ]);
      expect(await androidRecipesFor(const LauncherChannel(), presets, 'org.example.fork'), isEmpty);
    });

    test('no plugin or a native error is no recipe', () async {
      expect(await androidRecipesFor(const LauncherChannel(), presets, 'org.example.fork'), isEmpty);
      messenger.setMockMethodCallHandler(_channel, (call) async => throw PlatformException(code: 'x'));
      expect(await androidRecipesFor(const LauncherChannel(), presets, 'org.example.fork'), isEmpty);
    });
  });

  group('desktopRecipesFor', () {
    final ra = desktop('ra', linux: const [{'type': 'path', 'names': ['retroarch']}], windows: const [{'type': 'static', 'paths': [r'%APPDATA%\RetroArch\retroarch.exe']}]);
    final duck = desktop('duck', linux: const [{'type': 'static', 'paths': ['~/Applications/DuckStation*.AppImage']}]);
    final pcsx2 = desktop('pcsx2', linux: const [{'type': 'path', 'names': ['pcsx2-qt']}], windows: const [{'type': 'path', 'names': ['pcsx2-qt.exe']}]);

    test('the recipes for this OS, the ones whose find rules name the file first, each group in file order', () {
      expect([for (final r in desktopRecipesFor([ra, android('eden'), duck, pcsx2], 'linux', '/home/me/Applications/DuckStation-x64.AppImage')) r.id], ['duck', 'ra', 'pcsx2']);
      expect([for (final r in desktopRecipesFor([ra, duck, pcsx2], 'linux', '/usr/local/bin/pcsx2-qt')) r.id], ['pcsx2', 'ra', 'duck']);
    });

    test('Windows paths match whatever their case', () {
      expect([for (final r in desktopRecipesFor([pcsx2, duck, ra], 'windows', r'D:\Emus\RetroArch.EXE')) r.id], ['ra', 'pcsx2']);
    });
  });

  group('executableFor', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('rt-manual-app-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    String bundle(String name, {String? exe}) {
      final app = p.join(tmp.path, '$name.app');
      Directory(app).createSync();
      if (exe != null) {
        File(p.join(app, 'Contents', 'Info.plist'))
          ..createSync(recursive: true)
          ..writeAsStringSync('<plist><dict><key>CFBundleExecutable</key>\n<string>$exe</string></dict></plist>');
        File(p.join(app, 'Contents', 'MacOS', exe)).createSync(recursive: true);
      }
      return app;
    }

    test('on macOS a picked .app is the binary its Info.plist names', () async {
      final app = bundle('Duck Fork', exe: 'DuckFork');
      expect(await executableFor(app, 'macos'), p.join(app, 'Contents', 'MacOS', 'DuckFork'));
    });

    test('a bundle that names none, another OS, or any other file is itself', () async {
      final bare = bundle('Bare');
      expect(await executableFor(bare, 'macos'), bare);
      final app = bundle('Duck Fork', exe: 'DuckFork');
      expect(await executableFor(app, 'linux'), app);
      expect(await executableFor('/opt/emus/duckstation-qt', 'macos'), '/opt/emus/duckstation-qt');
    });
  });
}
