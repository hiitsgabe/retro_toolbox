import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/screens/setup_wizard_screen.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_store.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records imports instead of queueing them. [manifest] stands for metadata
/// already on; [platforms] for what the catalog wants at the time of a refresh.
class _FakeLaunchbox extends LaunchboxNotifier {
  _FakeLaunchbox(super.ref, {this.manifest});
  LaunchboxManifest? manifest;
  Set<String> platforms = {'Nintendo Entertainment System'};
  final imports = <Set<String>>[];

  @override
  Future<void> refresh() async {
    await Future<void>.value();
    state = state.copyWith(loading: false, manifest: manifest, wanted: platforms);
  }

  @override
  void startImport(WidgetRef ref, BuildContext context) => imports.add(state.wanted);
}

void main() {
  test('a console uses the Internet Archive through an IA url or IA auth', () {
    expect(const Console(id: 'a', name: 'A', urls: ['https://archive.org/download/item']).usesInternetArchive, isTrue);
    expect(const Console(id: 'b', name: 'B', urls: ['https://example.com/list'], auth: {'type': 'ia_s3'}).usesInternetArchive, isTrue);
    expect(const Console(id: 'c', name: 'C', urls: ['https://example.com/list']).usesInternetArchive, isFalse);
  });

  testWidgets('the connections step hides the IA login when no console uses IA', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('setup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SetupWizardScreen(initialStep: 2))));
    await tester.pump();

    expect(find.text('Internet Archive'), findsNothing);
    expect(find.text('No accounts needed for this catalog.'), findsOneWidget);
  });

  Future<List<String>> pumpWizard(WidgetTester tester,
      {required int step, required List<bool> popped, List<Override> overrides = const []}) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('setup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              await Navigator.of(ctx).push(
                  MaterialPageRoute<void>(builder: (_) => SetupWizardScreen(initialStep: step)));
              popped.add(true);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return [];
  }

  testWidgets('Start advances a step; B goes back; B on step 0 marks seen and leaves', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 1, popped: popped);
    expect(find.text('2/3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('3/3 · Connections'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('2/3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('1/3 · Catalog'), findsOneWidget);
    expect(popped, isEmpty);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
    expect((await SharedPreferences.getInstance()).getBool(SetupWizardScreen.seenKey), isTrue);
  });

  testWidgets('Start on the last step finishes (marks seen)', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 2, popped: popped);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
    expect((await SharedPreferences.getInstance()).getBool(SetupWizardScreen.seenKey), isTrue);
  });

  testWidgets('Start pressed repeatedly walks the wizard from a cold route', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 0, popped: popped);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('2/3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('3/3 · Connections'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
  });

  testWidgets('two quick backs on step 0 leave once (the page below stays)', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 0, popped: popped);
    // Two backs in one turn, both before markSeen returns (on device it is
    // slow enough for two quick presses).
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await tester.runAsync(() async {
      nav.maybePop();
      nav.maybePop();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
    expect(find.text('open'), findsOneWidget);
  });

  group('LaunchBox on the Connections step', () {
    late _FakeLaunchbox launchbox;
    Override fake({LaunchboxManifest? manifest}) =>
        launchboxProvider.overrideWith((ref) => launchbox = _FakeLaunchbox(ref, manifest: manifest));
    final tile = find.widgetWithText(SwitchListTile, 'Download LaunchBox metadata');

    Future<void> finish(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.text('Finish'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('offers the metadata below the accounts, off by default', (tester) async {
      await pumpWizard(tester, step: 2, popped: [], overrides: [fake()]);
      expect(find.text('3/3 · Connections'), findsOneWidget);
      expect(find.text('No accounts needed for this catalog.'), findsOneWidget);
      expect(find.text('Improve with LaunchBox (optional)'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(tester.widget<SwitchListTile>(tile).onChanged, isNotNull);
    });

    testWidgets('switched on, Finish imports once what the catalog wants now', (tester) async {
      final popped = <bool>[];
      await pumpWizard(tester, step: 2, popped: popped, overrides: [fake()]);
      // A catalog loaded earlier in the wizard: Finish must not import the
      // platforms read when the screen opened.
      launchbox.platforms = {'Sega Genesis'};
      await tester.tap(tile);
      await tester.pump();
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await finish(tester);
      expect(launchbox.imports, [
        {'Sega Genesis'}
      ]);
      expect(popped, [true]);
    });

    testWidgets('left off, Finish imports nothing', (tester) async {
      final popped = <bool>[];
      await pumpWizard(tester, step: 2, popped: popped, overrides: [fake()]);
      await finish(tester);
      expect(launchbox.imports, isEmpty);
      expect(popped, [true]);
    });

    testWidgets('switched on, then leaving with B from the first step imports nothing', (tester) async {
      final popped = <bool>[];
      await pumpWizard(tester, step: 2, popped: popped, overrides: [fake()]);
      await tester.tap(tile);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('1/3 · Catalog'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(popped, [true]);
      expect(launchbox.imports, isEmpty);
    });

    testWidgets('already on: shown on and disabled, and Finish imports nothing', (tester) async {
      final popped = <bool>[];
      final manifest = LaunchboxManifest(etag: null, importedAt: DateTime.utc(2026, 11, 16), platforms: const {});
      await pumpWizard(tester, step: 2, popped: popped, overrides: [fake(manifest: manifest)]);
      final s = tester.widget<SwitchListTile>(tile);
      expect(s.value, isTrue);
      expect(s.onChanged, isNull);
      expect(find.descendant(of: tile, matching: find.text('Already on')), findsOneWidget);
      await finish(tester);
      expect(launchbox.imports, isEmpty);
      expect(popped, [true]);
    });

    testWidgets('switched on, but turned on elsewhere before Finish: no second import', (tester) async {
      final popped = <bool>[];
      await pumpWizard(tester, step: 2, popped: popped, overrides: [fake()]);
      await tester.tap(tile);
      await tester.pump();
      // The first read landed after the switch was flipped: metadata was on
      // all along.
      launchbox.manifest = LaunchboxManifest(etag: null, importedAt: DateTime.utc(2026, 11, 16), platforms: const {});
      await finish(tester);
      expect(launchbox.imports, isEmpty);
      expect(popped, [true]);
    });
  });
}
