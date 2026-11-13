import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
import 'package:retro_toolbox/services/save_sync/gen.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/row_state.dart';
import 'package:retro_toolbox/services/save_sync/sync_planner.dart';


const binding = Binding(recipe: 'alpha', package: 'com.example.alpha', area: Area.androidData, root: 'files/Saves');

Recipe recipe() => Recipe.parse({
      'schema': 1,
      'id': 'alpha',
      'name': 'Alpha Title',
      'status': 'draft',
      'packages': ['com.example.alpha'],
      'locations': [
        {'area': 'androidData', 'root': 'files/Saves'},
      ],
      'unit': 'all',
      'include': ['*.sav'],
    });

GenMeta head(DateTime t, String device) => GenMeta(
      gen: makeGenId(t, 'dev', 'aaaaaaaa'),
      parents: const [],
      kind: 'save',
      recipe: 'alpha',
      unit: 'all',
      device: 'dev',
      deviceName: device,
      createdAt: t,
      package: 'com.example.alpha',
      files: const {},
      payloadSha256: 'x',
    );

GameStatus status(BindResult bind, {Map<String, UnitStatus> units = const {}, String? error}) =>
    GameStatus(recipe(), 'bundled', bind, units: units, error: error);

void main() {
  final t = DateTime.utc(2026, 11, 13, 1);

  test('a device with no access reads as blocked, never as a failure', () {
    final s = rowStateFor(status(const Bound(binding)), hasAccess: false);
    expect(s, isA<RowBlocked>());
    expect((s as RowBlocked).reason, BlockReason.noAccess);
  });

  test('a folder this device may not open is told apart from one needing root anywhere', () {
    expect(
      (rowStateFor(status(const NeedsRoot(binding, reason: NeedsRoot.refused)), hasAccess: true) as RowBlocked).reason,
      BlockReason.notOpenableHere,
    );
    expect(
      (rowStateFor(status(const NeedsRoot(binding)), hasAccess: true) as RowBlocked).reason,
      BlockReason.needsRoot,
    );
  });

  test('a conflict outranks a pending direction, and a download outranks an upload', () {
    final both = status(const Bound(binding), units: {
      'a': const UnitStatus(PushPlan('a', [])),
      'b': UnitStatus(PullPlan('b', head(t, 'Other'), missingLocally: true), newest: head(t, 'Other')),
    });
    expect(rowStateFor(both, hasAccess: true), isA<RowNeedsPull>());
    expect((rowStateFor(both, hasAccess: true) as RowNeedsPull).fromDevice, 'Other');

    final conflicted = status(const Bound(binding), units: {
      'a': const UnitStatus(PushPlan('a', [])),
      'b': UnitStatus(Diverged('b', [head(t, 'Other')], localDiffers: true)),
    });
    expect(rowStateFor(conflicted, hasAccess: true), isA<RowConflict>());
  });

  // The reason this exists: an emulator keeps one save per game under one
  // recipe, so one game being behind must not make another game read as behind.
  test('each save reads on its own, whatever the others owe', () {
    final mixed = status(const Bound(binding), units: {
      'ahead-here': const UnitStatus(PushPlan('ahead-here', [])),
      'ahead-there': UnitStatus(PullPlan('ahead-there', head(t, 'Other'), missingLocally: false), newest: head(t, 'Other')),
      'settled': const UnitStatus(UpToDate('settled')),
    });
    expect(rowStateForUnit(mixed, 'ahead-here', hasAccess: true), isA<RowNeedsPush>());
    expect(rowStateForUnit(mixed, 'ahead-there', hasAccess: true), isA<RowNeedsPull>());
    expect(rowStateForUnit(mixed, 'settled', hasAccess: true), isA<RowUpToDate>());
  });

  test('a device with no access blocks every save, not just the urgent one', () {
    final mixed = status(const Bound(binding), units: {
      'one': const UnitStatus(PushPlan('one', [])),
      'two': const UnitStatus(UpToDate('two')),
    });
    for (final u in ['one', 'two']) {
      expect((rowStateForUnit(mixed, u, hasAccess: false) as RowBlocked).reason, BlockReason.noAccess);
    }
  });

  test('the order puts what needs doing first and what cannot be done last', () {
    final ranks = [
      rowRank(const RowConflict()),
      rowRank(const RowNeedsPull(null, 'x')),
      rowRank(const RowNeedsPush(null)),
      rowRank(const RowUpToDate(null)),
      rowRank(const RowBlocked(BlockReason.needsRoot)),
      rowRank(const RowNotInstalled()),
    ];
    expect(ranks, orderedEquals([...ranks]..sort()));
  });
}
