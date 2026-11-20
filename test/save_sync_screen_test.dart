import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_screen.dart';
import 'package:retro_toolbox/screens/save_sync_setup_screen.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';
import 'package:retro_toolbox/services/save_sync/title_catalog.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

import 'save_sync_support.dart';

class FakeNotifier extends SaveSyncNotifier {
  FakeNotifier(SaveSyncState initial) {
    state = initial;
  }

  final calls = <String>[];
  bool checkThrows = false;

  @override
  Future<void> refresh() async => calls.add('refresh');

  /// What the next push or pull reports, as the engine does.
  List<String> reply = const [];

  @override
  Future<void> push(String recipeId, {String? unit}) async {
    calls.add('push $recipeId${unit == null ? '' : ' $unit'}');
    state = state.copyWith(messages: reply);
  }

  @override
  Future<void> pull(String recipeId, {String? unit}) async => calls.add('pull $recipeId${unit == null ? '' : ' $unit'}');

  @override
  Future<void> resolve(String recipeId, String unit, {required String keep}) async => calls.add('resolve $recipeId $unit $keep');

  @override
  Future<List<({String device, String name, DateTime at})>> backupsFor(String recipeId, String unit) async {
    calls.add('backupsFor $recipeId $unit');
    return backups;
  }

  List<({String device, String name, DateTime at})> backups = const [];

  @override
  Future<void> restoreBackup(String recipeId, String unit, {required String fromDevice}) async =>
      calls.add('restore $recipeId $unit $fromDevice');

  @override
  Future<void> requestShizuku() async => calls.add('grant');

  @override
  Future<void> confirmBinding(Binding b) async => calls.add('confirm ${b.recipe}');

  @override
  Future<void> signInWithGoogle() async => calls.add('google');

  @override
  Future<void> setHubFolder([String? path]) async => calls.add('folder ${path ?? 'default'}');

  @override
  Future<void> signOut() async => calls.add('sign out');

  @override
  Future<List<CheckLine>> check(String recipeId) async {
    if (checkThrows) throw StateError('bridge died');
    return const [
        CheckLine(CheckLevel.ok, 'Recipe', 'Stardew Valley: verified recipe from bundled'),
        CheckLine(CheckLevel.fail, 'Hub Farm_1', 'damaged'),
    ];
  }
}

void main() {
  final stardew = bundledRecipe('stardew-valley');
  const binding = Binding(recipe: 'stardew-valley', package: stardewPkg, area: Area.androidData, root: 'files/Saves');
  final remote = GenMeta(
    gen: '20261110T224107Z-thor-7f3a-9f2c01e1',
    parents: const [],
    recipe: 'stardew-valley',
    unit: 'Farm_2',
    device: 'thor-7f3a',
    deviceName: 'AYN Thor',
    createdAt: DateTime.utc(2026, 11, 10, 22, 41),
    package: stardewPkg,
    files: const {},
    payloadSha256: 'f' * 64,
  );

  Future<FakeNotifier> pump(WidgetTester t, SaveSyncState s, {InputMode mode = InputMode.touch}) async {
    final fake = FakeNotifier(s);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake), inputModeProvider.overrideWith((ref) => mode)],
      // DpadScope, as the app has it: Start, Y and Select reach the screen.
      child: MaterialApp(navigatorKey: nav, builder: (c, child) => DpadScope(navigatorKey: nav, child: child!), home: const SaveSyncScreen()),
    ));
    await t.pump();
    return fake;
  }

  /// The bar's primary, whatever case the style draws it in.
  Finder primary(String label) => find.descendant(of: find.byKey(const ValueKey('kit-primary')), matching: find.text(label.toUpperCase()));

  Future<void> openInfo(WidgetTester t) async {
    await t.tap(find.byTooltip('About this screen'));
    await t.pumpAndSettle();
  }

  testWidgets('a game with several saves acts on one at a time', (t) async {
    final fake = await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, hubFolder: '/storage/emulated/0/Retro Toolbox Saves', games: [
        GameStatus(stardew, 'bundled', const Bound(binding), installedVersion: '1.6.15.2', units: {
          'Farm_1': const UnitStatus(PushPlan('Farm_1', [])),
          'Farm_2': UnitStatus(PullPlan('Farm_2', remote, missingLocally: true), newest: remote),
        }),
      ]),
    );
    expect(fake.calls, ['refresh']);
    expect(find.text('Stardew Valley'), findsOneWidget);
    // Two saves under one game, so the row offers no verb of its own (acting
    // on both at once is what loses somebody's progress) and opens the list
    // of saves, each with its own line and its own verb.
    expect(find.text('1 to download · 1 to upload · 2 saves'), findsOneWidget);
    expect(find.text('Farm_1'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Upload'), findsNothing);
    await t.tap(find.text('Stardew Valley'));
    await t.pumpAndSettle();
    expect(find.text('Farm_1'), findsOneWidget);
    expect(find.text('Farm_2'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Upload'), findsNothing);

    await t.tap(find.widgetWithText(OutlinedButton, 'Upload'));
    expect(fake.calls.last, 'push stardew-valley Farm_1');
    await t.tap(find.widgetWithText(OutlinedButton, 'Download'));
    expect(fake.calls.last, 'pull stardew-valley Farm_2');
  });

  testWidgets('an emulated game is named, not left as its id', (t) async {
    final eden = bundledRecipe('eden');
    const edenBind = Binding(recipe: 'eden', package: 'dev.eden.eden_emulator', area: Area.androidData, root: 'files/nand/user/save/0000000000000000/ABC');
    final fake = await pump(
      t,
      SaveSyncState(
        access: SyncAccess.shizuku,
        titles: const {
          '0100000000ABC000': TitleInfo('Alpha Title', 'https://art.example/alpha.png'),
          '0100000000DEF000': TitleInfo('Beta Title', null),
        },
        games: [
          GameStatus(eden, 'bundled', const Bound(edenBind), units: {
            '0100000000ABC000': const UnitStatus(PushPlan('0100000000ABC000', [])),
            '0100000000DEF000': const UnitStatus(UpToDate('0100000000DEF000')),
            '0100000000FFF000': const UnitStatus(UpToDate('0100000000FFF000')),
          }),
        ],
      ),
    );
    await t.tap(find.text(eden.name));
    await t.pumpAndSettle();
    expect(find.text('Alpha Title'), findsOneWidget);
    expect(find.text('Beta Title'), findsOneWidget);
    // An id the catalog never heard of is still a save worth syncing, so it
    // keeps its id rather than disappearing or reading as unknown.
    expect(find.text('0100000000FFF000'), findsOneWidget);
    expect(find.text('0100000000ABC000'), findsNothing);

    // The name is decoration; the key is what travels. Pushing the row that
    // says Alpha Title must push the id it stands for.
    await t.tap(find.widgetWithText(OutlinedButton, 'Upload'));
    expect(fake.calls.last, 'push eden 0100000000ABC000');
  });

  testWidgets('with only an upload owing, the verb is Upload', (t) async {
    final fake = await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, games: [
        GameStatus(stardew, 'bundled', const Bound(binding), units: {
          'Farm_1': const UnitStatus(PushPlan('Farm_1', [])),
        }),
      ]),
    );
    expect(find.textContaining('Needs upload'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Upload'));
    expect(fake.calls, ['refresh', 'push stardew-valley']);
  });

  testWidgets('a game that is running says so and offers no verb', (t) async {
    await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, games: [
        GameStatus(
          stardew,
          'bundled',
          const Bound(binding),
          running: true,
          notes: const ['Recovered an interrupted pull of Farm_1'],
          units: {'Farm_2': UnitStatus(const Blocked('Farm_2', 'Stardew Valley is running'), newest: remote)},
        ),
      ]),
    );
    expect(find.text('Close the game first'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Upload'), findsNothing);
  });

  testWidgets('without access it offers the Shizuku grant', (t) async {
    final fake = await pump(t, const SaveSyncState(shizukuRunning: true));
    await t.tap(find.text('Grant Shizuku access'));
    expect(fake.calls.last, 'grant');
  });

  // url_launcher talks to this channel under flutter test; record the URLs.
  List<String> launches(WidgetTester t) {
    final urls = <String>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'launch') urls.add((call.arguments as Map)['url'] as String);
      return true;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    return urls;
  }

  for (final running in [true, false]) {
    testWidgets('without access the card links to the Shizuku setup (Shizuku ${running ? 'running' : 'stopped'})', (t) async {
      final urls = launches(t);
      await pump(t, SaveSyncState(shizukuRunning: running));
      expect(find.text('No access to game folders'), findsOneWidget);
      await t.tap(find.text('How to set up Shizuku'));
      await t.pump();
      expect(urls, ['https://hiitsgabe.github.io/retro_toolbox/save-sync.html#shizuku']);
    });
  }

  testWidgets('the (i) explains Save Sync and links to its page', (t) async {
    final urls = launches(t);
    await pump(t, const SaveSyncState());
    expect(find.textContaining("Pull a game's save before you play"), findsNothing);
    await t.tap(find.byTooltip('About this screen'));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining("Pull a game's save before you play")), findsOneWidget);
    await t.tap(find.text('Learn more'));
    await t.pump();
    expect(urls, ['https://hiitsgabe.github.io/retro_toolbox/save-sync.html']);
  });

  testWidgets('the row takes its name from Android', (t) async {
    await pump(
      t,
      SaveSyncState(
        access: SyncAccess.shizuku,
        hubKind: HubKind.folder,
        games: [GameStatus(stardew, 'bundled', const Bound(binding))],
        appInfo: {binding.package: const AppInfo('What the launcher calls it', null)},
      ),
    );
    expect(find.text('What the launcher calls it'), findsOneWidget);
    expect(find.text(stardew.name), findsNothing);
  });

  testWidgets('a game Android cannot describe keeps the recipe name', (t) async {
    await pump(
      t,
      SaveSyncState(
        access: SyncAccess.shizuku,
        hubKind: HubKind.folder,
        games: [GameStatus(stardew, 'bundled', const Bound(binding))],
      ),
    );
    expect(find.text(stardew.name), findsOneWidget);
  });

  // The state that used to be a dead end: both buttons disabled under a line
  // saying that picking a version came later.
  testWidgets('a conflict offers the choice, and keeping one settles it', (t) async {
    final fake = await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, hubKind: HubKind.folder, games: [
        GameStatus(stardew, 'bundled', const Bound(binding), units: {
          'Farm_1': UnitStatus(
            Diverged('Farm_1', [remote], localDiffers: true),
            local: const LocalUnit('Farm_1', {'Farm_1/Farm_1': LocalFile('abc', 12)}),
            newest: remote,
          ),
        }),
      ]),
    );
    expect(find.textContaining('Both sides changed'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Choose version'));
    await t.pumpAndSettle();
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('AYN Thor'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Keep this').last);
    await t.pumpAndSettle();
    expect(fake.calls.last, startsWith('resolve stardew-valley Farm_1'));
  });

  // The rare actions live behind the dots so they never sit beside the one
  // verb the row is actually for.
  testWidgets('the dots hold restore and check, and the row keeps one verb', (t) async {
    await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, hubKind: HubKind.folder, games: [
        GameStatus(stardew, 'bundled', const Bound(binding), units: {
          'Farm_1': const UnitStatus(PushPlan('Farm_1', [])),
        }),
      ]),
    );
    expect(find.widgetWithText(FilledButton, 'Upload'), findsOneWidget);
    expect(find.text('Restore a backup…'), findsNothing);

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('Restore a backup…'), findsOneWidget);
    expect(find.text('Check'), findsOneWidget);
  });

  testWidgets('with nothing replaced yet, restore says so instead of opening empty', (t) async {
    await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, hubKind: HubKind.folder, games: [
        GameStatus(stardew, 'bundled', const Bound(binding), units: {
          'Farm_1': const UnitStatus(PushPlan('Farm_1', [])),
        }),
      ]),
    );
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('Restore a backup…'));
    await t.pumpAndSettle();
    expect(find.text('No backup yet'), findsOneWidget);
  });

  testWidgets('picking a handheld restores from it, after saying what goes away', (t) async {
    final fake = await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, hubKind: HubKind.folder, games: [
        GameStatus(stardew, 'bundled', const Bound(binding), units: {
          'Farm_1': const UnitStatus(PushPlan('Farm_1', [])),
        }),
      ]),
    );
    fake.backups = [(device: 'odin-1', name: 'AYN Odin2 Mini', at: DateTime.utc(2026, 11, 13, 2))];

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('Restore a backup…'));
    await t.pumpAndSettle();
    expect(find.text('AYN Odin2 Mini'), findsOneWidget);

    await t.tap(find.text('AYN Odin2 Mini'));
    await t.pumpAndSettle();
    expect(find.text('Put this one back?'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Restore'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'restore stardew-valley Farm_1 odin-1');
  });

  // An app that names its own save folder can leave more than one that looks
  // right. The binder refuses to pick; the owner picks here.
  testWidgets('several possible places become a choice the owner can make', (t) async {
    const a = Binding(recipe: 'stardew-valley', package: 'com.chucklefish.stardewvalley', area: Area.androidData, root: 'files/save/0/AAA');
    const b = Binding(recipe: 'stardew-valley', package: 'com.chucklefish.stardewvalley', area: Area.androidData, root: 'files/save/0/BBB');
    final fake = await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, hubKind: HubKind.folder, games: [
        GameStatus(stardew, 'bundled', const NeedsDiscovery('saves found in more than one place', places: [
          (a, ['one.sav']),
          (b, ['two.sav', 'three.sav']),
        ])),
      ]),
    );
    expect(find.textContaining('could be in more than one place'), findsOneWidget);

    await t.tap(find.widgetWithText(FilledButton, 'Choose location'));
    await t.pumpAndSettle();
    // Shown by what is in each, not by a name that means nothing on its own.
    expect(find.text('AAA'), findsOneWidget);
    expect(find.text('1 file'), findsOneWidget);
    expect(find.text('2 files'), findsOneWidget);

    await t.tap(find.text('BBB'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'confirm stardew-valley');
  });

  testWidgets('a hub that is set up offers somewhere to add apps', (t) async {
    await pump(
      t,
      SaveSyncState(
        access: SyncAccess.shizuku,
        hubKind: HubKind.folder,
        games: [GameStatus(stardew, 'bundled', const Bound(binding))],
      ),
    );
    expect(primary('Add an app'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNotNull);
  });

  testWidgets('a game this device does not have is left out of the list', (t) async {
    await pump(
      t,
      SaveSyncState(
        access: SyncAccess.shizuku,
        hubKind: HubKind.folder,
        games: [
          GameStatus(stardew, 'bundled', const Bound(binding)),
          GameStatus(bundledRecipe('sea-of-stars'), 'bundled', const NotInstalled()),
        ],
      ),
    );
    expect(find.text(stardew.name), findsOneWidget);
    expect(find.text('Sea of Stars'), findsNothing);
  });

  testWidgets('with nothing installed the list says so instead of sitting empty', (t) async {
    await pump(
      t,
      SaveSyncState(
        access: SyncAccess.shizuku,
        hubKind: HubKind.folder,
        games: [GameStatus(stardew, 'bundled', const NotInstalled())],
      ),
    );
    expect(find.textContaining('Not on this device (1)'), findsOneWidget);
    expect(find.textContaining('Nothing here is set up to sync yet'), findsOneWidget);
  });

  // Recipes are not bundled and the list is opt-in, so a fresh hub has no
  // rows at all: point at the one button that adds one.
  testWidgets('with no apps chosen the list points at Add an app', (t) async {
    await pump(t, const SaveSyncState(access: SyncAccess.shizuku, hubKind: HubKind.folder, games: []));
    expect(find.text('No apps yet. Use Add an app to choose which games sync.'), findsOneWidget);
    expect(find.textContaining('No recipes loaded'), findsNothing);
  });

  testWidgets('Check opens a dialog with every line', (t) async {
    await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, games: [GameStatus(stardew, 'bundled', const Bound(binding))]),
    );
    await t.tap(find.text(stardew.name));
    await t.pumpAndSettle();
    expect(find.text('Hub Farm_1'), findsOneWidget);
    expect(find.text('damaged'), findsOneWidget);
  });

  testWidgets('a failing Check shows the error instead of spinning', (t) async {
    final fake = await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, games: [GameStatus(stardew, 'bundled', const Bound(binding))]),
    );
    fake.checkThrows = true;
    await t.tap(find.text(stardew.name));
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('bridge died'), findsOneWidget);
  });

  testWidgets('a draft location asks for confirmation', (t) async {
    final fake = await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, games: [
        GameStatus(bundledRecipe('sea-of-stars'), 'bundled', const NeedsConfirm(
          Binding(recipe: 'sea-of-stars', package: 'com.playdigious.seaofstars', area: Area.androidData, root: 'files', mode: 'backup'),
          ['SOS_SaveSlot0.sos'],
        )),
      ]),
    );
    await t.tap(find.text('Confirm location'));
    await t.pumpAndSettle();
    expect(find.text('SOS_SaveSlot0.sos'), findsOneWidget);
    await t.tap(find.text('Use this place'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'confirm sea-of-stars');
  });

  // A handheld with no place chosen has nothing to list, so it is sent to the
  // two questions rather than shown a screen of empty cards.
  testWidgets('first run goes to setup, and the list asks nothing itself', (t) async {
    await pump(t, const SaveSyncState(hubKind: HubKind.none, googleAvailable: true, access: SyncAccess.shizuku));
    await t.pumpAndSettle();
    expect(find.byType(SaveSyncSetupScreen), findsOneWidget);
    expect(find.text('Step 1 of 2 · Where'), findsOneWidget);
  });

  // Nothing on this device can opt out of a hub app, so ticks would promise
  // a choice that is never read.
  testWidgets('setup lists the apps that apply here, with nothing to tick', (t) async {
    final fake = FakeNotifier(SaveSyncState(
      hubKind: HubKind.folder,
      access: SyncAccess.shizuku,
      games: [
        GameStatus(stardew, 'bundled', const Bound(binding)),
        GameStatus(bundledRecipe('sea-of-stars'), 'bundled', const NotInstalled()),
      ],
    ));
    bool? popped;
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => popped = await Navigator.of(c).push(MaterialPageRoute<bool>(builder: (_) => const SaveSyncSetupScreen())),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('WILL APPLY HERE (1)'), findsOneWidget);
    expect(find.text(stardew.name), findsOneWidget);
    expect(find.text('NOT ON THIS DEVICE (1)'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.textContaining('Adopt'), findsNothing);
    expect(find.text('Step 2 of 2 · Apps'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'OPEN SAVE SYNC'));
    await t.pumpAndSettle();
    expect(popped, isTrue);
  });

  testWidgets('Use a folder opens the picker at the default, and only a picked folder becomes the hub', (t) async {
    final fake = FakeNotifier(const SaveSyncState(hubKind: HubKind.none));
    final asked = <String>[];
    String? answer;
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: MaterialApp(
        home: SaveSyncSetupScreen(pickFolder: (_, initialDir) async {
          asked.add(initialDir);
          return answer;
        }),
      ),
    ));
    await t.tap(find.widgetWithText(FilledButton, 'USE A FOLDER'));
    await t.pumpAndSettle();
    expect(asked, [fake.defaultHubFolder]);
    expect(fake.calls, isEmpty);
    expect(find.text('Where should saves go?'), findsOneWidget);

    answer = '/storage/emulated/0/Handheld Saves';
    await t.tap(find.widgetWithText(FilledButton, 'USE A FOLDER'));
    await t.pumpAndSettle();
    expect(fake.calls, ['folder /storage/emulated/0/Handheld Saves']);
  });

  // One question, one choice list; the bar's button says what the choice
  // does, in the words the website quotes.
  testWidgets('Where is one choice, Drive first when the build has Google; Start does the chosen one', (t) async {
    final fake = FakeNotifier(const SaveSyncState(hubKind: HubKind.none, googleAvailable: true));
    final asked = <String>[];
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: SaveSyncSetupScreen(pickFolder: (_, initialDir) async {
          asked.add(initialDir);
          return null;
        }),
      ),
    ));
    await t.pump();
    expect(find.text('Step 1 of 2 · Where'), findsOneWidget);
    expect(t.widget<KitRow>(find.widgetWithText(KitRow, 'Google Drive')).selected, isTrue);
    expect(primary('Sign in with Google'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pump();
    expect(fake.calls, ['google']);

    await t.tap(find.text('A folder'));
    await t.pump();
    expect(t.widget<KitRow>(find.widgetWithText(KitRow, 'A folder')).selected, isTrue);
    expect(primary('Use a folder'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(asked, [fake.defaultHubFolder]);
  });

  testWidgets('Not now puts the first question off; there is no way back from Apps but out', (t) async {
    final fake = FakeNotifier(const SaveSyncState(hubKind: HubKind.none));
    Object? popped = 'open';
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async => popped = await Navigator.of(c).push(MaterialPageRoute<bool>(builder: (_) => const SaveSyncSetupScreen())),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(OutlinedButton, 'NOT NOW'));
    await t.pumpAndSettle();
    expect(popped, isNull);
    expect(find.text('go'), findsOneWidget);
  });

  testWidgets('Needs a look says why each recipe was not loaded', (t) async {
    final fake = FakeNotifier(SaveSyncState(
      hubKind: HubKind.folder,
      games: [GameStatus(stardew, 'bundled', const Bound(binding))],
      recipeProblems: const {'odd.json': 'unknown key "rooot"'},
    ));
    await t.pumpWidget(ProviderScope(overrides: [saveSyncProvider.overrideWith((ref) => fake)], child: const MaterialApp(home: SaveSyncSetupScreen())));
    await t.pump();
    expect(find.text('NEEDS A LOOK (1)'), findsOneWidget);
    expect(find.text('unknown key "rooot"'), findsOneWidget);
    expect(find.text('No recipe for this one yet'), findsNothing);
  });

  // Plain tests, not testWidgets: disk IO hangs under the widget binding's fake clock.
  group('the picker starts at', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('hub_start_'));
    tearDown(() async => tmp.delete(recursive: true));

    test('the folder itself when it already exists', () async {
      final dir = await Directory(p.join(tmp.path, 'Saves')).create();
      expect(await hubPickerStart(dir.path), dir.path);
    });

    test('the folder, made for it, when it does not exist yet', () async {
      final dir = p.join(tmp.path, 'Retro Toolbox Saves');
      expect(await hubPickerStart(dir), dir);
      expect(Directory(dir).existsSync(), isTrue);
    });

    test('its parent when the folder cannot be made', () async {
      // A file where the parent folder should be makes the create fail, as missing permission would.
      final blocker = await File(p.join(tmp.path, 'blocker')).create();
      final dir = p.join(blocker.path, 'Saves');
      expect(await hubPickerStart(dir), blocker.path);
    });
  });

  testWidgets('a hub that will not open lets the owner pick the folder again', (t) async {
    final fake = FakeNotifier(const SaveSyncState(hubKind: HubKind.folder, hubFolder: '/storage/emulated/0/Old', error: 'No hub here'));
    final asked = <String>[];
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: MaterialApp(
        home: SaveSyncSetupScreen(pickFolder: (_, initialDir) async {
          asked.add(initialDir);
          return '/storage/emulated/0/New';
        }),
      ),
    ));
    await t.tap(find.text('Pick the folder again'));
    await t.pumpAndSettle();
    expect(asked, ['/storage/emulated/0/Old']);
    expect(fake.calls, ['folder /storage/emulated/0/New']);
  });

  testWidgets('before the first refresh has read the hub, neither the first run nor a hub row shows', (t) async {
    await pump(t, const SaveSyncState(googleAvailable: true));
    expect(find.text('Where should saves go?'), findsNothing);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('a build without Google offers only the folder', (t) async {
    await pump(t, const SaveSyncState(hubKind: HubKind.none));
    await t.pumpAndSettle();
    expect(find.text('A folder'), findsOneWidget);
    expect(find.text('Google Drive'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'USE A FOLDER'), findsOneWidget);
    expect(find.textContaining(RegExp('Sign in with Google', caseSensitive: false)), findsNothing);
  });

  // Where saves go is a setup decision: the header names it, the (i) changes it.
  testWidgets('a Google hub names the account in the header, and its (i) has Sign out and no folder note', (t) async {
    final fake = await pump(t, const SaveSyncState(hubKind: HubKind.drive, googleEmail: 'player@gmail.com', googleAvailable: true, access: SyncAccess.shizuku));
    expect(find.text('Drive · player@gmail.com'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    await openInfo(t);
    expect(find.text('Google Drive: player@gmail.com'), findsOneWidget);
    expect(find.textContaining('Folder hub'), findsNothing);
    expect(find.text('Sign in again'), findsNothing);
    await t.tap(find.text('Sign out'));
    expect(fake.calls.last, 'sign out');
  });

  testWidgets('a folder hub keeps its path and note in the (i), and Change switches to Google', (t) async {
    final fake = await pump(t, const SaveSyncState(hubKind: HubKind.folder, hubFolder: '/storage/emulated/0/Hub', googleAvailable: true, access: SyncAccess.shizuku));
    expect(find.text('Folder · 0 games'), findsOneWidget);
    expect(find.textContaining('Folder hub'), findsNothing);
    await openInfo(t);
    expect(find.text('/storage/emulated/0/Hub'), findsOneWidget);
    expect(find.textContaining('Folder hub'), findsOneWidget);
    await t.tap(find.text('Change'));
    await t.pumpAndSettle();
    expect(find.text('A folder on this device'), findsOneWidget);
    await t.tap(find.text('Google Drive'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'google');
  });

  testWidgets('without Google the chooser offers only a folder', (t) async {
    await pump(t, const SaveSyncState(hubKind: HubKind.folder, hubFolder: '/storage/emulated/0/Hub', access: SyncAccess.shizuku));
    await openInfo(t);
    await t.tap(find.text('Change'));
    await t.pumpAndSettle();
    expect(find.text('A folder on this device'), findsOneWidget);
    expect(find.text('Google Drive'), findsNothing);
  });

  testWidgets('Google wanting the user again, and a failed sign-in, are both shown', (t) async {
    final fake = await pump(
      t,
      const SaveSyncState(
        hubKind: HubKind.drive,
        googleEmail: 'player@gmail.com',
        googleAvailable: true,
        signInAgain: true,
        signInError: 'This build is not registered with Google, so it cannot use Google Drive. Use a folder instead.',
        error: 'Sign in to Google again.',
      ),
    );
    expect(find.textContaining('not registered with Google'), findsOneWidget);
    expect(find.text('Sign in to Google again.'), findsOneWidget);
    await t.tap(find.text('Sign in again'));
    expect(fake.calls.last, 'google');
  });

  testWidgets('while signing in, the hub buttons wait', (t) async {
    await pump(t, const SaveSyncState(hubKind: HubKind.none, googleAvailable: true, signingIn: true));
    // Not pumpAndSettle: the progress bar never settles while signing in.
    await t.pump();
    await t.pump();
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'SIGN IN WITH GOOGLE')).onPressed, isNull);
    // The other choice waits too: picking it would start a second sign-up.
    expect(t.widget<KitRow>(find.widgetWithText(KitRow, 'A folder')).onTap, isNull);
    expect(find.text('Signing in to Google'), findsOneWidget);
    // One on the setup screen, one on the list behind it.
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });

  group('games first', () {
    SaveSyncState two({SyncAccess access = SyncAccess.shizuku}) => SaveSyncState(access: access, hubKind: HubKind.folder, hubFolder: '/storage/emulated/0/Hub', games: [
          GameStatus(stardew, 'bundled', const Bound(binding), units: {'Farm_1': const UnitStatus(PushPlan('Farm_1', []))}),
          GameStatus(bundledRecipe('sea-of-stars'), 'bundled', const Bound(Binding(recipe: 'sea-of-stars', package: 'com.playdigious.seaofstars', area: Area.androidData, root: 'files')),
              units: {'all': const UnitStatus(UpToDate('all'))}),
        ]);

    testWidgets('the header says where saves go and how many games', (t) async {
      await pump(t, two());
      expect(find.text('Folder · 2 games'), findsOneWidget);
    });

    // Start is the focused row's action, never a sync of everything.
    testWidgets('with a pad, Start runs the focused row\'s action and the bar names it', (t) async {
      final fake = await pump(t, two(), mode: InputMode.gamepad);
      await t.pump();
      expect(primary('Upload'), findsOneWidget, reason: 'the first row has focus and owes an upload');
      expect(find.byKey(const ValueKey('kit-secondary')), findsOneWidget, reason: 'Add an app moves to the secondary');
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await t.pump();
      expect(fake.calls.last, 'push stardew-valley');
    });

    testWidgets('Start on a row with nothing to do does nothing, not Add an app', (t) async {
      final fake = await pump(t, two(), mode: InputMode.gamepad);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(find.byKey(const ValueKey('kit-primary')), findsNothing);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await t.pumpAndSettle();
      expect(fake.calls, ['refresh']);
      expect(find.byType(SaveSyncScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    // The bar follows the last input a frame late: the first Start after a
    // tap must still be the focused row's, never the bar's Add an app.
    testWidgets('Start on a focused row runs that row even while the bar still shows touch', (t) async {
      final fake = await pump(t, two());
      await t.pump();
      expect(primary('Add an app'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
      await t.pumpAndSettle();
      expect(fake.calls.last, 'push stardew-valley');
      expect(find.byType(SaveSyncScreen), findsOneWidget);
    });

    testWidgets('on touch the bar keeps Add an app and the row keeps its own button', (t) async {
      await pump(t, two());
      await t.pump();
      expect(primary('Add an app'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Upload'), findsOneWidget);
    });

    testWidgets('Y opens the row menu: Restore a backup, Check, Choose location', (t) async {
      await pump(t, two(), mode: InputMode.gamepad);
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.gameButtonY);
      await t.pumpAndSettle();
      final sheet = find.byType(BottomSheet);
      for (final item in ['Upload', 'Restore a backup…', 'Check', 'Choose location']) {
        expect(find.descendant(of: sheet, matching: find.text(item)), findsOneWidget, reason: item);
      }
    });

    testWidgets('an action\'s result lands in its own row, not as loose text', (t) async {
      final fake = await pump(t, two());
      fake.reply = const ['Farm_1: pushed'];
      await t.tap(find.widgetWithText(FilledButton, 'Upload'));
      await t.pump();
      final result = find.byKey(const ValueKey('save-sync-result'));
      expect(result, findsOneWidget);
      // One save: the row says what happened, not the save's folder name.
      expect(t.widget<Text>(result).data, 'Pushed');
      expect(find.descendant(of: find.byKey(const ValueKey('save-sync-row-stardew-valley')), matching: result), findsOneWidget);
    });

    testWidgets('access is only shown when it is missing; the (i) says which one is in use', (t) async {
      await pump(t, two());
      expect(find.textContaining('Access:'), findsNothing);
      expect(find.text('No access to game folders'), findsNothing);
      await openInfo(t);
      expect(find.text('Access: Shizuku (shell)'), findsOneWidget);
    });

    testWidgets('without Shizuku running the panel offers Retry and keeps the website\'s words', (t) async {
      final fake = await pump(t, two(access: SyncAccess.none));
      expect(find.text('No access to game folders'), findsOneWidget);
      expect(find.text('Start Shizuku (wireless debugging, or root), then come back and refresh.'), findsOneWidget);
      await t.tap(find.text('Retry'));
      expect(fake.calls.last, 'refresh');
    });

    testWidgets('a save in a game with several restores that save, from its own menu', (t) async {
      final fake = await pump(
        t,
        SaveSyncState(access: SyncAccess.shizuku, hubKind: HubKind.folder, games: [
          GameStatus(stardew, 'bundled', const Bound(binding), units: {
            'Farm_1': const UnitStatus(PushPlan('Farm_1', [])),
            'Farm_2': UnitStatus(PullPlan('Farm_2', remote, missingLocally: false), newest: remote),
          }),
        ]),
      );
      await t.tap(find.text('Stardew Valley'));
      await t.pumpAndSettle();
      await t.longPress(find.text('Farm_2'));
      await t.pumpAndSettle();
      await t.tap(find.text('Restore a backup…'));
      await t.pumpAndSettle();
      expect(fake.calls.last, 'backupsFor stardew-valley Farm_2');
    });
  });
}
