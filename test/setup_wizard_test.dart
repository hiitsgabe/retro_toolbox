import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/screens/setup_wizard_screen.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/launchbox/launchbox_store.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/settings/ia_credentials_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No consoles: the wizard's text must not depend on a git-ignored catalog in
/// assets/catalog, which a developer may have and CI does not.
class _NoCatalog extends CatalogService {
  @override
  Future<Map<String, Console>> getConsoles([String consolesFilePath = 'consoles.json']) async => {};
}

Override _noCatalog() =>
    appStateProvider.overrideWith((ref) => AppStateNotifier(ref, _NoCatalog(), ref.read(catalogProvider.notifier)));

/// The catalog the app ships: two consoles, one of them on the Internet Archive.
class _Bundled extends CatalogService {
  @override
  Future<Map<String, Console>> getConsoles([String consolesFilePath = 'consoles.json']) async => {
        'snes': const Console(id: 'snes', name: 'SNES', urls: ['https://example.com/snes']),
        'psx': const Console(id: 'psx', name: 'PlayStation', urls: ['https://archive.org/download/psx']),
      };
}

Override _bundled() => appStateProvider.overrideWith((ref) => AppStateNotifier(ref, _Bundled(), ref.read(catalogProvider.notifier)));

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

    await tester.pumpWidget(ProviderScope(overrides: [_noCatalog()], child: const MaterialApp(home: SetupWizardScreen(initialStep: 2))));
    await tester.pump();

    expect(find.text('Internet Archive'), findsNothing);
    expect(find.text('No accounts needed for this catalog.'), findsOneWidget);
  });

  Future<List<String>> pumpWizard(WidgetTester tester,
      {required int step, required List<bool> popped, List<Override> overrides = const [], Override? catalog}) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('setup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 600);
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(ProviderScope(
      overrides: [catalog ?? _noCatalog(), ...overrides],
      child: MaterialApp(
        navigatorKey: key,
        builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
        // A Scaffold, as the menu is, for what the wizard says as it closes.
        home: Scaffold(
          body: Builder(
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
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return [];
  }

  testWidgets('Start advances a step; B goes back; B on step 0 marks seen and leaves', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 1, popped: popped);
    expect(find.text('Step 2 of 3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3 · Connections'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3 · Catalog'), findsOneWidget);
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
    expect(find.text('Step 2 of 3 · Downloads'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3 · Connections'), findsOneWidget);
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

  Finder primary() => find.byKey(const ValueKey('kit-primary'));
  String primaryLabel(WidgetTester t) => t.widget<Text>(find.descendant(of: primary(), matching: find.byType(Text)).last).data!;
  bool chosen(WidgetTester t, String title) => t.widget<KitRow>(find.widgetWithText(KitRow, title)).selected!;

  testWidgets('the catalog is one choice list with the built-in catalog chosen, and Next in the bar', (tester) async {
    await pumpWizard(tester, step: 0, popped: [], catalog: _bundled());
    expect(find.text('Step 1 of 3 · Catalog'), findsOneWidget);
    expect(chosen(tester, 'Built-in catalog'), isTrue);
    expect(chosen(tester, 'From a link'), isFalse);
    expect(find.text('2 consoles, works right away'), findsOneWidget);
    expect(find.text('Built-in · 2 consoles'), findsOneWidget);
    // What the catalog brings, by name.
    expect(find.text('PlayStation'), findsOneWidget);
    // One primary: no second "use this" button in the body, no navigation in the header.
    expect(primaryLabel(tester), 'NEXT');
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byKey(const ValueKey('kit-back')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3 · Downloads'), findsOneWidget);
  });

  testWidgets('another source asks for its input, and Start does what it needs', (tester) async {
    await pumpWizard(tester, step: 0, popped: [], catalog: _bundled());
    await tester.tap(find.text('From a link'));
    await tester.pump();
    expect(chosen(tester, 'From a link'), isTrue);
    expect(find.text('Catalog URL'), findsOneWidget);
    expect(primaryLabel(tester), 'LOAD');
    expect(tester.widget<FilledButton>(primary()).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'https://example.com/consoles.json');
    await tester.pump();
    expect(tester.widget<FilledButton>(primary()).onPressed, isNotNull);
    // Not loaded yet: the bar does not claim the built-in catalog for the link.
    expect(find.text('Built-in · 2 consoles'), findsNothing);

    await tester.tap(find.text('From a file'));
    await tester.pump();
    expect(primaryLabel(tester), 'CHOOSE FILE');
    expect(find.text('Import from file'), findsOneWidget);

    await tester.tap(find.text('Built-in catalog'));
    await tester.pump();
    expect(primaryLabel(tester), 'NEXT');
  });

  testWidgets('with no catalog at all, Start skips the step for now', (tester) async {
    await pumpWizard(tester, step: 0, popped: []);
    expect(primaryLabel(tester), 'SKIP FOR NOW');
    expect(find.text('Built-in · 0 consoles'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3 · Downloads'), findsOneWidget);
  });

  testWidgets('Not now on the first step leaves and marks the setup seen; later steps have Back', (tester) async {
    final popped = <bool>[];
    await pumpWizard(tester, step: 1, popped: popped);
    final secondary = find.byKey(const ValueKey('kit-secondary'));
    expect(find.descendant(of: secondary, matching: find.text('BACK')), findsOneWidget);
    await tester.tap(secondary);
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3 · Catalog'), findsOneWidget);
    expect(find.descendant(of: secondary, matching: find.text('NOT NOW')), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(secondary);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(popped, [true]);
    expect((await SharedPreferences.getInstance()).getBool(SetupWizardScreen.seenKey), isTrue);
  });

  testWidgets('Connections has two groups, Logins and Game info; a login opens in a sheet', (tester) async {
    await pumpWizard(tester, step: 2, popped: [], catalog: _bundled());
    expect(find.text('LOGINS'), findsOneWidget);
    expect(find.text('GAME INFO'), findsOneWidget);
    expect(find.text('Internet Archive'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.text('Internet Archive'));
    await tester.pumpAndSettle();
    expect(find.byType(IaCredentialsSetting), findsOneWidget);
  });

  testWidgets('with a pad, a new step puts the focus on its first control', (tester) async {
    await pumpWizard(tester, step: 1, popped: []);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3 · Connections'), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus!.context!;
    expect(focused.findAncestorWidgetOfExactType<OptionToggle>()?.title, 'Download LaunchBox metadata');
  });

  group('LaunchBox on the Connections step', () {
    late _FakeLaunchbox launchbox;
    Override fake({LaunchboxManifest? manifest}) =>
        launchboxProvider.overrideWith((ref) => launchbox = _FakeLaunchbox(ref, manifest: manifest));
    final tile = find.widgetWithText(OptionToggle, 'Download LaunchBox metadata');

    Future<void> finish(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('kit-primary')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('offers the metadata below the accounts, off by default', (tester) async {
      await pumpWizard(tester, step: 2, popped: [], overrides: [fake()]);
      expect(find.text('Step 3 of 3 · Connections'), findsOneWidget);
      expect(find.text('No accounts needed for this catalog.'), findsOneWidget);
      expect(find.text('GAME INFO'), findsOneWidget);
      expect(tester.widget<OptionToggle>(tile).value, isFalse);
      expect(tester.widget<OptionToggle>(tile).onChanged, isNotNull);
    });

    testWidgets('switched on, Finish imports once what the catalog wants now', (tester) async {
      final popped = <bool>[];
      await pumpWizard(tester, step: 2, popped: popped, overrides: [fake()]);
      // A catalog loaded earlier in the wizard: Finish must not import the
      // platforms read when the screen opened.
      launchbox.platforms = {'Sega Genesis'};
      await tester.tap(tile);
      await tester.pump();
      expect(tester.widget<OptionToggle>(tile).value, isTrue);
      await finish(tester);
      expect(launchbox.imports, [
        {'Sega Genesis'}
      ]);
      expect(popped, [true]);
    });

    testWidgets('switched on with no console LaunchBox knows, Finish says so on the screen below', (tester) async {
      final popped = <bool>[];
      await pumpWizard(tester, step: 2, popped: popped, overrides: [fake()]);
      launchbox.platforms = {};
      await tester.tap(tile);
      await tester.pump();
      await finish(tester);
      expect(launchbox.imports, isEmpty);
      expect(popped, [true]);
      expect(find.text('open'), findsOneWidget);
      expect(find.text(noLaunchboxConsolesMessage), findsOneWidget);
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
      expect(find.text('Step 1 of 3 · Catalog'), findsOneWidget);
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
      final s = tester.widget<OptionToggle>(tile);
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
