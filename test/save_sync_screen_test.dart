import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_screen.dart';
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

  testWidgets('shows each unit state and pushes and pulls the game', (t) async {
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
    expect(find.textContaining('Farm_1: push pending'), findsOneWidget);
    expect(find.textContaining('Farm_2: not on this device, pull available'), findsOneWidget);
    expect(find.textContaining('AYN Thor'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Push'));
    await t.tap(find.widgetWithText(OutlinedButton, 'Pull'));
    expect(fake.calls, ['refresh', 'push stardew-valley', 'pull stardew-valley']);
  });

  testWidgets('a blocked unit shows why, with the game status notes and no Pull', (t) async {
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
    expect(find.textContaining('Farm_2: Stardew Valley is running'), findsOneWidget);
    expect(find.text('Recovered an interrupted pull of Farm_1'), findsOneWidget);
    expect(find.text('Stardew Valley is running: close it to sync'), findsOneWidget);
    expect(t.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Pull')).onPressed, isNull);
  });

  testWidgets('without access it offers the Shizuku grant', (t) async {
    final fake = await pump(t, const SaveSyncState(shizukuRunning: true));
    await t.tap(find.text('Grant Shizuku access'));
    expect(fake.calls.last, 'grant');
  });

  testWidgets('Check opens a dialog with every line', (t) async {
    await pump(
      t,
      SaveSyncState(access: SyncAccess.shizuku, games: [GameStatus(stardew, 'bundled', const Bound(binding))]),
    );
    await t.tap(find.widgetWithText(TextButton, 'Check'));
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
    await t.tap(find.widgetWithText(TextButton, 'Check'));
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
    await t.tap(find.text('Confirm save location'));
    await t.pumpAndSettle();
    expect(find.text('SOS_SaveSlot0.sos'), findsOneWidget);
    await t.tap(find.text('Use this place'));
    await t.pumpAndSettle();
    expect(fake.calls.last, 'confirm sea-of-stars');
  });
}
