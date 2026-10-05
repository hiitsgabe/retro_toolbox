import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/providers/update_provider.dart';
import 'package:retro_toolbox/screens/about_screen.dart';
import 'package:retro_toolbox/services/update_service.dart';

const _packageInfo = MethodChannel('dev.fluttercommunity.plus/package_info');

/// PackageInfo caches the first answer, so later tests set it directly.
void _mockVersion(WidgetTester t, String version) => PackageInfo.setMockInitialValues(
    appName: 'x', packageName: 'x', version: version, buildNumber: '1', buildSignature: '');

final _release = ReleaseInfo(
  version: '0.3.0',
  htmlUrl: 'https://github.com/hiitsgabe/retro_toolbox/releases/tag/v0.3.0',
  notes: '## Retro Toolbox v0.3.0\n### New Features\n- Shiny thing\n---\n### Downloads',
  assets: const [
    ReleaseAsset(name: 'retro_toolbox_arm64.apk', url: 'u', size: 31457280),
    ReleaseAsset(name: 'retro_toolbox_handheld_arm64.zip', url: 'u', size: 1024),
  ],
);

class _FakeService extends UpdateService {
  _FakeService() : super(portRoot: '/nowhere');
  Future<ReleaseInfo> Function() fetch = () async => _release;
  final downloadGate = Completer<void>();
  bool staged = false;
  bool installResult = true;
  int installs = 0;

  @override
  Future<ReleaseInfo> fetchLatest() => fetch();

  @override
  Future<File> download(ReleaseAsset asset, void Function(double progress) onProgress) async {
    onProgress(0.5);
    await downloadGate.future;
    return File('/nowhere/${asset.name}');
  }

  @override
  Future<void> stageHandheld(File zip) async => staged = true;

  @override
  Future<bool> installApk(File apk) async {
    installs++;
    return installResult;
  }
}

Future<void> _pumpAbout(WidgetTester t, _FakeService service, {bool handheld = false, String os = 'android'}) async {
  await t.pumpWidget(ProviderScope(
    overrides: [
      updateProvider.overrideWith(
          (ref) => UpdateNotifier(service, handheld: handheld, os: os, abi: handheld ? Abi.linuxArm64 : Abi.androidArm64)),
    ],
    child: const MaterialApp(home: AboutScreen()),
  ));
  await t.pumpAndSettle();
}

Finder _button(String label) => find.widgetWithText(FilledButton, label);

void main() {
  testWidgets('leaving the About screen before package info loads does not setState after dispose', (t) async {
    final gate = Completer<void>();
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_packageInfo, (_) async {
      await gate.future;
      return <String, dynamic>{'appName': 'x', 'packageName': 'x', 'version': '1', 'buildNumber': '1'};
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(_packageInfo, null));

    await t.pumpWidget(ProviderScope(
      overrides: [updateProvider.overrideWith((ref) => UpdateNotifier(_FakeService()))],
      child: const MaterialApp(home: AboutScreen()),
    ));
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    gate.complete();
    await t.pump(const Duration(milliseconds: 10));
    expect(t.takeException(), isNull);
  });

  testWidgets('checks on open and reports up to date, focusing the check button', (t) async {
    _mockVersion(t, '0.3.0');
    await _pumpAbout(t, _FakeService());

    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Version 0.3.0 is the latest'), findsOneWidget);
    final button = t.widget<FilledButton>(_button('Check for updates'));
    expect(button.onPressed, isNotNull);
    expect(button.focusNode!.hasFocus, isTrue);
  });

  testWidgets('shows checking while the request is in flight', (t) async {
    _mockVersion(t, '0.2.8');
    final service = _FakeService();
    final pending = Completer<ReleaseInfo>();
    service.fetch = () => pending.future;
    await t.pumpWidget(ProviderScope(
      overrides: [updateProvider.overrideWith((ref) => UpdateNotifier(service, handheld: false, os: 'android'))],
      child: const MaterialApp(home: AboutScreen()),
    ));
    await t.pump();
    await t.pump();

    expect(find.text('Checking for updates…'), findsOneWidget);
    expect(t.widget<FilledButton>(_button('Check for updates')).onPressed, isNull);
    pending.complete(_release);
    await t.pumpAndSettle();
  });

  testWidgets('android: available -> downloading -> ready, then install', (t) async {
    _mockVersion(t, '0.2.8');
    final service = _FakeService()..installResult = false;
    await _pumpAbout(t, service);

    expect(find.text('Version 0.3.0 available'), findsOneWidget);
    expect(find.text('30.0 MB'), findsOneWidget);
    expect(find.textContaining('• Shiny thing'), findsOneWidget);
    expect(t.widget<FilledButton>(_button('Download update')).focusNode!.hasFocus, isTrue);

    await t.tap(_button('Download update'));
    await t.pump();
    expect(find.text('Downloading 0.3.0…'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    service.downloadGate.complete();
    await t.pumpAndSettle();
    expect(service.installs, 1);
    expect(find.text('Update downloaded'), findsOneWidget);
    expect(find.text('Allow Retro Toolbox to install apps, then press Install again.'), findsOneWidget);

    service.installResult = true;
    await t.tap(_button('Install'));
    await t.pumpAndSettle();
    expect(service.installs, 2);
    expect(find.textContaining('Allow Retro Toolbox'), findsNothing);
  });

  testWidgets('handheld: stages the update and asks for a restart', (t) async {
    _mockVersion(t, '0.2.8');
    final service = _FakeService();
    service.downloadGate.complete();
    await _pumpAbout(t, service, handheld: true, os: 'linux');

    await t.tap(_button('Download update'));
    await t.pumpAndSettle();
    expect(service.staged, isTrue);
    expect(find.text('Restart Retro Toolbox to finish the update'), findsOneWidget);
    expect(_button('Close app'), findsOneWidget);
  });

  testWidgets('desktop: offers the release page instead of a download', (t) async {
    _mockVersion(t, '0.2.8');
    await _pumpAbout(t, _FakeService(), os: 'macos');

    expect(find.text('Version 0.3.0 available'), findsOneWidget);
    expect(_button('Open release page'), findsOneWidget);
    expect(_button('Download update'), findsNothing);
  });

  testWidgets('errors are shown and the check can be retried', (t) async {
    _mockVersion(t, '0.2.8');
    final service = _FakeService()..fetch = () async => throw const UpdateException('GitHub rate limit reached. Try again later.');
    await _pumpAbout(t, service);

    expect(find.text('Update check failed'), findsOneWidget);
    expect(find.text('GitHub rate limit reached. Try again later.'), findsOneWidget);

    service.fetch = () async => _release;
    await t.tap(_button('Check for updates'));
    await t.pumpAndSettle();
    expect(find.text('Version 0.3.0 available'), findsOneWidget);
  });
}
