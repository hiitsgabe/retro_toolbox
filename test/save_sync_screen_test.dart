import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_screen.dart';
import 'package:retro_toolbox/screens/save_sync_setup_screen.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/checker.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';

import 'save_sync_support.dart';

class FakeNotifier extends SaveSyncNotifier {
  FakeNotifier(SaveSyncState initial) {
    state = initial;
  }

  final calls = <String>[];
  bool checkThrows = false;

  @override
  Future<void> refresh() async => calls.add('refresh');

  @override
  Future<void> push(String recipeId) async => calls.add('push $recipeId');

  @override
  Future<void> pull(String recipeId) async => calls.add('pull $recipeId');

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

  Future<FakeNotifier> pump(WidgetTester t, SaveSyncState s) async {
    final fake = FakeNotifier(s);
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: const MaterialApp(home: SaveSyncScreen()),
    ));
    await t.pump();
    return fake;
  }

  testWidgets('the row names the direction, and the verb does it', (t) async {
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
    // A download outranks an upload: the row owes the newer copy first, and
    // only one verb is ever offered.
    expect(find.textContaining('Needs download'), findsOneWidget);
    expect(find.textContaining('AYN Thor'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Upload'), findsNothing);
    await t.tap(find.widgetWithText(FilledButton, 'Download'));
    expect(fake.calls, ['refresh', 'pull stardew-valley']);
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

  testWidgets('Check opens a dialog with every line', (t) async {
    await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, games: [GameStatus(stardew, 'bundled', const Bound(binding))]),
    );
    await t.tap(find.byType(InkWell).first);
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
    await t.tap(find.byType(InkWell).first);
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
    expect(find.text('Save Sync'), findsWidgets);
  });

  testWidgets('before the first refresh has read the hub, neither the first run nor a hub row shows', (t) async {
    await pump(t, const SaveSyncState(googleAvailable: true));
    expect(find.text('Where should saves go?'), findsNothing);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('a build without Google offers only the folder', (t) async {
    await pump(t, const SaveSyncState(hubKind: HubKind.none));
    await t.pumpAndSettle();
    expect(find.text('Use a folder'), findsOneWidget);
    expect(find.textContaining('Sign in with Google'), findsNothing);
  });

  testWidgets('a Google hub shows the account with Sign out, and no folder note', (t) async {
    final fake = await pump(t, const SaveSyncState(hubKind: HubKind.drive, googleEmail: 'player@gmail.com', googleAvailable: true, access: SyncAccess.shizuku));
    expect(find.text('Google Drive: player@gmail.com'), findsOneWidget);
    expect(find.textContaining('Folder hub'), findsNothing);
    expect(find.text('Sign in again'), findsNothing);
    await t.tap(find.text('Sign out'));
    expect(fake.calls.last, 'sign out');
  });

  testWidgets('a folder hub shows its path, and Change switches to Google', (t) async {
    final fake = await pump(t, const SaveSyncState(hubKind: HubKind.folder, hubFolder: '/storage/emulated/0/Hub', googleAvailable: true, access: SyncAccess.shizuku));
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
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sign in with Google')).onPressed, isNull);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Use a folder')).onPressed, isNull);
    // One on the setup screen, one on the list behind it.
    expect(find.byType(LinearProgressIndicator), findsWidgets);
  });
}
