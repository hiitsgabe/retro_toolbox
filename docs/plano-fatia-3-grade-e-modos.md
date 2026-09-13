# Slice 3, Grid and modes: implementation plan

> **For whoever executes:** MANDATORY SUB-SKILL: use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute task by task. The steps use checkboxes (`- [ ]`) for tracking.

**Goal:** make the grid tile represent a **game** instead of a **file**, when the console has a metadata pack, without regressing at all the console that does not have one.

**Architecture:** the app gains two grid modes, decided by a single predicate, "a pack exists for this console". SOURCE MODE is today's app, byte for byte. PACK MODE is a new grid, fed by a new entry type (`PackGridEntry`), which joins a `PackGame` from the pack with the list of files that the slice 2 `PackMatcher` matched to it. The choice of which file to download leaves the tile and goes to the detail screen and to the batch sheet, both driven by the same deterministic rule. Multiple selection, the footer bar and the confirmation sheet do not depend on any pack and are done first, in isolation, already improving today's app.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod: ^2.6.1`), Material 3 with seed `#7C4DEF` and ChakraPetch, `cached_network_image` for the covers, `flutter_test` without mockito, constructor injection. No new dependency in `pubspec.yaml`.

> **Post-execution note, about the `-1`.** Every "Expected: `+N -1`" in this plan counts on a permanent failure, `test/rar_decompress_screen_test.dart`. It was fixed in `5d21b14`, **after** the slice closed. On a HEAD from there on, each of these steps gives `+N` and no failure, and **any** failure is a regression. The detail is in Step 5 of Task 22.

---

## Before starting: read these four things

1. **`docs/stremio-de-jogos-ui.md` in full.** This plan implements sections 3, 4, 5, 6, 7 and the UI of section 8. Sections 9 and 10 belong to slices 4 and 6 and are **not** yours. Section 12 lists what is out of scope, and it holds: coverflow and list stay as they are.
2. **`docs/stremio-de-jogos-design.md`, section 7, "Grid modes"**, lines 428 to 445. It is eighteen lines and they define the whole slice. Read it together with the "Reading pitfall" further below in this plan, because section 7 has one line that misleads.
3. **`docs/plano-fatia-2-identidade.md`**, at least the "File structure" table. Everything that slice delivered is input to this one, and none of it should be reimplemented.
4. **`lib/models/metadata_pack_model.dart` and `lib/models/game_match_model.dart`.** These are the two types that cross this whole slice. `PackGame` is a canonical game with a list of `PackDump`; `GameMatch` is the matcher's verdict about a file name.

### Commands for this repository

`flutter` is not on the PATH. Every command line in this plan assumes:

```bash
export PATH=/home/exedev/flutter/bin:$PATH
cd /home/exedev/Workspace/retro_toolbox
```

- Whole suite: `flutter test`
- A single file: `flutter test test/selection_bar_test.dart`
- Analysis: `flutter analyze`

The `flutter test` output uses carriage returns, so `flutter test | tail` shows garbage. To see the end:

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -20
```

**Baseline before this slice**, checked by running, not by report: `flutter test` exits at `+178 -1`. The only failure is `test/rar_decompress_screen_test.dart`, in the case `renders with extract disabled until a file and folder are picked`, and it predates slice 1. It is not yours, do not try to fix it, and it has to remain the only one at the end. `flutter analyze` exits with **22 findings and zero errors**. The exact breakdown, because a vague allowlist already cost a round of QA in slice 2:

| File | Rule | How many | Origin |
| --- | --- | --- | --- |
| `tool/verify_matcher.dart` | `avoid_print` | 11 | slice 2, accepted |
| `tool/probe_zip_cd.dart` | `avoid_print` | 1 | slice 2, accepted |
| `lib/widgets/settings/network_address_setting.dart` | `deprecated_member_use` | 6 | preexisting |
| `lib/screens/fbi_server_screen.dart` | `use_build_context_synchronously` | 2 | preexisting |
| `test/webdav_server_test.dart` | `unnecessary_non_null_assertion` | 1 | preexisting |
| `lib/utils/rom_search.dart` | `dangling_library_doc_comments` | 1 | preexisting |

The acceptance criterion for this slice is **22, and no new finding in a file it touched**. It is not "only `avoid_print` is acceptable": the ten findings at the bottom were already there before slice 1 and are not your work.

### `pubspec.lock` lives dirty and never enters a commit

`git log -- pubspec.lock` stops at `c637fd5`, well before slice 1, and even so `git status` shows the file modified with 18 lines changed. These are transitive package downgrades (`matcher` 0.12.20 to 0.12.17, `material_color_utilities` 0.13.0 to 0.11.1, `characters` 1.4.1 to 1.4.0) that the local Flutter 3.35.7 rewrites on every `pub get`. It is nobody's work and comes back on its own.

Practical consequence, and it is mandatory: **`git add` always by explicit path**. Never `git add -A`, never `git add .`, never `git commit -a`. Every commit command in this plan already comes with the paths written out.

---

## Reading pitfall: the badge is not confidence

Section 7 of the architecture spec draws the two modes like this (design:435-439):

```
                    PACK MODE           SOURCE MODE
        grid = pack games            grid = addon listing
        cover/synopsis = pack        cover = console.boxarts
        badge = subsystem 2 match    badge = always available
```

Read literally, the line `badge = subsystem 2 match` seems to order painting the match **confidence** on the tile. **It does not, and doing so is an error.**

The axis of that table is **availability**, not confidence. In SOURCE MODE everything in the listing exists by definition, so the badge is always "available". In PACK MODE availability comes from the matcher having found something. In other words:

> The tile badge depends on `sources.isEmpty`, **never** on `match.confidence`. The three confidences (`confirmed`, `likely`, `guess`) give exactly the same tile.

This is CONCLUSION 3 and CONCLUSION 7 of the design review (task #10), and it is a locked decision of section 2 of the UI spec, line 32: *"Match confidence does not appear on the tile. Confidence is a property of the source, and a source only appears in the detail. The game exists, what is uncertain is one of its sources."*

The reason is not aesthetic, it is categorical: the tile represents a **game**, and a game can have several sources with different confidences, so there is no single tile confidence to paint.

Two independent design reviewers already proposed an uncertainty badge on the tile, and both times it was rejected. If you are reading this and thinking that a little uncertainty badge on the tile would solve it, you are the third. It does not.

## Second locked decision: CRC is not `MatchConfidence`

`MatchConfidence` is the **a priori** confidence, derived from the name tier, and slice 2 already produces it. The result of the CRC verification of section 8 of the UI spec is **a posteriori** and is another axis:

| Axis | Type | Values | Who produces it |
| --- | --- | --- | --- |
| A priori | `MatchConfidence` (already exists) | `confirmed`, `likely`, `guess` | slice 2, `game_match_model.dart` |
| A posteriori | `SourceVerification` (Task 18) | `notVerified`, `verifying`, `crcOk`, `crcDiscarded`, `impossible` | this slice |

A `confirmed` is born with a matched CRC and never goes through `verifying`. A `guess` goes through `verifying` and lands in `crcOk`, `crcDiscarded` or `impossible`.

**If you catch yourself adding a `crcOk` value to `MatchConfidence`, stop: it is wrong.** It is CONCLUSION 6 of task #10, which the two reviewers reached independently.

## Third locked decision: in PACK MODE no `Game` is synthesized

There were two ways out to feed the pack grid: synthesize a fake `Game` per `PackGame`, reusing the whole grid of today, or create a new entry type. **It is the new type.** Three reasons, all verified in the code:

1. `gameStateProvider` is a `Provider.family<GameState, Game>` (game_state_provider.dart:14) keyed by `game.gameId` (:16), and resolves state by calling `snap.getStatus(game.filename)` (:164) and `path.join(downloadDir, game.filename)` (:247). It is **file-keyed to the bone**. A synthetic `Game` without a real file would make this provider lie about download state.
2. `FilteringService._matchesFilter` literally has `if (metadata == null) return true;` (filtering_service.dart:59-60). A synthetic `Game` without metadata would pass through all the region, revision and dump quality filters, meaning the filter chips would become decorative and lying.
3. `_filterLatestRevisions` (filtering_service.dart:116-147) builds the key `'$baseTitle|$regions|$languages|$diskNumber'`, which with null metadata collapses into `'$title|||'`, and the final filtering compares by **object identity** (`latestByGameIdentity[gameIdentity] == game`). Since `Game` has no `operator ==`, two synthetics of the same title become one, silently. Measured on the real SNES pack: 2415 games, 2415 distinct titles, zero collision. The risk does not materialize today, so this is the **third** argument and not the first, but it is a trapdoor that makes no sense to leave armed.

Consequence: `game_grid_item.dart`, `game_grid.dart` and `filtering_service.dart` **are not modified by this slice**. PACK MODE gets its own widgets. This is a deliberate divergence from the table of section 11 of the UI spec, which speaks of "two variants per mode" inside `game_grid_item.dart`; the divergence protects `GameCoverFlow`, which reuses `GameGridItem` and is explicitly out of scope (UI spec, section 12).

## Fourth locked decision: the selection key in PACK MODE

Selection already exists and is a `Set<String>` in `CatalogState` (catalog_model.dart:13), read by `gameSelectionProvider`, a `Provider.family<bool, String>` (catalog_provider.dart:17). All this plumbing serves without modification, **as long as the PACK MODE string does not collide with the SOURCE MODE one**.

- In SOURCE MODE the key is `Game.gameId`, which is `'$consoleId/$filename'` (game_model.dart:86).
- `consoleId` comes from `CatalogService._nameToId` (catalog_service.dart:61-63), which is `[a-z0-9_]+`.
- `PackGame.id` is `'<pack_id>/<slug>'` (`tool/build_metadata_pack.py:237`), for example `snes/crystal-vanguard`. **It also has a slash, and it also starts with `[a-z0-9]`.** Using raw `PackGame.id` as the selection key is not provably disjoint from `Game.gameId`.

That is why the PACK MODE key is **`'pack:${packGame.id}'`**, with the literal prefix. The `:` character cannot appear in a `consoleId` generated by `_nameToId`, so the collision becomes impossible through the normal path.

Known and accepted edge: `catalog_service.dart:95-96` accepts a `consoles.json` in the legacy map format and uses the map key **verbatim**, without passing it through `_nameToId`. A hand-written `consoles.json` with a console whose id is `pack:snes` and a file named `crystal-vanguard` would collide. It is not worth code for this; it is worth the comment line that Task 10 orders written.

## Fifth locked decision: search yes, version chips no

In PACK MODE the grid does not pass through `FilteringService`, because that service operates over `List<Game>` and the pack grid has no `Game`. So:

- **The search box keeps working, and keeps being the same one.** `SearchField` (header.dart:102-107 and :145-150) keeps calling `catalogNotifier.updateFilterText(text)` (catalog_provider.dart:223-226), which keeps storing `filterText` in the `CatalogState`. What changes is only the consumer: in PACK MODE the one who reads `filterText` is `filterPackEntries` (Task 9), pure Dart, no isolate. It is 2415 entries and a `contains` on a lowercase string; measuring that in an isolate would be ceremony without gain.
- **The region, revision and dump quality chips stay out of the pack grid.** Region, revision and quality are properties of a **version**, and in PACK MODE the grid has no version, so these filters have no subject. Filtering the grid by "has a dump in that region" would hide games based on a property that the tile does not even show, contradicting the whole premise of section 3.1 of the UI spec ("the tile marks only the exception", not "the tile disappears").
- `filter.regions` **does not die**: it goes on to feed the version choice rule (Task 14), which is where region has a subject. It is exactly what the table of section 11 of the UI spec foresees for `catalog_filter_model.dart`.
- UI consequence, and it is mandatory: in PACK MODE the header funnel button **does not disappear**, it changes label. Task 19 handles this.

---

## Sixth locked decision: no test touches the favorites disk

This section exists because the first version of this plan was **wrong** on this point, and the error was caught by running the code in Task 1. It is written here in full so that nobody repeats it.

`CatalogNotifier` listens to `favoritesProvider` in the constructor (`catalog_provider.dart:38`), and `FavoritesNotifier` calls `_loadFavorites()` inside its own constructor (`favorites_provider.dart:9`), which goes to disk via `path_provider`. Any test that builds a real `catalogProvider`, in a `ProviderContainer` or in a `ProviderScope`, inherits this. **Verified by running**, and there are two distinct defects, not one:

1. With nothing, the test passes and **then** throws `MissingPluginException(No implementation found for method getApplicationSupportDirectory on channel plugins.flutter.io/path_provider)`. `flutter test` counts this as a failure of the case that had already passed.
2. Registering a fake handler for the `path_provider` channel, the `MissingPluginException` disappears and the second, harder defect appears: `_loadFavorites` is `async` and the assignment `state = await ...` completes **after** the `addTearDown(container.dispose)`, so it throws `Bad state: Tried to use FavoritesNotifier after 'dispose' was called`. With a single case this sometimes does not appear, by scheduling luck. With two, it always does.

`TestWidgetsFlutterBinding.ensureInitialized()` **fixes neither one**. The binding does not register the `path_provider` channel, and it has nothing to do with the `dispose` race. If you saw that line somewhere in this plan as the fix, the plan was wrong.

**The fix, and it is mandatory:** override `favoritesProvider` with an in-memory version. Task 1 creates `test/support/favorites_stub.dart` with `InMemoryFavoritesNotifier` and the constant `withoutFavoritesDisk`, and **every** test of this slice that builds a real `catalogProvider` has to put `withoutFavoritesDisk` in the `overrides` list. They are: Task 1, Task 12, Task 15, Task 16, Task 18 and Task 21.

The stub keeps favorites in memory for real, with a `toggleFavorite` that works, and is **not** a no-op. This is not a whim: the tests of Tasks 15 and 18 hold their breath and expect the icon to become `Icons.favorite`. With a stub that does nothing, those tests would fail, and the wrong fix would be to loosen the assertion.

---

## File structure

Fifteen new production files. **Three** existing production files modified. `pubspec.yaml` does not change.

### New

| File | Responsibility | Depends on |
| --- | --- | --- |
| `lib/models/grid_entry_model.dart` | `PackGridEntry` (a `PackGame` plus the sources matched to it), `MatchedSource` (a matched source, with confidence and size) and `kPackSelectionPrefix`. Pure Dart. | `metadata_pack_model`, `game_match_model` |
| `lib/models/source_verification_model.dart` | `SourceVerification`, the a posteriori CRC axis. Pure Dart. | nothing |
| `lib/models/source_pick_model.dart` | `SourcePick`, `PickFailure` and `kBuiltinAddonId`. Pure Dart. | `game_model` |
| `lib/services/source_index.dart` | Inverted index game to sources, built once per console. Pure Dart. | `pack_matcher`, `game_match_model` |
| `lib/services/pack_grid_filter.dart` | Text search and sorting of the pack grid (`filterPackEntries`, Task 9), plus the per-mode selection slicing (`entriesForSelection` and `selectionKeysFor`, Task 20). Pure Dart. | `grid_entry_model`, `pack_naming` |
| `lib/services/source_pick_service.dart` | Produces `BatchPlan`. Born in Task 6 with the trivial SOURCE MODE case (`planFromGames`) and gains in Task 14 the rule of section 6 of the UI spec: region, revision, confidence, priority. Pure Dart. | `game_model`, `grid_entry_model`, `source_pick_model` |
| `lib/providers/pack_grid_provider.dart` | `gridModeProvider`, `sourceIndexProvider`, `allPackEntriesProvider`, `packGridEntriesProvider`, and the two test seams `packTargetProvider` and `catalogGamesProvider`. | everything above, `identity_provider`, `catalog_provider` |
| `lib/providers/owned_games_provider.dart` | Set of `PackGame` ids that are already on disk. | `identity_provider`, `settings_provider` |
| `lib/services/source_verification_service.dart` | Answers "does this remote file contain a dump of this game?" by reading the CRC via `Range`. Pure Dart. | `pack_matcher`, `zip_central_directory`, `source_verification_model` |
| `lib/providers/source_verification_provider.dart` | Trigger and cache of the CRC verification, per (source, file). | `source_verification_service`, `identity_provider` |
| `lib/widgets/footer/selection_bar.dart` | The purple strip of section 5 of the UI spec. Pure widget. | nothing |
| `lib/widgets/game_grid/batch_confirm_sheet.dart` | The confirmation sheet of section 6. Pure widget. | `source_pick_model` |
| `lib/widgets/game_grid/pack_grid_item.dart` | The PACK MODE tile. Pure widget. | nothing (receives primitives) |
| `lib/widgets/game_grid/pack_grid.dart` | The PACK MODE grid, with the empty state strip of section 3.2. | `pack_grid_item`, `pack_grid_provider` |
| `lib/screens/game_detail_screen.dart` | The screen of sections 7 and 8. | almost everything above |

### Modified

| File | What changes | In Task |
| --- | --- | --- |
| `lib/providers/catalog_provider.dart` | gains `clearSelection()` | 1 |
| `lib/widgets/header/header.dart` | the "Download Selected" button goes away (`:184-195`), the funnel gains a per-mode label | 3 and 19 |
| `lib/screens/home_screen.dart` | the `SelectionBar`, the batch sheet and the mode routing come in | 3, 6 and 19 |
| `lib/services/task_queue_service.dart` | none. **It is here on purpose.** An earlier version of this table promised a `startDownloadsFromPicks`. It does not exist: the body would be `startDownloads(ref, context, picks.map((p) => p.game).toList(), consoleId)` and nothing else, because `SourcePick` already carries the whole `Game`. A one-line alias is not tested and does not pay for the file touched | none |
| `lib/widgets/footer/footer.dart` | none. **It is here on purpose, to say that it does not change.** The selection bar sits *above* it, as a sibling in the `Column`, and not inside it | none |

### Untouched, and this is a requirement

`lib/widgets/game_grid/game_grid_item.dart`, `lib/widgets/game_grid/game_grid.dart`, `lib/widgets/game_grid/game_cover_flow.dart`, `lib/services/filtering_service.dart`, the whole of `lib/widgets/game_list/`. Note the coverflow path: it lives **inside** `lib/widgets/game_grid/`, and not in a directory of its own, so the check of that directory is file by file and not all at once, because the slice creates three new files in there. SOURCE MODE is today's app and has to remain so. Task 22 proves this with `git diff --stat`.

---

**One test support file**, which is not production and therefore does not appear in the `lib/` check of Task 22:

| File | Responsibility | Depends on |
|---|---|---|
| `test/support/favorites_stub.dart` | `InMemoryFavoritesNotifier` and the constant `withoutFavoritesDisk`, the `favoritesProvider` override that removes the disk and the `async` race from the path. Created in Task 1, used by Tasks 1, 12, 15, 16, 18 and 21. See the "Sixth locked decision". | `favorites_provider`, `favorites_model` |

## Commit convention for this slice

Each Task below is split between a test agent and a production agent, and therefore **each Task brings two commit messages**, never one:

- `test(<scope>): <text>` for the commit that only touches `test/`
- `feat(<scope>): <same text>` for the commit that only touches `lib/`

The descriptive text is the same in both. In slice 2 the absence of this rule produced eleven pairs of commits with identical messages, and resolving "which is which" only worked through `git show --stat`.

**Homogeneity rule:** a commit touches either only `lib/`, or only `test/`. The two legitimate exceptions are `tool/` and `docs/`, which can accompany either of the two. In slice 2 the QA had to decide this alone in commit `15520e2`; now it is written.

Scopes used in this slice: `selecao`, `lote`, `grade`, `detalhe`, `crc`.

---

# Group 1: selection and batch

This group does not touch pack, matcher or addon. It improves today's app on its own and can start before anything else. It is the "useful exception" of section 13 of the UI spec.

---

### Task 1: `clearSelection` on `CatalogNotifier`

**Files:**
- Modify: `lib/providers/catalog_provider.dart`
- Test: `test/catalog_selection_test.dart`

The `×` of the footer bar needs to clear the entire selection, and that method does not exist. Today there is only `toggleGameSelection` (`:228`), `selectGame` (`:240`) and `deselectGame` (`:246`).

- [ ] **Step 1: Create the favorites stub that the whole slice will use**

Read the "Sixth locked decision" before this step. In short: a real `catalogProvider` goes to disk and throws after the test, and this file is the fix, used by six Tasks.

Create `test/support/favorites_stub.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/favorites_model.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';

/// In-memory favorites, no disk and no `async` that outlives the test.
///
/// The real `FavoritesNotifier` calls `_loadFavorites()` in the constructor,
/// which goes to `path_provider`. In tests this gives `MissingPluginException`,
/// and if you silence the channel, it gives `Bad state: Tried to use
/// FavoritesNotifier after dispose` because the `await` completes after teardown.
///
/// Keeps favorites for real, and is not a no-op: Tasks 15 and 18 hold their
/// breath and expect the icon to flip.
class InMemoryFavoritesNotifier extends StateNotifier<Favorites>
    implements FavoritesNotifier {
  InMemoryFavoritesNotifier()
      : super(Favorites(lastUpdated: DateTime.fromMillisecondsSinceEpoch(0)));

  @override
  Future<void> toggleFavorite(String gameId) async {
    final ids = Set<String>.from(state.gameIds);
    ids.contains(gameId) ? ids.remove(gameId) : ids.add(gameId);
    state = state.copyWith(gameIds: ids);
  }

  @override
  Future<void> addFavorite(String gameId) async {
    state = state.copyWith(gameIds: Set<String>.from(state.gameIds)..add(gameId));
  }

  @override
  Future<void> removeFavorite(String gameId) async {
    state = state.copyWith(gameIds: Set<String>.from(state.gameIds)..remove(gameId));
  }

  @override
  Future<void> clearFavorites() async {
    state = state.copyWith(gameIds: {});
  }

  @override
  Future<String> exportFavorites() async => 'stub';

  @override
  Future<void> importFavorites(String slug, {bool merge = true}) async {}

  @override
  Future<void> deleteExport() async {}

  @override
  bool isFavorite(String gameId) => state.isFavorite(gameId);
}

/// Put this in the `overrides` list of every test that builds a real
/// `catalogProvider`, in a container or in a `ProviderScope`.
final withoutFavoritesDisk =
    favoritesProvider.overrideWith((_) => InMemoryFavoritesNotifier());
```

- [ ] **Step 2: Write the tests that fail**

Create `test/catalog_selection_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';

import 'support/favorites_stub.dart';

void main() {
  test('clearSelection empties the whole selection', () {
    final container = ProviderContainer(overrides: [withoutFavoritesDisk]);
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    notifier.selectGame('snes/a.zip');
    notifier.selectGame('snes/b.zip');
    expect(container.read(catalogProvider).selectedGames, {'snes/a.zip', 'snes/b.zip'});

    notifier.clearSelection();

    expect(container.read(catalogProvider).selectedGames, isEmpty);
  });

  test('clearSelection emits no state when the selection is already empty', () {
    final container = ProviderContainer(overrides: [withoutFavoritesDisk]);
    addTearDown(container.dispose);
    final notifier = container.read(catalogProvider.notifier);

    var emissions = 0;
    container.listen(catalogProvider, (_, __) => emissions++);

    notifier.clearSelection();

    // The whole grid rebuilds on every catalogProvider emission. Clearing a
    // selection that is already empty must not cost that.
    expect(emissions, 0);
  });
}
```

- [ ] **Step 3: Run and watch it fail**

```bash
flutter test test/catalog_selection_test.dart
```

Expected: compile failure, `The method 'clearSelection' isn't defined for the type 'CatalogNotifier'`.

If instead you see `MissingPluginException` or `Tried to use FavoritesNotifier after dispose`, Step 1 was not done or `withoutFavoritesDisk` did not enter the `overrides`.

- [ ] **Step 4: Implement**

In `lib/providers/catalog_provider.dart`, right after `deselectGame` (which ends at line 250), add:

```dart
  /// Clears the whole selection. It is the `×` of the footer bar.
  ///
  /// The empty guard is not a micro-optimization: the whole grid listens to
  /// `catalogProvider`, so emitting an equal state costs a screen rebuild.
  void clearSelection() {
    if (state.selectedGames.isEmpty) return;
    state = state.copyWith(selectedGames: {});
  }
```

- [ ] **Step 5: Run and watch it pass**

```bash
flutter test test/catalog_selection_test.dart
```

Expected: `+2`, zero failures.

- [ ] **Step 6: Commit**

Two messages, one per agent. The stub goes with the test commit, because it is a test file:

```bash
# test agent
git add test/support/favorites_stub.dart test/catalog_selection_test.dart
git commit -m "test(selecao): clearSelection zera a selecao sem emitir a toa"

# production agent
git add lib/providers/catalog_provider.dart
git commit -m "feat(selecao): clearSelection zera a selecao sem emitir a toa"
```

---

### Task 2: the `SelectionBar` widget

**Files:**
- Create: `lib/widgets/footer/selection_bar.dart`
- Test: `test/selection_bar_test.dart`

The purple strip of section 5 of the UI spec. It sits **above** the `Footer`, as its sibling in the `HomeScreen` `Column`, and **not inside** it: `footer.dart` is not modified by this slice.

Pure widget, in the house idiom: it receives a number and callbacks, does not know Riverpod, and is tested standalone inside `MaterialApp`/`Scaffold` without a `ProviderScope`. The model is `test/menu_grid_test.dart`.

- [ ] **Step 1: Write the tests that fail**

Create `test/selection_bar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';

Widget _host({required int count, VoidCallback? onClear, VoidCallback? onDownload}) {
  return MaterialApp(
    home: Scaffold(
      body: SelectionBar(
        count: count,
        onClear: onClear ?? () {},
        onDownload: onDownload ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('takes no height when the selection is empty', (tester) async {
    await tester.pumpWidget(_host(count: 0));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Download'), findsNothing);
    expect(tester.getSize(find.byType(SelectionBar)).height, 0);
  });

  testWidgets('singular count with one item', (tester) async {
    await tester.pumpWidget(_host(count: 1));

    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('plural count with more than one item', (tester) async {
    await tester.pumpWidget(_host(count: 3));

    expect(find.text('3 selected'), findsOneWidget);
  });

  testWidgets('takes exactly 48 height with a selection', (tester) async {
    await tester.pumpWidget(_host(count: 3));

    // The opposite of the first case, not a redundancy of it: `IconButton`
    // and `FilledButton` measure 48 on their own because of Material's default
    // touch target, so `SizedBox(height: 48)` has no slack. Any extra padding
    // overflows the strip, and without this case nothing warns.
    expect(tester.getSize(find.byType(SelectionBar)).height, 48);
  });

  testWidgets('the × calls onClear and the button calls onDownload', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(_host(
      count: 3,
      onClear: () => fired.add('clear'),
      onDownload: () => fired.add('download'),
    ));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(fired, ['clear', 'download']);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/selection_bar_test.dart
```

Expected: compilation error, `Target of URI doesn't exist: 'package:roms_downloader/widgets/footer/selection_bar.dart'`.

- [ ] **Step 3: Implement**

Create `lib/widgets/footer/selection_bar.dart`:

```dart
import 'package:flutter/material.dart';

/// The selection strip of section 5 of the UI spec.
///
/// Sits above the `Footer`, as its sibling in the HomeScreen Column, never
/// inside it: the two stay active at the same time and neither hides the other.
///
/// Pure widget on purpose: it receives a number and callbacks and does not know
/// Riverpod. The one that wires the provider is the HomeScreen (Task 3).
class SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onClear;
  final VoidCallback onDownload;

  const SelectionBar({
    super.key,
    required this.count,
    required this.onClear,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    // Disappears on its own when it zeroes. SizedBox.shrink and not Visibility,
    // because the bar must reserve no height with an empty selection.
    if (count == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary,
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              color: scheme.onPrimary,
              tooltip: 'Clear selection',
              onPressed: onClear,
            ),
            Expanded(
              child: Text(
                count == 1 ? '1 selected' : '$count selected',
                // Same policy as `footer.dart:99-100`, and for the same reason:
                // the strip has a fixed height, so with a large `textScaler` on
                // a narrow screen the paragraph asks for more height than it gets
                // and is clipped mid-word, with no ellipsis and no yellow
                // overflow strip. Measured at 320dp and 360dp with scale 2.0.
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonal(
                onPressed: onDownload,
                child: const Text('Download'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/selection_bar_test.dart
```

Expected: `+5`, zero failures.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/selection_bar_test.dart
git commit -m "test(selecao): barra do rodape com contador, x e botao baixar"

# production agent
git add lib/widgets/footer/selection_bar.dart
git commit -m "feat(selecao): barra do rodape com contador, x e botao baixar"
```

---

### Task 3: wire the bar and remove the button from the header

**Files:**
- Modify: `lib/screens/home_screen.dart:96`
- Modify: `lib/widgets/header/header.dart:183-196`
- Test: none new. See the test note below.

**Test note, read before complaining about the absence.** `HomeScreen` depends on `appStateProvider`, which loads the catalog from disk and network in the constructor, and `Header` depends on `CatalogService`. Mounting that screen in a widget test would require faking half a dozen providers, and the value of that is low next to the cost: the widget is already tested standalone in Task 2 and the notifier in Task 1. What this Task changes is three lines of wiring. Its proof is a clean `flutter analyze` plus the whole suite green, in Step 4.

- [ ] **Step 1: Wire the bar into the `HomeScreen`**

In `lib/screens/home_screen.dart`, add the import together with the other widget ones (after line 10):

```dart
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
```

And replace line 96, which today is just `Footer(),`, with:

```dart
          SelectionBar(
            count: ref.watch(catalogProvider.select((s) => s.selectedGames.length)),
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () {
              final catalogState = ref.read(catalogProvider);
              final selectedGames =
                  catalogState.games.where((g) => catalogState.selectedGames.contains(g.gameId)).toList();
              TaskQueueService.startDownloads(ref, context, selectedGames, appState.selectedConsole?.id);
            },
          ),
          Footer(),
```

The `select` over `selectedGames.length` is on purpose: it cuts the rebuilds on every catalog change and lets through only the ones where the **number** changes.

**But say that precisely, because the first version of this paragraph was wrong and a QA review caught it.** The `watch` is inside the `build` of `_HomeScreenState`, so what rebuilds when the number changes is the whole `HomeScreen`, not the bar alone. A `select` narrows the trigger, never the target: the target is always the widget that called the `watch`. Narrowing the target for real would be to put a `Consumer` around the bar, and this slice does not do that: Task 21 touches the bar again and the decision of where it lives stays there.

The body of `onDownload` is the same one that was in the header (`header.dart:190-191`), with **one** mandatory swap: there the console comes from `widget.selectedConsole?.id`, because `Header` receives the console as a parameter; here it comes from `appState.selectedConsole?.id`, because `HomeScreen` already reads `appStateProvider`. Copying `widget.selectedConsole` into `HomeScreen` does not compile. Other than that it is the same line. In Task 5 it goes on to call the confirmation sheet; here it only changes place, so the commit is a single thing.

Also add the import of the queue service:

```dart
import 'package:roms_downloader/services/task_queue_service.dart';
```

- [ ] **Step 2: Remove the button from the header**

In `lib/widgets/header/header.dart`, delete lines **183 to 195, inclusive**. Check before deleting that 183 is `      SizedBox(width: 4),`, 184 is `      _buildActionButton(` and **195 is `      ),`**.

> **Mind the range.** Section 11 and section 5 of the UI spec say `:186-194`. It is wrong at both ends. The real block is `184-195`, and there is a `SizedBox(width: 4)` on **both** sides, at 183 and 196. Deleting up to 194 leaves an orphan `),` and does not compile; deleting 184-195 without taking a spacer along leaves double spacing between the funnel and the view mode button. That is why the range to delete is 183-195: it takes the top spacer along.

After deleting, `_buildActionWidgets` has to look like this (lines 175 onward, with the funnel next to the view mode button):

```dart
    return [
      _buildActionButton(
        context: context,
        icon: catalogState.filter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
        isActive: catalogState.filter.isActive,
        onPressed: () => FilterModal.show(context),
        tooltip: 'Filters',
      ),
      SizedBox(width: 4),
      _buildActionButton(
```

- [ ] **Step 3: Clean up what is left**

Deleting that block leaves `canDownload` and the `TaskQueueService` import possibly unused in `header.dart`. Run:

```bash
flutter analyze lib/widgets/header/header.dart
```

If `unused_import` or `unused_element` shows up, delete what it points at. If `canDownload` is still used by another button, leave it. **Do not guess: run and obey the analyzer.**

- [ ] **Step 4: Prove nothing broke**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Expected: 22 findings and zero errors in analyze; `+185 -1` in the suite (178 from the baseline plus 2 from Task 1 and 5 from Task 2).

- [ ] **Step 5: Commit**

This Task is production only, so it has **one** message only, and this is the exception, not the rule:

```bash
git add lib/screens/home_screen.dart lib/widgets/header/header.dart
git commit -m "feat(selecao): barra do rodape substitui o botao Download Selected do header"
```

---

### Task 4: `SourcePick`, `PickFailure` and `BatchPlan`

**Files:**
- Create: `lib/models/source_pick_model.dart`
- Test: `test/source_pick_model_test.dart`

The result of the batch rule of section 6 of the UI spec. It is born here, in Group 1, even though the rule that produces it only arrives in Task 14, because the confirmation sheet of Task 5 needs a type to draw and the alternative would be to draw over `Game` and rewrite everything later.

In SOURCE MODE each selected item **already is** a file, so the "choice" is trivial and the reason is the same for all. In PACK MODE Task 14 fills `reason` and `uncertain` for real. The type is the same in both cases, and that is what makes the sheet be written only once.

- [ ] **Step 1: Write the tests that fail**

Create `test/source_pick_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';

Game _game(String name, int size) => Game(
      title: name,
      url: 'https://example/$name',
      size: size,
      consoleId: 'snes',
    );

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listing',
      reason: 'chosen by your preferred region',
      uncertain: uncertain,
      game: _game(name, size),
    );

void main() {
  test('totalBytes sums the size of every pick', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 1000), _pick('b.zip', 2400)]);

    expect(plan.totalBytes, 3400);
  });

  test('totalBytes is zero in a plan with no picks', () {
    const plan = BatchPlan();

    expect(plan.totalBytes, 0);
    expect(plan.isEmpty, isTrue);
  });

  test('uncertainCount counts only the picks marked uncertain', () {
    final plan = BatchPlan(picks: [
      _pick('a.zip', 10),
      _pick('b.zip', 10, uncertain: true),
      _pick('c.zip', 10, uncertain: true),
    ]);

    expect(plan.uncertainCount, 2);
  });

  test('withoutPick removes a pick and preserves the failures', () {
    final plan = BatchPlan(
      picks: [_pick('a.zip', 10), _pick('b.zip', 20)],
      failures: const [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    );

    final smaller = plan.withoutPick('snes/a.zip');

    expect(smaller.picks.map((p) => p.gameId), ['snes/b.zip']);
    expect(smaller.failures.single.title, 'C');
    // The original plan does not change: the sheet keeps the previous one to undo.
    expect(plan.picks.length, 2);
  });

  test('withoutPick of an id not in the plan returns the same content', () {
    final plan = BatchPlan(picks: [_pick('a.zip', 10)]);

    expect(plan.withoutPick('snes/does-not-exist').picks.length, 1);
  });

  test('a failures-only plan is not empty', () {
    const plan = BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    );

    // Matters because the sheet must open to explain why nothing will be
    // downloaded, instead of disappearing without saying anything.
    expect(plan.isEmpty, isFalse);
    expect(plan.picks, isEmpty);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/source_pick_model_test.dart
```

Expected: `Target of URI doesn't exist: 'package:roms_downloader/models/source_pick_model.dart'`.

- [ ] **Step 3: Implement**

Create `lib/models/source_pick_model.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_model.dart';

/// The source id of the listings that already ship in `consoles.json`.
///
/// In this slice there is only one source per console, so the value is
/// constant. In slice 4 it becomes the id of the addon that served the file,
/// and that is why [SourcePick.sourceId] and `MatchedSource.sourceId` are
/// fields instead of being implicit.
///
/// It lives in this file for a reason of order, not of taste: it is the first
/// pure Dart file of this slice to exist, and both `source_pick_service.dart`
/// (Task 6) and `pack_grid_provider.dart` (Task 10) need the constant. Putting
/// it in the provider would drag Riverpod into a service that runs outside
/// Flutter; putting it in `grid_entry_model.dart` would make it be born three
/// Tasks after the first use.
const kBuiltinAddonId = 'builtin';

/// A chosen version for a game, with the reason written out in full.
///
/// The reason is mandatory and not decorative: it is the only thing that
/// separates "the app chose for you" from "the app chose at random" (UI spec,
/// section 7).
@immutable
class SourcePick {
  /// The game's selection key. In SOURCE MODE it is `Game.gameId`; in PACK MODE
  /// it is `'pack:${packGame.id}'`. The sheet does not need to know which.
  final String gameId;
  final String title;
  final String filename;

  /// Bytes. Zero when the source declares no size, and in that case the sheet
  /// shows the total as approximate.
  final int size;

  /// Which source it came from. In this slice it is always [kBuiltinAddonId]
  /// and in slice 4 it is the addon id. It is what the "4.0 MB, Myrient" line
  /// of section 7 shows, and that is why it is born here instead of in slice 4.
  final String sourceId;
  final String reason;

  /// Marks the uncertainty badge of section 6. It is `true` when the match
  /// confidence is `guess`. The batch does **not** verify CRC before enqueueing.
  final bool uncertain;

  /// What actually goes to the queue. The sheet never reads this field: it draws
  /// the display fields above and returns the whole picks.
  final Game game;

  const SourcePick({
    required this.gameId,
    required this.title,
    required this.filename,
    required this.size,
    required this.sourceId,
    required this.reason,
    required this.game,
    this.uncertain = false,
  });
}

/// A selected game that does not go to the queue, with the reason.
@immutable
class PickFailure {
  final String gameId;
  final String title;
  final String reason;

  const PickFailure({
    required this.gameId,
    required this.title,
    required this.reason,
  });
}

/// What the confirmation sheet of section 6 draws: what goes and what does not.
@immutable
class BatchPlan {
  final List<SourcePick> picks;
  final List<PickFailure> failures;

  const BatchPlan({this.picks = const [], this.failures = const []});

  int get totalBytes => picks.fold(0, (sum, pick) => sum + pick.size);

  int get uncertainCount => picks.where((pick) => pick.uncertain).length;

  /// Truly empty: nothing to download and nothing to explain. A failures-only
  /// plan is **not** empty, because the sheet needs to open to say why.
  bool get isEmpty => picks.isEmpty && failures.isEmpty;

  /// Removes an item from the batch. Returns a new plan; the original does not change.
  BatchPlan withoutPick(String gameId) => BatchPlan(
        picks: picks.where((pick) => pick.gameId != gameId).toList(),
        failures: failures,
      );
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/source_pick_model_test.dart
```

Expected: `+6`, zero failures.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/source_pick_model_test.dart
git commit -m "test(lote): SourcePick, PickFailure e os totais do BatchPlan"

# production agent
git add lib/models/source_pick_model.dart
git commit -m "feat(lote): SourcePick, PickFailure e os totais do BatchPlan"
```

---

### Task 5: the batch confirmation sheet

**Files:**
- Create: `lib/widgets/game_grid/batch_confirm_sheet.dart`
- Test: `test/batch_confirm_sheet_test.dart`

Section 6 of the UI spec: "40 games, 1.2 GB", the list of what was chosen, and the ones that do not go in appearing separately with the reason.

**Scope of this Task, and read this line before complaining about short scope.** Section 6 speaks of "per-item override". Override has two meanings: *remove from the batch* and *swap the chosen version*. Removing from the batch is what this Task does, and it works in both modes. Swapping the version only has a subject in PACK MODE, where there is more than one version, and it arrives in Task 20. Do not invent a version selector here: there is nothing to select.

The widget is pure: it receives a `BatchPlan` and two callbacks, and does not know Riverpod nor `showModalBottomSheet`. The one that opens the sheet is Task 6.

- [ ] **Step 1: Write the tests that fail**

Create `test/batch_confirm_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listing',
      reason: 'chosen by your preferred region',
      uncertain: uncertain,
      game: Game(title: name, url: 'https://example/$name', size: size, consoleId: 'snes'),
    );

Widget _host(BatchPlan plan, {ValueChanged<BatchPlan>? onConfirm, ValueChanged<String>? onRemove}) {
  return MaterialApp(
    home: Scaffold(
      body: BatchConfirmSheet(
        plan: plan,
        onConfirm: onConfirm ?? (_) {},
        onRemove: onRemove ?? (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows the count and total in the header', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('a.zip', 1024 * 1024),
      _pick('b.zip', 1024 * 1024),
    ])));

    expect(find.text('2 games, 2.0 MB'), findsOneWidget);
  });

  testWidgets('uses singular with a single game', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('a.zip', 1024)])));

    expect(find.text('1 game, 1.0 KB'), findsOneWidget);
  });

  testWidgets('lists the file name and the reason of each pick', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('Crystal.zip', 1024)])));

    expect(find.text('Crystal.zip'), findsOneWidget);
    expect(find.text('chosen by your preferred region'), findsOneWidget);
  });

  testWidgets('badges only the uncertain picks', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certain.zip', 1024),
      _pick('doubt.zip', 1024, uncertain: true),
    ])));

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('separates the ones that do not go to the queue, with the reason', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'No source', reason: 'no addon has this game')],
    )));

    expect(find.text('Not going to the queue'), findsOneWidget);
    expect(find.text('No source'), findsOneWidget);
    expect(find.text('no addon has this game'), findsOneWidget);
  });

  testWidgets('the remove button returns the gameId of that row', (tester) async {
    final removed = <String>[];
    await tester.pumpWidget(_host(
      BatchPlan(picks: [_pick('a.zip', 1024), _pick('b.zip', 1024)]),
      onRemove: removed.add,
    ));

    await tester.tap(find.byKey(const ValueKey('remove-snes/b.zip')));
    await tester.pump();

    expect(removed, ['snes/b.zip']);
  });

  testWidgets('confirm returns the whole plan', (tester) async {
    BatchPlan? confirmed;
    final plan = BatchPlan(picks: [_pick('a.zip', 1024)]);
    await tester.pumpWidget(_host(plan, onConfirm: (p) => confirmed = p));

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(confirmed, same(plan));
  });

  testWidgets('with no picks the download button is disabled', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    )));

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download'));
    expect(button.onPressed, isNull);
  });

  testWidgets('the header counts the uncertainties, and disappears when there are none', (tester) async {
    // The per-row badge already had a test; the header count did not, and it
    // has its own plural. The three branches in a single case on purpose: it is
    // a text rule, and three separate cases would cost three times the same
    // scenario to prove the same sentence.
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certain.zip', 1024),
      _pick('doubt.zip', 1024, uncertain: true),
      _pick('other.zip', 1024, uncertain: true),
    ])));
    expect(find.text('2 uncertain'), findsOneWidget);

    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certain.zip', 1024),
      _pick('doubt.zip', 1024, uncertain: true),
    ])));
    expect(find.text('1 uncertain'), findsOneWidget);

    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('certain.zip', 1024)])));
    expect(find.textContaining('uncertain'), findsNothing);
  });

  testWidgets('Cancel closes the sheet without confirming anything', (tester) async {
    // Needs a real route: the sheet calls `maybePop`, and with it mounted
    // straight in the `body` there is nothing to pop, so the test would pass
    // without proving anything. Here it comes up as a modal, the way
    // `_confirmBatch` brings it up in production.
    var confirmedCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<BatchPlan>(
              context: context,
              builder: (_) => BatchConfirmSheet(
                plan: BatchPlan(picks: [_pick('a.zip', 1024)]),
                onConfirm: (_) => confirmedCount++,
                onRemove: (_) {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BatchConfirmSheet), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(BatchConfirmSheet), findsNothing);
    expect(confirmedCount, 0);
  });

  testWidgets('with only failures the header says zero games, and the sheet stays open', (tester) async {
    // The sheet does not close itself when nothing can be downloaded: it exists
    // precisely to show the reason (section 6). The header must tell the truth
    // in that state, and the plural of zero is "games".
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    )));

    expect(find.text('0 games, 0 B'), findsOneWidget);
    expect(find.text('no source'), findsOneWidget);
  });
}
```

> **The last three cases came in later**, in a QA caveat accepted when the slice was already at Task 13. They covered three things the sheet did and no test asserted: the uncertainty count in the header, the `Cancel` button and the header in the "failures only" state. Whoever executes Task 5 from scratch writes the eleven at once; the table cumulative at the end of the plan already counts the eleven.

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/batch_confirm_sheet_test.dart
```

Expected: `Target of URI doesn't exist: '.../batch_confirm_sheet.dart'`.

- [ ] **Step 3: Implement**

Create `lib/widgets/game_grid/batch_confirm_sheet.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// The confirmation sheet of section 6 of the UI spec.
///
/// Pure widget: it receives the plan and two callbacks. The one that opens it
/// in `showModalBottomSheet` and the one that enqueues is the caller.
class BatchConfirmSheet extends StatelessWidget {
  final BatchPlan plan;
  final ValueChanged<BatchPlan> onConfirm;

  /// Receives the `gameId` of the row to remove from the batch. The caller is
  /// the one that keeps the current plan and applies `plan.withoutPick`.
  final ValueChanged<String> onRemove;

  const BatchConfirmSheet({
    super.key,
    required this.plan,
    required this.onConfirm,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = plan.picks.length;
    final header = '$n ${n == 1 ? 'game' : 'games'}, ${formatBytes(plan.totalBytes)}';

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                if (plan.uncertainCount > 0)
                  Text(
                    '${plan.uncertainCount} uncertain',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final pick in plan.picks)
                  ListTile(
                    dense: true,
                    // The uncertainty badge of section 6. It lives HERE and not
                    // on the grid tile: see "Reading pitfall" at the top.
                    leading: pick.uncertain ? const Icon(Icons.help_outline, size: 20) : null,
                    title: Text(pick.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(pick.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      key: ValueKey('remove-${pick.gameId}'),
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Remove from batch',
                      onPressed: () => onRemove(pick.gameId),
                    ),
                  ),
                if (plan.failures.isNotEmpty) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      'Not going to the queue',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  for (final failure in plan.failures)
                    ListTile(
                      dense: true,
                      leading: Icon(Icons.cloud_off_rounded, size: 20, color: scheme.onSurfaceVariant),
                      title: Text(failure.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(failure.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  // With nothing chosen there is nothing to enqueue, but the
                  // sheet stays open to show the reasons of the failures.
                  onPressed: plan.picks.isEmpty ? null : () => onConfirm(plan),
                  child: const Text('Download'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/batch_confirm_sheet_test.dart
```

Expected: `+11`, zero failures.

If `2 games, 2.0 MB` fails because of the format, check `formatBytes` in `lib/utils/formatters.dart:6-13`: it uses one decimal place by default and the 1024 scale. **Adjust the test to `formatBytes`, not `formatBytes` to the test**: it is already used in other screens and changing it is an out-of-scope regression.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/batch_confirm_sheet_test.dart
git commit -m "test(lote): folha de confirmacao com total, motivos e o que nao vai"

# production agent
git add lib/widgets/game_grid/batch_confirm_sheet.dart
git commit -m "feat(lote): folha de confirmacao com total, motivos e o que nao vai"
```

---

### Task 6: the batch passes through the sheet before becoming a queue

**Files:**
- Create: `lib/services/source_pick_service.dart`
- Modify: `lib/screens/home_screen.dart`
- Test: `test/source_pick_service_test.dart`

Task 3 moved the button and Task 5 drew the sheet, but the two still do not talk: pressing "Download" on the bar enqueues everything directly, without confirmation. This Task closes Group 1.

The SOURCE MODE `BatchPlan` is born here, and it is the trivial case: each selected item **already is** a file, every file in the listing exists, so no pick is uncertain and no failure is possible. Even so it passes through the same function and the same sheet as PACK MODE, because that is what makes Task 20 small.

**Why a function and not an inline `map` in `HomeScreen`.** Because `HomeScreen` is not tested (see the test note of Task 3) and a top-level function in `lib/services/` is tested. The real rule arrives in Task 14, in the same file, and will want the same place.

- [ ] **Step 1: Write the tests that fail**

Create `test/source_pick_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';

Game _game(String filename, int size) => Game(
      title: filename.replaceAll('.zip', ''),
      url: 'https://example.org/snes/$filename',
      size: size,
      consoleId: 'snes',
    );

void main() {
  test('each selected game becomes one pick, in the same order', () {
    final plan = planFromGames([
      _game('Crystal Vanguard (USA).zip', 4 * 1024 * 1024),
      _game('Super Vectron (USA).zip', 3 * 1024 * 1024),
    ]);

    expect(plan.picks.map((p) => p.filename),
        ['Crystal Vanguard (USA).zip', 'Super Vectron (USA).zip']);
    expect(plan.totalBytes, 7 * 1024 * 1024);
  });

  test('the key and the whole Game travel together, because that is what goes to the queue', () {
    final game = _game('Crystal Vanguard (USA).zip', 1024);
    final pick = planFromGames([game]).picks.single;

    expect(pick.gameId, game.gameId);
    expect(pick.game, same(game));
    expect(pick.size, 1024);
  });

  test('in SOURCE MODE nothing is uncertain and nothing is left out', () {
    // The sheet exists to show uncertainty and failure. In SOURCE MODE it has
    // neither of the two to show, and that is correct, not a bug: the file the
    // user marked is the file they will receive.
    final plan = planFromGames([_game('a.zip', 1), _game('b.zip', 2)]);

    expect(plan.uncertainCount, 0);
    expect(plan.failures, isEmpty);
    expect(plan.picks.every((p) => p.reason.isNotEmpty), isTrue);
  });

  test('with no game the plan is truly empty', () {
    expect(planFromGames(const []).isEmpty, isTrue);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/source_pick_service_test.dart
```

Expected: `Target of URI doesn't exist: 'package:roms_downloader/services/source_pick_service.dart'`.

- [ ] **Step 3: Implement the function**

Create `lib/services/source_pick_service.dart`:

```dart
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';

/// The SOURCE MODE batch plan.
///
/// There is no choice to make here: each selected `Game` already is a file, and
/// every file in the listing exists. That is why no pick is uncertain and the
/// failures list is always empty.
///
/// The real rule of section 6 of the UI spec, with region, revision, confidence
/// and addon priority, lives in `planFromEntries` (Task 14) and only has a
/// subject in PACK MODE, where there is more than one version of the same game.
BatchPlan planFromGames(List<Game> games) {
  return BatchPlan(
    picks: [
      for (final game in games)
        SourcePick(
          gameId: game.gameId,
          title: game.displayTitle,
          filename: game.filename,
          size: game.size,
          sourceId: kBuiltinAddonId,
          reason: 'you picked this file',
          game: game,
        ),
    ],
  );
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/source_pick_service_test.dart
```

Expected: `+4`, zero failures.

- [ ] **Step 5: Wire the sheet into the `HomeScreen`**

In `lib/screens/home_screen.dart`, add the missing imports:

```dart
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';
```

Inside `_HomeScreenState`, before `build`, write the method:

```dart
  /// Opens the sheet of section 6, and only enqueues what comes back from it.
  Future<void> _confirmBatch() async {
    final catalogState = ref.read(catalogProvider);
    final games =
        catalogState.games.where((g) => catalogState.selectedGames.contains(g.gameId)).toList();
    if (games.isEmpty) return;

    // The current plan lives here, and not inside the sheet, because the sheet
    // is a pure widget (Task 5): it announces that a row left and the one that
    // keeps the result is this method.
    var plan = planFromGames(games);
    final confirmed = await showModalBottomSheet<BatchPlan>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (_, setSheetState) => BatchConfirmSheet(
          plan: plan,
          onConfirm: (p) => Navigator.of(sheetContext).pop(p),
          onRemove: (gameId) => setSheetState(() => plan = plan.withoutPick(gameId)),
        ),
      ),
    );
    if (confirmed == null || !mounted) return;

    await TaskQueueService.startDownloads(
      ref,
      context,
      confirmed.picks.map((pick) => pick.game).toList(),
      ref.read(appStateProvider).selectedConsole?.id,
    );
    if (!mounted) return;
    ref.read(catalogProvider.notifier).clearSelection();
  }
```

And replace the `onDownload` of the `SelectionBar`, which Task 3 left with the old header body, with a single line:

```dart
          SelectionBar(
            count: ref.watch(catalogProvider.select((s) => s.selectedGames.length)),
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: _confirmBatch,
          ),
```

Three things in this method are not style, they are requirements:

1. **`if (!mounted) return;` after every `await`.** Without it `flutter analyze` gains two new `use_build_context_synchronously`, and the acceptance criterion of this slice is 22 findings and none new. In a `State` the analyzer understands `mounted`; do not swap it for `context.mounted` without running the analyzer.
2. **The selection is cleared after enqueueing.** This is different from today's app, which left the 40 games marked after telling them to download. Today that passed because there was no way to unmark everything at once; from Task 1 on there is, and leaving the purple bar lit over an already-sent queue is an invitation to enqueue twice.
3. **`Navigator.pop` lives in the `onConfirm`, not inside the sheet.** The sheet does not know navigation (Task 5), and that is what allows testing it without a `Navigator`.

- [ ] **Step 6: Prove nothing broke**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Expected: 22 findings and zero errors; `+206 -1` in the suite. The math: 178 from the baseline, plus 2 from Task 1, 5 from Task 2, 6 from Task 4, 11 from Task 5 and 4 from this one.

Check by hand, because no test covers it: run the app, mark three games, press "Download", remove one from the sheet, confirm, and see that two enter the queue and the purple bar goes out.

- [ ] **Step 7: Commit**

```bash
# test agent
git add test/source_pick_service_test.dart
git commit -m "test(lote): plano de lote do MODO FONTE, um pick por arquivo selecionado"

# production agent
git add lib/services/source_pick_service.dart lib/screens/home_screen.dart
git commit -m "feat(lote): plano de lote do MODO FONTE, um pick por arquivo selecionado"
```

The production commit takes both files together on purpose: the function alone has no caller and the screen alone does not compile.

---

# Group 2: the inverted index and the grid data

Here PACK MODE begins. This group is pure Dart from start to finish, except the last file, which is a providers one. No widget is touched. If an agent of this group opens a file in `lib/widgets/`, it left the scope.

The input is the whole of slice 2: `PackMatcher` matches a file name with a `PackGame`, and `MetadataPack` brings the games. What is missing is the opposite direction, which is the one the grid needs: **given a game, which files exist for it.**

---

### Task 7: `PackGridEntry`, an entry of the pack grid

**Files:**
- Create: `lib/models/grid_entry_model.dart`
- Test: `test/grid_entry_model_test.dart`

The type that the PACK MODE grid draws. A `PackGame` plus the sources that the matcher matched to it. Pure Dart, no Flutter.

Read the "Third locked decision" at the top before starting: this type exists precisely so as **not** to synthesize a `Game`.

- [ ] **Step 1: Write the tests that fail**

Create `test/grid_entry_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: const []);

MatchedSource _src(String filename, {MatchConfidence confidence = MatchConfidence.likely}) =>
    MatchedSource(filename: filename, sourceId: 'listing', confidence: confidence, size: 1024);

void main() {
  test('with no source the entry is not available', () {
    final entry = PackGridEntry(game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'), sources: const []);

    expect(entry.hasSource, isFalse);
    expect(entry.sourceCount, 0);
  });

  test('with at least one source the entry is available', () {
    final entry = PackGridEntry(
      game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'),
      sources: [_src('Crystal Vanguard (USA).zip')],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 1);
  });

  test('the selection key has the pack: prefix, and does not collide with gameId', () {
    // See "Fourth locked decision" at the top of the plan. `Game.gameId` is
    // 'snes/file.zip' and `PackGame.id` is 'snes/crystal-vanguard': both start
    // with a letter and have a slash. The prefix is what separates them.
    final entry = PackGridEntry(game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'), sources: const []);

    expect(entry.selectionKey, 'pack:snes/crystal-vanguard');
  });

  test('the entry does not invent its own confidence from the sources', () {
    // See "Reading pitfall" at the top. A game with one confirmed source and
    // one guessed one is still a single game, and its tile is the same as that
    // of any other game with a source.
    final entry = PackGridEntry(
      game: _pg('snes/crystal-vanguard', 'Crystal Vanguard'),
      sources: [
        _src('a.zip', confidence: MatchConfidence.confirmed),
        _src('b.zip', confidence: MatchConfidence.guess),
      ],
    );

    expect(entry.hasSource, isTrue);
    expect(entry.sourceCount, 2);
    // If you just wrote `entry.confidence`, delete it: it does not exist and
    // will not exist.
  });
}
```

- [ ] **Step 2: Check the real name of `MatchedSource`**

This is the step that avoids rewriting the whole Task later. `MatchedSource` **does not exist yet**: slice 2 delivered `GameMatch`, which is the matcher's verdict about **one file name** and points to the `PackGame`. The grid needs the inverse direction and with the file size along, which the matcher does not know.

Open `lib/models/game_match_model.dart` and check, with your own eyes, the names of `MatchTier`, `MatchConfidence` and of the `GameMatch` fields. If any name in this plan diverges from the file, **the file wins**, and you fix the plan on the way through.

- [ ] **Step 3: Implement**

Create `lib/models/grid_entry_model.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';

/// A file from a source that the matcher matched to a `PackGame`.
///
/// It is the slice 2 `GameMatch` turned inside out: there the key is the file
/// name and the value is the game; here the key is the game and this is one of
/// the values. The size comes from the listing, not from the matcher.
@immutable
class MatchedSource {
  final String filename;

  /// Which source it came from. In this slice it is always the console listing;
  /// in slice 4 it becomes the addon id, and that is why the field already exists.
  final String sourceId;
  final MatchConfidence confidence;

  /// Bytes, or zero when the listing declares no size.
  final int size;

  /// The download URL. Stays null when the source does not provide it upfront.
  final String? url;

  const MatchedSource({
    required this.filename,
    required this.sourceId,
    required this.confidence,
    required this.size,
    this.url,
  });
}

/// An entry of the grid in PACK MODE: a canonical game and its sources.
///
/// The grid draws this, and not `Game`. See "Third locked decision" in the
/// slice 3 plan.
@immutable
class PackGridEntry {
  final PackGame game;
  final List<MatchedSource> sources;

  const PackGridEntry({required this.game, this.sources = const []});

  /// The only axis the tile paints. See "Reading pitfall": the tile shows
  /// **availability**, never confidence.
  bool get hasSource => sources.isNotEmpty;

  int get sourceCount => sources.length;

  /// The selection key in PACK MODE. The `pack:` prefix is mandatory because
  /// `Game.gameId` and `PackGame.id` are not provably disjoint, and `:` cannot
  /// appear in an id generated by `_nameToId` (`catalog_service.dart:61-63`).
  String get selectionKey => 'pack:${game.id}';
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/grid_entry_model_test.dart
```

Expected: `+4`, zero failures.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/grid_entry_model_test.dart
git commit -m "test(grade): entrada de grade de pack, disponibilidade e chave de selecao"

# production agent
git add lib/models/grid_entry_model.dart
git commit -m "feat(grade): entrada de grade de pack, disponibilidade e chave de selecao"
```

---

### Task 8: `SourceIndex`, the matcher turned inside out

**Files:**
- Create: `lib/services/source_index.dart`
- Test: `test/source_index_test.dart`

The slice 2 `PackMatcher` answers "which game is this file". The grid needs the opposite: "which files exist for this game". This is the inverted index, built once per console and consulted per tile.

**Cost, because this decides the shape.** It is 2415 games and a few thousand files in the average console. Building all at once is one pass; asking per tile during the scroll would be one pass per tile. That is why `build` is static and the result is kept in a provider (Task 10), never recomputed in a widget's `build`.

- [ ] **Step 1: Write the tests that fail**

Create `test/source_index_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';

PackGame _pg(String id, String dumpName) => PackGame(
      id: id,
      title: dumpName,
      dumps: [PackDump(name: dumpName)],
    );

PackMatcher _matcher() => PackMatcher(MetadataPack(
      pack: 'snes',
      system: 'Super Nintendo',
      built: '2026-01-01',
      games: [
        _pg('snes/crystal-vanguard', 'Crystal Vanguard (USA)'),
        _pg('snes/super-vectron', 'Super Vectron (USA)'),
        _pg('snes/emberfall', 'Emberfall (USA)'),
      ],
    ));

SourceFile _f(String filename, {int size = 1024}) =>
    (filename: filename, sourceId: 'listing', size: size, url: null);

void main() {
  test('each matched file enters the list of its game', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Crystal Vanguard (USA).zip'),
      _f('Super Vectron (USA).zip'),
    ]);

    expect(index.sourcesFor('snes/crystal-vanguard').single.filename, 'Crystal Vanguard (USA).zip');
    expect(index.sourcesFor('snes/super-vectron').single.filename, 'Super Vectron (USA).zip');
    expect(index.hasSource('snes/emberfall'), isFalse);
  });

  test('two versions of the same game stay together, in listing order', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Crystal Vanguard (USA).zip'),
      _f('Crystal Vanguard (Europe).zip'),
    ]);

    expect(
      index.sourcesFor('snes/crystal-vanguard').map((s) => s.filename),
      ['Crystal Vanguard (USA).zip', 'Crystal Vanguard (Europe).zip'],
    );
  });

  test('each source confidence comes from that file tier', () {
    final index = SourceIndex.build(_matcher(), [
      _f('Crystal Vanguard (USA).zip'),   // exact name
      _f('Crystal Vanguar (USA).zip'),    // typo, falls into fuzzy
    ]);

    final sources = index.sourcesFor('snes/crystal-vanguard');
    expect(sources.map((s) => s.confidence),
        [MatchConfidence.likely, MatchConfidence.guess]);
  });

  test('the size and the origin source survive the crossing', () {
    final index = SourceIndex.build(_matcher(), [_f('Crystal Vanguard (USA).zip', size: 4096)]);

    final source = index.sourcesFor('snes/crystal-vanguard').single;
    expect(source.size, 4096);
    expect(source.sourceId, 'listing');
  });

  test('a file that matches no game becomes an unmatched one', () {
    final index = SourceIndex.build(_matcher(), [_f('Game That Does Not Exist (USA).zip')]);

    expect(index.unmatched, ['Game That Does Not Exist (USA).zip']);
    expect(index.matchedGameCount, 0);
  });

  test('what is not a ROM is ignored, and does not count as unmatched', () {
    // The archive.org listing comes full of index .txt, .png and .xml. Calling
    // that "unmatched" would lie in the strip of Task 12.
    final index = SourceIndex.build(_matcher(), [
      _f('readme.txt'),
      _f('Crystal Vanguard (USA).zip'),
    ]);

    expect(index.unmatched, isEmpty);
    expect(index.matchedGameCount, 1);
  });

  test('a game with no source returns an empty list, never null', () {
    final index = SourceIndex.build(_matcher(), const []);

    expect(index.sourcesFor('snes/emberfall'), isEmpty);
    expect(index.sourcesFor('id/that/does/not/exist'), isEmpty);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/source_index_test.dart
```

Expected: `Target of URI doesn't exist: 'package:roms_downloader/services/source_index.dart'`.

- [ ] **Step 3: Implement**

Create `lib/services/source_index.dart`:

```dart
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// A raw file from a source, before the matcher has an opinion about it.
///
/// It is a record and not a class because it has no behavior at all and because
/// the one that produces it changes per slice: in this one it is the console
/// listing, in slice 4 it is the addon. `pack_matcher.dart:25` already uses a
/// record for the same reason.
typedef SourceFile = ({String filename, String sourceId, int size, String? url});

/// Inverted index: given a `PackGame` id, which files exist.
///
/// The `PackMatcher` answers "which game is this file". This answers "which
/// files are this game", which is what the grid asks.
///
/// Build once per console, in `build`, and keep it. Do not build inside a
/// widget's `build`: it is thousands of `match` calls at a time.
class SourceIndex {
  final Map<String, List<MatchedSource>> _byGameId;

  /// Names with a ROM extension that the matcher assigned to no game. What is
  /// not a ROM never enters here: it would be listing index noise.
  final List<String> unmatched;

  const SourceIndex._(this._byGameId, this.unmatched);

  static SourceIndex build(PackMatcher matcher, List<SourceFile> files) {
    final byGameId = <String, List<MatchedSource>>{};
    final unmatched = <String>[];

    for (final file in files) {
      if (!hasRomExtension(file.filename)) continue;
      final match = matcher.match(file.filename);
      if (match == null) {
        unmatched.add(file.filename);
        continue;
      }
      byGameId.putIfAbsent(match.game.id, () => <MatchedSource>[]).add(MatchedSource(
            filename: file.filename,
            sourceId: file.sourceId,
            confidence: match.confidence,
            size: file.size,
            url: file.url,
          ));
    }

    return SourceIndex._(byGameId, unmatched);
  }

  /// That game's sources, **in listing order**. Ordering by preference is the
  /// choice rule (Task 14), not the index.
  List<MatchedSource> sourcesFor(String gameId) => _byGameId[gameId] ?? const [];

  bool hasSource(String gameId) => _byGameId.containsKey(gameId);

  /// How many games in the pack have at least one source. It is what decides
  /// the empty state strip of Task 12.
  int get matchedGameCount => _byGameId.length;
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/source_index_test.dart
```

Expected: `+7`, zero failures.

If the fuzzy case fails saying that the confidence came `likely` instead of `guess`, do not touch `SourceIndex`: read `pack_matcher.dart:12`, where `fuzzyCutoff = 90.0` lives, and confirm that `Crystal Vanguar` still falls above the cutoff. The test is there precisely to warn if the cutoff changes.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/source_index_test.dart
git commit -m "test(grade): indice invertido de jogo para fontes casadas"

# production agent
git add lib/services/source_index.dart
git commit -m "feat(grade): indice invertido de jogo para fontes casadas"
```

---

### Task 9: `filterPackEntries`, the search of the pack grid

**Files:**
- Create: `lib/services/pack_grid_filter.dart`
- Test: `test/pack_grid_filter_test.dart`

Read the "Fifth locked decision" at the top before starting. One-line summary: **text search yes, region and revision chips no.** If you catch yourself writing `filter.regions` in this file, you stopped at the wrong place.

Two functions in one: it filters by the text that came from the header search box and sorts. The sorting is here, and not in the provider, because sorting is a presentation decision and because this way it is tested without Riverpod.

- [ ] **Step 1: Write the tests that fail**

Create `test/pack_grid_filter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';

PackGridEntry _e(String title, {bool withSource = true, String? id}) => PackGridEntry(
      game: PackGame(id: id ?? 'snes/${title.toLowerCase()}', title: title, dumps: const []),
      sources: withSource
          ? [const MatchedSource(filename: 'a.zip', sourceId: 'listing', confidence: MatchConfidence.likely, size: 1)]
          : const [],
    );

void main() {
  test('an empty query returns everything', () {
    final out = filterPackEntries([_e('Super Vectron'), _e('Crystal Vanguard')], '');

    expect(out.length, 2);
  });

  test('the output comes sorted by title, not in pack order', () {
    final out = filterPackEntries([_e('Super Vectron'), _e('Crystal Vanguard'), _e('Emberfall')], '');

    expect(out.map((e) => e.game.title), ['Crystal Vanguard', 'Emberfall', 'Super Vectron']);
  });

  test('the search ignores case and accent', () {
    // `norm` already folds accents and lowercases since slice 2. Do not reimplement.
    final out = filterPackEntries([_e('Prismón Red'), _e('Super Vectron')], 'prismon');

    expect(out.single.game.title, 'Prismón Red');
  });

  test('the search matches a chunk in the middle of the title', () {
    final out = filterPackEntries([_e('The Legend of Kaelis'), _e('Super Vectron')], 'kaelis');

    expect(out.single.game.title, 'The Legend of Kaelis');
  });

  test('a search with no result returns an empty list', () {
    final out = filterPackEntries([_e('Super Vectron')], 'cryptmanor');

    expect(out, isEmpty);
  });

  test('a game with no source keeps appearing, because the grid shows everything', () {
    // Locked decision of the whole project: the grid shows all games in the
    // pack and marks the exception. Filtering by availability here is the error
    // this line exists to prevent.
    final out = filterPackEntries([_e('Super Vectron', withSource: false)], '');

    expect(out.single.hasSource, isFalse);
  });

  test('equal titles always come out in the same order, broken by id', () {
    // Every other sorting test uses distinct titles, so `byTitle != 0` is always
    // true and the tie-break branch never runs. Without this case, deleting the
    // tie-break or inverting it leaves no test red.
    //
    // The two calls are the point: the input goes in both possible orders and
    // the output has to be the same. A single call would pass by chance, because
    // in a two-element list Dart's `sort` falls into insertion, which preserves
    // the input order when the comparator returns 0.
    final usa = _e('Fabled Frontier', id: 'snes/ff-usa');
    final eur = _e('Fabled Frontier', id: 'snes/ff-eur');

    expect(filterPackEntries([usa, eur], '').map((e) => e.game.id), ['snes/ff-eur', 'snes/ff-usa']);
    expect(filterPackEntries([eur, usa], '').map((e) => e.game.id), ['snes/ff-eur', 'snes/ff-usa']);
  });

  test('whitespace around the query does not count', () {
    final out = filterPackEntries([_e('Super Vectron')], '  vectron  ');

    expect(out.length, 1);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/pack_grid_filter_test.dart
```

Expected: `Target of URI doesn't exist: 'package:roms_downloader/services/pack_grid_filter.dart'`.

- [ ] **Step 3: Implement**

Create `lib/services/pack_grid_filter.dart`:

```dart
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Search and sorting of the grid in PACK MODE.
///
/// Pure and synchronous Dart on purpose. SOURCE MODE uses `FilteringService` in
/// an isolate because there the filter is expensive (region regex, revision,
/// latest-revision grouping). Here it is a `contains` over a few thousand
/// already-normalized titles; sending that to an isolate would cost more in
/// serialization than the filter itself.
///
/// It does **not** filter by region, revision or dump quality. See "Fifth
/// locked decision" in the slice 3 plan: those are properties of a version, and
/// in PACK MODE the grid has no version.
///
/// It does **not** filter by availability. The grid shows the whole pack and
/// marks the exception; hiding what has no source is the opposite of what the
/// spec asks.
List<PackGridEntry> filterPackEntries(List<PackGridEntry> entries, String query) {
  final needle = norm(query);
  final out = needle.isEmpty
      ? [...entries]
      : entries.where((entry) => norm(entry.game.title).contains(needle)).toList();

  out.sort((a, b) {
    final byTitle = norm(a.game.title).compareTo(norm(b.game.title));
    // Stable tie-break by id: two games with the same title exist (a reissue, a
    // region homonym), and without this the grid order would change from one
    // rebuild to the next.
    return byTitle != 0 ? byTitle : a.game.id.compareTo(b.game.id);
  });
  return out;
}
```

A note about `norm`, checked by running and not by reading: it trims the ROM extension (`pack_naming.dart:80`), but only when the text **ends** with the extension, dot included. `norm('md')` is `'md'` and `norm('bin')` is `'bin'`, so searching for those letters works normally. The only degenerate case is a search that is exactly an extension with the dot, like `.md`: `norm` returns an empty string and the grid shows everything. Nobody types that, and fixing it would require a second normalization function just for search. Do not fix it in this slice.

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/pack_grid_filter_test.dart
```

Expected: `+8`, zero failures.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/pack_grid_filter_test.dart
git commit -m "test(grade): busca e ordenacao da grade de pack, sem chip de versao"

# production agent
git add lib/services/pack_grid_filter.dart
git commit -m "feat(grade): busca e ordenacao da grade de pack, sem chip de versao"
```

---

### Task 10: the pack grid providers

**Files:**
- Create: `lib/providers/pack_grid_provider.dart`
- Test: `test/pack_grid_provider_test.dart`

Six small providers. Three are inputs, and exist so that the other three are tested without touching `AppStateNotifier` nor `CatalogNotifier`, which do IO in the constructor.

**The decision this file locks, and it is the most important of the slice:** while the pack has not arrived, and also if it never arrives, the mode is **SOURCE**. No new spinner, no blank screen. SOURCE MODE is today's app, and falling into it is by definition not regressing. A console with no pack, a user with no network and the first second of any session are the same case, and all of them see exactly the app they already saw.

- [ ] **Step 1: Write the tests that fail**

Create `test/pack_grid_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';

const _target = PackTarget('snes', 'Super Nintendo');

PackGame _pg(String id, String dumpName) =>
    PackGame(id: id, title: dumpName, dumps: [PackDump(name: dumpName)]);

MetadataPack _pack() => MetadataPack(
      pack: 'snes',
      system: 'Super Nintendo',
      built: '2026-01-01',
      games: [
        _pg('snes/crystal-vanguard', 'Crystal Vanguard (USA)'),
        _pg('snes/super-vectron', 'Super Vectron (USA)'),
      ],
    );

Game _game(String filename) => Game(
      title: filename,
      url: 'https://example.org/snes/$filename',
      size: 2048,
      consoleId: 'snes',
    );

ProviderContainer _container({
  PackTarget? target = _target,
  Future<MetadataPack?>? pack,
  List<Game> games = const [],
  String search = '',
}) {
  final container = ProviderContainer(overrides: [
    packTargetProvider.overrideWithValue(target),
    if (target != null)
      metadataPackProvider(target).overrideWith((ref) => pack ?? Future.value(_pack())),
    catalogGamesProvider.overrideWithValue(games),
    gridSearchQueryProvider.overrideWithValue(search),
  ]);
  addTearDown(container.dispose);
  return container;
}

/// Waits for the pack and the matcher to resolve. Without this the synchronous
/// providers are still seeing `AsyncLoading`, a legitimate state tested apart.
Future<void> _ready(ProviderContainer container) async {
  await container.read(metadataPackProvider(_target).future);
  await container.read(packMatcherProvider(_target).future);
}

void main() {
  test('with no console selected the mode is SOURCE and the grid is empty', () {
    final container = _container(target: null);

    expect(container.read(gridModeProvider), GridMode.source);
    expect(container.read(packGridEntriesProvider), isEmpty);
    expect(container.read(sourceIndexProvider), isNull);
  });

  test('while the pack loads the mode is SOURCE', () {
    // No `await`. This is the state of the first frame of every session.
    final container = _container(pack: Future.delayed(const Duration(seconds: 1), _pack));

    expect(container.read(gridModeProvider), GridMode.source);
  });

  test('a console with no pack stays in SOURCE MODE', () async {
    final container = _container(pack: Future.value(null));
    await container.read(metadataPackProvider(_target).future);

    expect(container.read(gridModeProvider), GridMode.source);
    expect(container.read(packGridEntriesProvider), isEmpty);
  });

  test('an error fetching the pack falls into SOURCE MODE, not an error screen', () async {
    final container = _container(pack: Future.error(Exception('no network')));
    await expectLater(container.read(metadataPackProvider(_target).future), throwsException);

    expect(container.read(gridModeProvider), GridMode.source);
  });

  test('with a pack the mode is PACK and the grid brings all the pack games', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    expect(container.read(gridModeProvider), GridMode.pack);
    final entries = container.read(packGridEntriesProvider);
    expect(entries.map((e) => e.game.id), ['snes/crystal-vanguard', 'snes/super-vectron']);
    // What has no source stays in the grid, marked, and does not disappear from it.
    expect(entries.map((e) => e.hasSource), [true, false]);
  });

  test('the matched source carries the size and the builtin source id', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    final source = container.read(packGridEntriesProvider).first.sources.single;
    expect(source.filename, 'Crystal Vanguard (USA).zip');
    expect(source.size, 2048);
    expect(source.sourceId, kBuiltinAddonId);
    expect(source.url, 'https://example.org/snes/Crystal Vanguard (USA).zip');
  });

  test('the header search filters the pack grid', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')], search: 'vectron');
    await _ready(container);

    expect(container.read(packGridEntriesProvider).single.game.id, 'snes/super-vectron');
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/pack_grid_provider_test.dart
```

Expected: `Target of URI doesn't exist: 'package:roms_downloader/providers/pack_grid_provider.dart'`.

- [ ] **Step 3: Implement**

Create `lib/providers/pack_grid_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/metadata_pack_provider.dart';
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/services/source_index.dart';

/// The two grid modes of section 7 of the architecture spec.
enum GridMode {
  /// Today's grid: one tile per listing file.
  source,

  /// The new grid: one tile per pack game.
  pack,
}

/// The selected console, in the shape the pack provider understands.
///
/// This is the test seam: override **this** provider, never `appStateProvider`,
/// which does disk and network IO in the constructor.
///
/// Note about key collision, which is the "Fourth locked decision" of the slice
/// 3 plan: the selection key in PACK MODE is `'pack:${packGame.id}'`. The `:`
/// cannot come out of `CatalogService._nameToId` (`catalog_service.dart:61-63`),
/// so it does not collide with `Game.gameId`. The only collision path is a
/// `consoles.json` in the legacy map format (`catalog_service.dart:95-96`),
/// which uses the map key verbatim: a hand-written console with id `pack:snes`
/// would collide. It is a known and accepted edge, with no defense code.
final packTargetProvider = Provider<PackTarget?>((ref) {
  final console = ref.watch(appStateProvider.select((s) => s.selectedConsole));
  if (console == null) return null;
  return PackTarget(console.id, console.name);
});

/// The console listing. Test seam for the same reason as above.
final catalogGamesProvider =
    Provider<List<Game>>((ref) => ref.watch(catalogProvider.select((s) => s.games)));

/// The text of the header search box. The same box in both modes: what changes
/// is only who consumes it. See "Fifth locked decision" in the plan.
final gridSearchQueryProvider =
    Provider<String>((ref) => ref.watch(catalogProvider.select((s) => s.filterText)));

/// Which grid to draw.
///
/// **Everything that is not "the pack arrived" is SOURCE MODE**: no console,
/// pack loading, console with no pack, network error. SOURCE MODE is today's
/// app, so degrading to it is never a regression, and that is the only reason
/// this provider is synchronous instead of returning `AsyncValue`.
final gridModeProvider = Provider<GridMode>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return GridMode.source;
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  return pack == null ? GridMode.source : GridMode.pack;
});

/// The inverted index of the current console. Null while there is no matcher.
///
/// Rebuilds when the listing changes, which happens once per catalog load. It
/// does **not** rebuild on every keystroke: the search is applied later, in the
/// entries provider.
final sourceIndexProvider = Provider<SourceIndex?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  final matcher = ref.watch(packMatcherProvider(target)).valueOrNull;
  if (matcher == null) return null;
  return SourceIndex.build(matcher, <SourceFile>[
    for (final game in ref.watch(catalogGamesProvider))
      (filename: game.filename, sourceId: kBuiltinAddonId, size: game.size, url: game.url),
  ]);
});

/// What the PACK MODE grid draws, already filtered and sorted.
///
/// In SOURCE MODE nobody reads this provider, and it returns an empty list at
/// no cost, because `metadataPackProvider` already resolved to null.
final packGridEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return const [];
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  if (pack == null) return const [];

  final index = ref.watch(sourceIndexProvider);
  return filterPackEntries([
    for (final game in pack.games)
      PackGridEntry(game: game, sources: index?.sourcesFor(game.id) ?? const []),
  ], ref.watch(gridSearchQueryProvider));
});
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/pack_grid_provider_test.dart
```

Expected: `+7`, zero failures.

Two likely stumbles, and both have a known fix:

- If `metadataPackProvider(target).overrideWith(...)` does not compile, check the Riverpod version in `pubspec.yaml`. In 2.6 overriding a family member is `provider(arg).overrideWith((ref) => value)`. Do not swap it for `overrideWithValue` on a `FutureProvider`: that form was removed.
- If the network error case makes the whole test fail instead of pass, it is the `ProviderContainer` propagating the error on disposal. The `expectLater(..., throwsException)` before the assertion exists to consume that error; keep it.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/pack_grid_provider_test.dart
git commit -m "test(grade): providers de modo, indice e entradas da grade de pack"

# production agent
git add lib/providers/pack_grid_provider.dart
git commit -m "feat(grade): providers de modo, indice e entradas da grade de pack"
```

---

# Group 3: the tile, the grid and the routing

Now the UI. The two widgets of this group are pure: they receive primitives and callbacks, do not know Riverpod, and therefore test themselves alone in a `MaterialApp`, without a `ProviderScope`. The model is `test/menu_grid_test.dart`, 31 lines.

Reminder for the whole group: **`game_grid_item.dart` and `game_grid.dart` are not touched.** What section 3.1 of the UI spec describes as "leaves the tile" is already born outside the new tile.

---

### Task 11: `PackGridItem`, the tile of a game

**Files:**
- Create: `lib/widgets/game_grid/pack_grid_item.dart`
- Test: `test/pack_grid_item_test.dart`

The tile of section 3.1. Cover, overlaid title, the "no source" mark, the selection checkbox, the state border.

**What this tile does not do in this slice, and why.** Section 3.1 lists the progress bar among what the tile keeps. It does **not** come in here. Progress is a property of a file, and this tile is a game with N files; finding out "some source of this game is downloading" requires reading the state of N sources per tile, on every scroll frame, which is exactly the cost that Task 8 exists to avoid. Meanwhile, the footer queue keeps showing every download in progress, and it does not change in this slice. When someone wants the bar back, the recipe is the same as Task 13: a `Set<String>` of games with an active download, computed once, never per tile. **Do not improvise that now.**

**Desktop hover also does not come in, and it is a noted divergence.** Section 4 of the UI spec says that on desktop the checkbox appears on tile hover even with an empty selection. Doing this requires turning this widget into a `StatefulWidget` just to keep a `MouseRegion` `bool`, and the hover test in `flutter_test` requires setting up a mouse pointer by hand. What is lost without it is **discovery**, not capability: the long press works with the mouse (press and hold), and as soon as a selection exists the checkbox appears on all tiles. It is noted as a deliberate divergence, along with the other three of the "File structure" table.

Read the "Reading pitfall" at the top of the plan before Step 1. The tile does not paint confidence. It paints availability.

- [ ] **Step 1: Write the tests that fail**

Create `test/pack_grid_item_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

// `coverUrl` is null in every test on purpose: with a URL, `CachedNetworkImage`
// would attempt the network inside the test. The cover is covered by hand.
Widget _host(
  Widget child, {
  double width = 200,
}) =>
    MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: width, child: child))));

void main() {
  testWidgets('shows the game title', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.text('Crystal Vanguard'), findsOneWidget);
  });

  testWidgets('with no source it gets the crossed-cloud mark', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('with a source it gets no mark at all', (tester) async {
    // The premise of section 3.1: the exception is marked, not the rule.
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });

  testWidgets('the tile is the same with a confirmed source and a guessed source', (tester) async {
    // There is no confidence parameter on this widget, and this test exists so
    // that the absence is intentional and visible. If someone adds `confidence:`
    // here, this test stops compiling and that is what is wanted.
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(find.byIcon(Icons.verified_outlined), findsNothing);
  });

  testWidgets('with no active selection there is no checkbox', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('with an active selection every tile shows a checkbox, checked or not', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: true,
      isSelected: false,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('the selected tile shows the checkbox checked', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: true,
      isSelected: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
  });

  testWidgets('short tap opens and long press selects', (tester) async {
    var opened = 0;
    var selected = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () => opened++,
      onLongPress: () => selected++,
      onToggleSelection: () {},
    )));

    await tester.tap(find.byType(PackGridItem));
    await tester.longPress(find.byType(PackGridItem));
    await tester.pump();

    expect(opened, 1);
    expect(selected, 1);
  });

  testWidgets('the checkbox toggles the selection without opening the detail', (tester) async {
    var opened = 0;
    var toggled = 0;
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      selectionActive: true,
      onTap: () => opened++,
      onLongPress: () {},
      onToggleSelection: () => toggled++,
    )));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(toggled, 1);
    expect(opened, 0);
  });

  testWidgets('the thick border appears when the game is already on disk', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      isOwned: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final border = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((border.decoration as BoxDecoration).border!.top.width, 3);
  });

  testWidgets('with no state at all the border is thin', (tester) async {
    await tester.pumpWidget(_host(PackGridItem(
      title: 'Crystal Vanguard',
      hasSource: true,
      onTap: () {},
      onLongPress: () {},
      onToggleSelection: () {},
    )));

    final border = tester.widget<Container>(find.byKey(const ValueKey('pack-tile-border')));
    expect((border.decoration as BoxDecoration).border!.top.width, 1);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/pack_grid_item_test.dart
```

Expected: `Target of URI doesn't exist: '.../pack_grid_item.dart'`.

- [ ] **Step 3: Implement**

Create `lib/widgets/game_grid/pack_grid_item.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The PACK MODE tile: it represents a **game**, not a file.
///
/// Pure widget on purpose. It does not know what a `PackGridEntry` is, reads no
/// provider and decides nothing: the one that assembles it is `PackGrid` (Task 12).
///
/// What it does **not** have, and the absence is the important part:
/// - no match confidence parameter. The tile shows availability, and a game
///   with one confirmed source and one guessed one is a single game. See
///   "Reading pitfall" in the slice 3 plan.
/// - no download button. The tile does not know which file to download, so it
///   cannot have a download button (UI spec, section 3.1).
/// - no region, revision or disc tag. Those describe a version.
class PackGridItem extends StatelessWidget {
  final String title;

  /// The pack cover URL. Null falls into the missing-cover placeholder.
  final String? coverUrl;

  /// Whether any addon has any file for this game. **It is the only axis that
  /// changes the tile's drawing.**
  final bool hasSource;

  /// Whether some version of this game is already on disk (Task 13). While the
  /// scan is not finished it comes `false`, because a wrong border is worse
  /// than a missing one.
  final bool isOwned;

  final bool isSelected;

  /// Whether a selection is in progress. With an empty selection the checkbox
  /// disappears from **all** tiles, to keep the cover clean (UI spec, section 4).
  final bool selectionActive;

  final double aspectRatio;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelection;

  const PackGridItem({
    super.key,
    required this.title,
    required this.hasSource,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelection,
    this.coverUrl,
    this.isOwned = false,
    this.isSelected = false,
    this.selectionActive = false,
    this.aspectRatio = 0.75,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color? borderColor = isSelected
        ? scheme.primary
        : isOwned
            ? scheme.secondaryContainer
            : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: const ValueKey('pack-tile-border'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor ?? Theme.of(context).dividerColor.withValues(alpha: 0.2),
            width: borderColor != null ? 3 : 1,
          ),
        ),
        child: Tooltip(
          message: title,
          // Without `manual` the `Tooltip` builds its own
          // `LongPressGestureRecognizer`, because `TooltipTriggerMode.longPress`
          // is the default on mobile and `flutter_test` runs as Android. That
          // recognizer is the innermost one, wins the arena and swallows the
          // long press of the outer `GestureDetector`, so the selection never
          // fires. `manual` removes only the tap trigger and keeps the desktop
          // hover, which is where the truncated-title hint serves any purpose. On
          // mobile the long press belongs to the selection, and that is a
          // locked decision.
          triggerMode: TooltipTriggerMode.manual,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _cover(context),
                ),
                if (selectionActive)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggleSelection(),
                        shape: const CircleBorder(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                // Two redundant signals for "no source": the desaturated cover
                // and this icon. Gray alone gets confused with "loading", and
                // many period covers are already nearly monochrome.
                if (!hasSource)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                      shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final url = coverUrl;
    final cover = url == null
        ? _placeholder(context)
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (context, _, __) => _placeholder(context),
            errorListener: (_) {},
          );
    if (hasSource) return cover;
    // Zero-saturation matrix: greys the art while preserving its brightness.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: cover,
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.3),
            scheme.secondaryContainer.withValues(alpha: 0.2),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.videogame_asset_rounded,
          size: 32,
          color: scheme.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/pack_grid_item_test.dart
```

Expected: `+11`, zero failures.

If `tester.tap(find.byType(PackGridItem))` complains of an ambiguous target or a pointer off screen, increase the `width` of `_host`: the tile respects `aspectRatio` and a too-narrow `SizedBox` can overflow the test screen height.

If the `short tap opens and long press selects` case fails with `Expected: <1> Actual: <0>` on the `selected` line, the `triggerMode: TooltipTriggerMode.manual` of Step 3 was not transcribed. Measured in both directions: with the default `Tooltip` it gives `opened=1 selected=0`, with `manual` it gives `opened=1 selected=1`. Do not fix it by swapping the test for `longPressAt`, nor by removing the `Tooltip`, nor by putting `behavior:` on the `GestureDetector`: the fix is the `triggerMode`.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/pack_grid_item_test.dart
git commit -m "test(grade): tile de jogo com marca de sem fonte e selecao por toque longo"

# production agent
git add lib/widgets/game_grid/pack_grid_item.dart
git commit -m "feat(grade): tile de jogo com marca de sem fonte e selecao por toque longo"
```

---

### Task 12: `PackGrid`, the PACK MODE grid

**Files:**
- Create: `lib/widgets/game_grid/pack_grid.dart`
- Test: `test/pack_grid_test.dart`

The grid that draws the Task 11 tiles from the Task 10 providers, plus the empty state strip of section 3.2.

**The grid does not navigate.** The short tap calls `onOpenGame`, and the one that pushes the route is `HomeScreen`, in Task 19. This is not purism: it is what allows testing the grid without a `Navigator` and without the detail screen, which only exists from Task 15 on.

**The empty state strip in this slice.** Section 3.2 speaks of "no addon installed", and addon is slice 4. In this slice the only source is the listing that already ships in `consoles.json`, so the equivalent condition, and a true one today, is **the index matched no game**. A SNES pack against a Nintendo Switch listing lands exactly there. In slice 4 the condition becomes "no addon covers this console" and the text is already ready.

**The "already downloaded" border does not come in here.** `PackGridItem.isOwned` stays at the default `false`. It arrives in Task 13, which is the only one that knows what is on disk.

- [ ] **Step 1: Write the tests that fail**

Create `test/pack_grid_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_index.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

import 'support/favorites_stub.dart';

PackGame _pg(String id, String title) => PackGame(id: id, title: title, dumps: [PackDump(name: '$title (USA)')]);

PackGridEntry _entry(String id, String title, {bool withSource = true}) => PackGridEntry(
      game: _pg(id, title),
      sources: withSource
          ? [MatchedSource(filename: '$title (USA).zip', sourceId: kBuiltinAddonId, confidence: MatchConfidence.likely, size: 1024)]
          : const [],
    );

/// A real index, because the empty state strip reads `matchedGameCount` and a
/// fake index would prove nothing.
SourceIndex _index({required bool matchesSomething}) {
  final matcher = PackMatcher(MetadataPack(
    pack: 'snes',
    system: 'Super Nintendo',
    built: '2026-01-01',
    games: [_pg('snes/crystal-vanguard', 'Crystal Vanguard')],
  ));
  return SourceIndex.build(matcher, [
    if (matchesSomething)
      (filename: 'Crystal Vanguard (USA).zip', sourceId: kBuiltinAddonId, size: 1024, url: null),
  ]);
}

Widget _host(
  List<PackGridEntry> entries, {
  SourceIndex? index,
  void Function(PackGridEntry)? onOpenGame,
}) {
  return ProviderScope(
    overrides: [
      withoutFavoritesDisk,
      packGridEntriesProvider.overrideWithValue(entries),
      sourceIndexProvider.overrideWithValue(index ?? _index(matchesSomething: true)),
    ],
    child: MaterialApp(
      home: Scaffold(body: PackGrid(onOpenGame: onOpenGame ?? (_) {})),
    ),
  );
}

void main() {
  testWidgets('draws one tile per entry', (tester) async {
    await tester.pumpWidget(_host([
      _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
      _entry('snes/super-vectron', 'Super Vectron'),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.text('Crystal Vanguard'), findsOneWidget);
  });

  testWidgets('a sourceless game stays in the grid, badged', (tester) async {
    await tester.pumpWidget(_host([
      _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
      _entry('snes/emberfall', 'Emberfall', withSource: false),
    ]));

    expect(find.byType(PackGridItem), findsNWidgets(2));
    expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
  });

  testWidgets('with an empty index the no-coverage strip appears', (tester) async {
    await tester.pumpWidget(_host(
      [_entry('snes/crystal-vanguard', 'Crystal Vanguard', withSource: false)],
      index: _index(matchesSomething: false),
    ));

    expect(find.text('No source covers this console'), findsOneWidget);
    // The strip is grid state, not tile state: the tiles are still there.
    expect(find.byType(PackGridItem), findsOneWidget);
  });

  testWidgets('with the index covering something there is no strip', (tester) async {
    await tester.pumpWidget(_host([_entry('snes/crystal-vanguard', 'Crystal Vanguard')]));

    expect(find.text('No source covers this console'), findsNothing);
  });

  testWidgets('a search with no result shows the search empty, not the coverage one', (tester) async {
    await tester.pumpWidget(_host(const []));

    expect(find.text('No game with that name'), findsOneWidget);
    expect(find.text('No source covers this console'), findsNothing);
  });

  testWidgets('the short tap returns the tapped entry', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_host(
      [_entry('snes/crystal-vanguard', 'Crystal Vanguard'), _entry('snes/super-vectron', 'Super Vectron')],
      onOpenGame: (entry) => opened.add(entry.game.id),
    ));

    await tester.tap(find.text('Super Vectron'));
    await tester.pump();

    expect(opened, ['snes/super-vectron']);
  });

  testWidgets('the long press selects, and then the checkbox appears on every tile', (tester) async {
    await tester.pumpWidget(_host([
      _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
      _entry('snes/super-vectron', 'Super Vectron'),
    ]));

    expect(find.byType(Checkbox), findsNothing);

    await tester.longPress(find.text('Crystal Vanguard'));
    await tester.pump();

    // Two checkboxes, one checked. It is the rule of section 4: the checkbox
    // visibility is global, its value is per tile.
    expect(find.byType(Checkbox), findsNWidgets(2));
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).where((c) => c.value == true).length,
      1,
    );
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/pack_grid_test.dart
```

Expected: `Target of URI doesn't exist: '.../pack_grid.dart'`.

- [ ] **Step 3: Implement**

Create `lib/widgets/game_grid/pack_grid.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid_item.dart';

/// The PACK MODE grid: one tile per pack game.
///
/// It does not replace `GameGrid`, it coexists with it. The one that chooses
/// which of the two to draw is `HomeScreen`, via `gridModeProvider` (Task 19).
class PackGrid extends ConsumerWidget {
  /// Called on a tile's short tap. The grid does not know `Navigator`: the one
  /// that pushes the detail route is `HomeScreen`.
  final void Function(PackGridEntry entry) onOpenGame;

  const PackGrid({super.key, required this.onOpenGame});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(packGridEntriesProvider);
    final index = ref.watch(sourceIndexProvider);
    final selected = ref.watch(catalogProvider.select((s) => s.selectedGames));
    final catalogNotifier = ref.read(catalogProvider.notifier);

    // Section 4 of the UI spec: the checkbox visibility is global and depends
    // only on there being a selection in progress. With an empty selection, a
    // clean cover on every tile.
    final selectionActive = selected.isNotEmpty;

    // Section 3.2. In this slice "no source" means "this console's listing
    // matched no game in the pack". In slice 4 the condition becomes "no
    // installed addon covers this console" and the text stays.
    final noCoverage = (index?.matchedGameCount ?? 0) == 0;

    return Column(
      children: [
        if (noCoverage) const _NoCoverageBanner(),
        Expanded(
          child: entries.isEmpty
              ? const _SearchEmpty()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 3),
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    // Fixed ratio, unlike `GameGrid`, which measures the first
                    // cover of the listing. The pack covers all come from the
                    // same origin and are already consistent, so measuring would
                    // be an image round trip per console switch, for nothing.
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      return PackGridItem(
                        key: ValueKey(entry.selectionKey),
                        title: entry.game.title,
                        coverUrl: entry.game.cover,
                        hasSource: entry.hasSource,
                        isSelected: selected.contains(entry.selectionKey),
                        selectionActive: selectionActive,
                        onTap: () => onOpenGame(entry),
                        onLongPress: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                        onToggleSelection: () => catalogNotifier.toggleGameSelection(entry.selectionKey),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _NoCoverageBanner extends StatelessWidget {
  const _NoCoverageBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No source covers this console',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Games show up for browsing, but there is nothing to download.',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No game with that name',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/pack_grid_test.dart
```

Expected: `+7`, zero failures.

Two likely stumbles:

- If the long press selects nothing, the culprit is the real `catalogProvider` inside the `ProviderScope`. It is real on purpose, to prove the whole wiring. Its constructor listens to `favoritesProvider`, which goes to disk, and that is why `withoutFavoritesDisk` is in the `overrides`: without it the test throws with `MissingPluginException` or with `Tried to use FavoritesNotifier after dispose`, both **after** the case passed. See the "Sixth locked decision". What you **must not** do is override the `catalogProvider`, because then the test stops proving the wiring and starts proving the stand-in.
- If `find.text('Super Vectron')` finds more than one widget, it is the tile's `Tooltip` duplicating the text in the tree. In that case use `find.byKey(const ValueKey('pack:snes/super-vectron'))`.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/pack_grid_test.dart
git commit -m "test(grade): grade de pack com faixa de sem cobertura e selecao por toque longo"

# production agent
git add lib/widgets/game_grid/pack_grid.dart
git commit -m "feat(grade): grade de pack com faixa de sem cobertura e selecao por toque longo"
```

---

### Task 13: `ownedGameIdsProvider`, who is already on disk

**Files:**
- Create: `lib/providers/owned_games_provider.dart`
- Create: `test/owned_games_provider_test.dart`
- Modify: `lib/widgets/game_grid/pack_grid.dart` (the grid starts filling `isOwned`)
- Modify: `test/pack_grid_test.dart` (two new tests at the end)

The "already downloaded" border of section 3.1. The tile already knows how to draw it since Task 11 and the grid already left it at the default `false` in Task 12. This Task is the only one that looks at the disk.

**One scan per console, never one per tile.** It is the same argument as Task 8. `identify` is a call that can compute a CRC, and calling it from inside an `itemBuilder` means calling it again on every scroll frame. So the scan runs once, returns a `Set<String>` of `PackGame.id`, and the tile does `contains`.

**While the scan is not finished, nobody gets a border.** `AsyncValue.valueOrNull ?? {}` solves this on its own, and it is what section 3.1 asks for: "shows nothing while scanning". A wrong border is worse than a missing one.

**Similarity does not paint a border.** `LocalIdentityService.identify` can return a tier 3 match, `MatchTier.fuzzyName`, which becomes `MatchConfidence.guess`. That serves to suggest, not to assert that the file is on disk. `guess` is discarded here. Exact name, canonical title and CRC come in.

**The border does not update itself when a download finishes.** This is deliberate in this slice: the hook would live inside `task_queue_service` / `download_provider`, which this slice does not touch (see the untouched table at the top, which Task 22 checks with `git diff --stat`). The recipe for when someone wants it, and it is two lines, is `ref.invalidate(ownedGameIdsProvider)` at the point where the download is marked as done. **Do not improvise that now**, because touching the download provider breaks the Task 22 criterion.

- [ ] **Step 1: Write the tests that fail**

Create `test/owned_games_provider_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/owned_games_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/local_identity_service.dart';
import 'package:roms_downloader/services/pack_matcher.dart';

const _target = PackTarget('snes', 'Super Nintendo');

final _pack = MetadataPack(
  pack: 'snes',
  system: 'Super Nintendo',
  built: '2026-01-01',
  games: [
    PackGame(
      id: 'snes/crystal-vanguard',
      title: 'Crystal Vanguard',
      dumps: [PackDump(name: 'Crystal Vanguard (USA)', crc: 'AABBCCDD')],
    ),
    PackGame(
      id: 'snes/super-vectron',
      title: 'Super Vectron',
      dumps: [PackDump(name: 'Super Vectron (Japan, USA)')],
    ),
  ],
);

/// Fixed CRC on purpose: no test here is about checksum, and reading the disk
/// to compute one would make the test slow and dependent on the file content.
/// `FFFFFFFF` is not in the pack, so the CRC axis never matches and each test
/// measures exactly the name axis it claims to measure.
LocalIdentityService _service() => LocalIdentityService(
      matcher: PackMatcher(_pack),
      crcOfFile: (_) async => 'FFFFFFFF',
    );

Future<Directory> _dir() async {
  final dir = await Directory.systemTemp.createTemp('owned_games_test');
  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  return dir;
}

Future<File> _file(Directory dir, String name) async {
  final file = File(p.join(dir.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsString('rom');
  return file;
}

ProviderContainer _container({
  required String? libraryDir,
  PackTarget? target = _target,
  LocalIdentityService? service,
  bool withService = true,
}) {
  final container = ProviderContainer(
    overrides: [
      packTargetProvider.overrideWithValue(target),
      libraryDirProvider.overrideWithValue(libraryDir),
      if (target != null)
        localIdentityServiceProvider(target).overrideWith(
          (ref) => withService ? (service ?? _service()) : null,
        ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('with no console selected the set is empty', () async {
    final container = _container(libraryDir: null, target: null);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('with no pack there is no identity, and the set is empty', () async {
    final dir = await _dir();
    await _file(dir, 'Crystal Vanguard (USA).sfc');
    final container = _container(libraryDir: dir.path, withService: false);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a folder that does not exist does not bring down the scan', () async {
    final container = _container(libraryDir: p.join(Directory.systemTemp.path, 'does_not_exist_at_all'));

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('the ROM that matches by name enters the set', () async {
    final dir = await _dir();
    await _file(dir, 'Crystal Vanguard (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), {'snes/crystal-vanguard'});
  });

  test('what is not a ROM is ignored', () async {
    final dir = await _dir();
    await _file(dir, 'Crystal Vanguard (USA).txt');
    await _file(dir, 'Super Vectron (Japan, USA).nfo');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM that matches nothing does not enter', () async {
    final dir = await _dir();
    await _file(dir, 'A Game That Does Not Exist (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });

  test('a ROM extracted inside a subfolder also counts', () async {
    final dir = await _dir();
    // It is the shape that `extractToFolder` leaves on disk, and it is the depth
    // that `_scanLibraryDirIsolate` already scans today.
    await _file(dir, p.join('Super Vectron (Japan, USA)', 'Super Vectron (Japan, USA).sfc'));
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), {'snes/super-vectron'});
  });

  test('a similarity-only match does not count as downloaded', () async {
    final dir = await _dir();
    // Tier 3: `ratio('crystal vanguar', 'crystal vanguard')` passes 90, so the
    // matcher returns a `fuzzyName`. Good enough to suggest, not good enough to
    // paint a border.
    await _file(dir, 'Crystal Vanguar (USA).sfc');
    final container = _container(libraryDir: dir.path);

    expect(await container.read(ownedGameIdsProvider.future), isEmpty);
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/owned_games_provider_test.dart
```

Expected: `Target of URI doesn't exist: 'package:roms_downloader/providers/owned_games_provider.dart'`.

- [ ] **Step 3: Implement the provider**

Create `lib/providers/owned_games_provider.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/utils/pack_naming.dart';

/// Where the selected console's library is on disk.
///
/// It exists separate from the provider below for one reason only: it is the
/// test injection point. `getDownloadDir` lives in the settings notifier, and
/// the `SettingsNotifier` constructor reads the disk; overriding this provider
/// is what allows scanning a temporary folder without booting real settings.
final libraryDirProvider = Provider<String?>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return null;
  // The `watch` is of the state and the call is on the notifier. It is that
  // pair that makes this provider recompute when the user changes the folder in
  // the settings.
  ref.watch(settingsProvider);
  final dir = ref.read(settingsProvider.notifier).getDownloadDir(target.consoleId);
  return dir.isEmpty ? null : dir;
});

/// The `PackGame.id`s that already have some version on disk.
///
/// One scan per console, never one per tile: `identify` can compute a CRC, and
/// calling it from inside an `itemBuilder` would be calling it again on every
/// scroll frame. The tile receives the ready set and does `contains`.
final ownedGameIdsProvider = FutureProvider<Set<String>>((ref) async {
  final target = ref.watch(packTargetProvider);
  final dir = ref.watch(libraryDirProvider);
  if (target == null || dir == null) return const <String>{};

  final identity = await ref.watch(localIdentityServiceProvider(target).future);
  if (identity == null) return const <String>{};

  final owned = <String>{};
  for (final file in await _libraryFiles(dir)) {
    if (!hasRomExtension(p.basename(file.path))) continue;
    final match = await identity.identify(file);
    // `guess` is the similarity tier, and it errs. A wrong border is worse than
    // a missing one (UI spec, section 3.1), so only exact name, canonical title
    // and CRC paint.
    if (match == null || match.confidence == MatchConfidence.guess) continue;
    owned.add(match.game.id);
  }
  return owned;
});

/// The files of the folder and of one level below it.
///
/// The extra level is not a whim: with `extractToFolder` on, the extracted ROM
/// lands in `<folder>/<game name>/`, and `_scanLibraryDirIsolate`
/// (`lib/providers/library_snapshot_provider.dart:273-294`) already counts that
/// depth. Scanning differently would give two answers to "did I already
/// download this?" inside the same screen.
Future<List<File>> _libraryFiles(String dir) async {
  final root = Directory(dir);
  if (!await root.exists()) return const [];

  final files = <File>[];
  try {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        try {
          await for (final sub in entity.list(followLinks: false)) {
            if (sub is File) files.add(sub);
          }
        } catch (_) {
          // Subfolder with no permission. Not a reason for the whole grid to go
          // without a border.
        }
      }
    }
  } catch (_) {
    // Folder deleted mid-scan, USB stick removed, permission denied. Returns
    // what it managed to read.
  }
  return files;
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/owned_games_provider_test.dart
```

Expected: `+8`, zero failures.

If the subfolder test fails with an empty set, check that `_file` created the parent: `File.writeAsString` does not create a directory, which is why the helper calls `file.parent.create(recursive: true)` first.

- [ ] **Step 5: Commit the provider**

```bash
# test agent
git add test/owned_games_provider_test.dart
git commit -m "test(grade): varredura da biblioteca devolve os jogos ja baixados"

# production agent
git add lib/providers/owned_games_provider.dart
git commit -m "feat(grade): varredura da biblioteca devolve os jogos ja baixados"
```

- [ ] **Step 6: Write the grid-with-border tests**

In `test/pack_grid_test.dart`, replace the whole `_host` helper with this version, which gains a parameter for already-downloaded games. **Note that `withoutFavoritesDisk` stays in the `overrides` list**: it came from Task 12 and losing it in this swap breaks the long-press case, which uses the real `catalogProvider`.

```dart
Widget _host(
  List<PackGridEntry> entries, {
  SourceIndex? index,
  void Function(PackGridEntry)? onOpenGame,
  Set<String>? downloaded,
  bool scanning = false,
}) {
  return ProviderScope(
    overrides: [
      // Stays here, and it is the easiest line to lose in this swap: the
      // `catalogProvider` of this test is the real one, and its constructor
      // listens to `favoritesProvider`, which goes to disk. Without the stub the
      // long-press case throws with `MissingPluginException` **after** having
      // passed. See the "Sixth locked decision".
      withoutFavoritesDisk,
      packGridEntriesProvider.overrideWithValue(entries),
      sourceIndexProvider.overrideWithValue(index ?? _index(matchesSomething: true)),
      ownedGameIdsProvider.overrideWith(
        // A `Completer` that nobody completes is the scan in progress. A
        // `Future.delayed` would leave a pending timer and the test would fail
        // at the end.
        (ref) => scanning ? Completer<Set<String>>().future : Future.value(downloaded ?? const <String>{}),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: PackGrid(onOpenGame: onOpenGame ?? (_) {})),
    ),
  );
}
```

Add the two imports at the top of the file:

```dart
import 'dart:async';
import 'package:roms_downloader/providers/owned_games_provider.dart';
```

And add the two tests at the end of `main`:

```dart
  testWidgets('the game already on disk goes marked to the tile', (tester) async {
    await tester.pumpWidget(_host(
      [
        _entry('snes/crystal-vanguard', 'Crystal Vanguard'),
        _entry('snes/super-vectron', 'Super Vectron'),
      ],
      downloaded: {'snes/crystal-vanguard'},
    ));
    await tester.pump();

    final tiles = tester.widgetList<PackGridItem>(find.byType(PackGridItem)).toList();
    expect(tiles.firstWhere((t) => t.title == 'Crystal Vanguard').isOwned, isTrue);
    expect(tiles.firstWhere((t) => t.title == 'Super Vectron').isOwned, isFalse);
  });

  testWidgets('while the scan is not finished nobody goes marked', (tester) async {
    await tester.pumpWidget(_host(
      [_entry('snes/crystal-vanguard', 'Crystal Vanguard')],
      downloaded: {'snes/crystal-vanguard'},
      scanning: true,
    ));
    await tester.pump();

    // Section 3.1: no border while the scan runs. A wrong border is worse than a
    // missing one, and at this instant the answer does not exist yet.
    expect(tester.widget<PackGridItem>(find.byType(PackGridItem)).isOwned, isFalse);
  });
```

- [ ] **Step 7: Run and watch it fail**

```bash
flutter test test/pack_grid_test.dart
```

Expected: `+8 -1`. The seven from Task 12 keep passing, and **one** of the two new ones fails, the border one, because `PackGrid` does not read the provider yet: `Expected: true / Actual: <false>`.

The other, "while the scan is not finished nobody goes marked", **passes before the wiring exists**, and that is expected. It asserts `isOwned == false`, and `false` is exactly the default that Task 12 left. A test that passes in the red phase is not proving anything today; it is guarding tomorrow, in case someone swaps the `valueOrNull ?? {}` for a `.value` or an optimistic default. Keep it and do not try to make it fail on purpose: forcing it to fail would require inverting the assertion, and then it would assert the opposite of section 3.1.

The first version of this plan said `+7 -2` here. It was wrong, and the one who caught it was the Task 13 implementer by reporting the divergence instead of swallowing the number.

- [ ] **Step 8: Wire the grid to the provider**

In `lib/widgets/game_grid/pack_grid.dart`, add the import:

```dart
import 'package:roms_downloader/providers/owned_games_provider.dart';
```

Inside `build`, right after the `selected` line, add:

```dart
    // The library scan (Task 13). `valueOrNull` is what delivers the rule of
    // section 3.1 for free: while it does not resolve, the set is empty and no
    // tile gets a border.
    final owned = ref.watch(ownedGameIdsProvider).valueOrNull ?? const <String>{};
```

And in the `itemBuilder`'s `PackGridItem`, replace the `hasSource` line with this pair:

```dart
                        hasSource: entry.hasSource,
                        isOwned: owned.contains(entry.game.id),
```

- [ ] **Step 9: Run and watch it pass**

```bash
flutter test test/pack_grid_test.dart
```

Expected: `+9`, zero failures.

Now the whole suite, because this Task closes the grid. (The one that closes Group 3 is Task 14; the grid itself is standing here.)

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Expected: `+260 -1`, with the only failure being the usual one, `test/rar_decompress_screen_test.dart: renders with extract disabled until a file and folder are picked`. Any other failure is a regression of this Task.

- [ ] **Step 10: Commit the wiring**

```bash
# test agent
git add test/pack_grid_test.dart
git commit -m "test(grade): grade marca o tile do jogo ja baixado e nada durante a varredura"

# production agent
git add lib/widgets/game_grid/pack_grid.dart
git commit -m "feat(grade): grade marca o tile do jogo ja baixado e nada durante a varredura"
```

---

### Task 14: `planFromEntries`, the rule of section 6

**Files:**
- Modify: `lib/services/source_pick_service.dart` (the new function coexists with `planFromGames`)
- Modify: `test/source_pick_service_test.dart` (the new tests go at the end of `main`)

The choice rule of section 6 of the UI spec, in its exact order: preferred region, highest revision, highest confidence, addon priority. It is the same rule that will choose the highlight of the detail screen in Task 15. **One rule, two places**, and its place is this file.

**Where region and revision come from.** `MatchedSource` carries neither of the two, and that is on purpose: an addon returns a file name and nothing more (locked decision of slice 4, "the addon is dumb"). The one that extracts the two from the name is `TitleMetadataParser.parseRomTitle`, which already exists, is already pure Dart and is already the parser the whole listing uses. Checked by running, not by reading:

| Name | `regions` | `revision` |
| --- | --- | --- |
| `Crystal Vanguard (USA).zip` | `[USA]` | `''` |
| `Crystal Vanguard (Japan).zip` | `[Japan]` | `''` |
| `Crystal Vanguard (USA) (Rev A).zip` | `[USA]` | `'A'` |
| `Super Vectron (Japan, USA) (En,Ja).zip` | `[Japan, USA]` | `''` |
| `Crystal Vanguard (World).zip` | `[World]` | `''` |

**Two inheritances you will not fix here.** The first: `World` is not treated as a wildcard, so against a `{'USA'}` filter a `(World)` ROM loses to a `(USA)` one. The second: revision is compared with string `compareTo`, so `Rev A` beats `Rev 1` because `'A' > '1'` in the character table. Both come from `filtering_service.dart:61-65` and `:151-157`, hold for today's grid, and changing either of them here would make the grid and the batch disagree about the same file. That disagreement is worse than the two inheritances together. If they are ever fixed, it is there, and both at the same time.

**Why the function asks for a `Game` resolver.** `SourcePick.game` is what actually enters the queue, and `TaskQueueService.startDownloads` only knows how to deal with `Game`. A `MatchedSource` is not a `Game`: in this slice it came from one, but in slice 4 it comes from an addon. Instead of synthesizing a `Game` here, and losing `details` and the `gameId` that the queue already uses, the function receives `resolveGame` and the caller decides how to resolve. In Task 20 it is a map by file name built over the catalog; in slice 4 it is the addon.

**Addon priority in this slice is the dead axis.** There is only one source, `kBuiltinAddonId`, so `sourcePriority` stays at the empty default and the axis never decides anything. It is here because section 6 lists it and because implementing it later would mean touching the comparator again, with the rule already in production in two places.

- [ ] **Step 1: Write the tests that fail**

Add at the top of `test/source_pick_service_test.dart` the missing imports:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
```

Add the helpers just below the `_game` that is already there:

```dart
MatchedSource _source(
  String filename, {
  MatchConfidence confidence = MatchConfidence.likely,
  String sourceId = 'listing',
  int size = 1000,
}) =>
    MatchedSource(filename: filename, sourceId: sourceId, confidence: confidence, size: size);

PackGridEntry _entry(String title, List<MatchedSource> sources) => PackGridEntry(
      game: PackGame(id: 'snes/${title.toLowerCase()}', title: title, dumps: [PackDump(name: title)]),
      sources: sources,
    );

/// The test resolver: every file name resolves, and the `Game` that comes out
/// is recognizable by name. Task 20 swaps this for a map over the catalog.
Game? _resolve(MatchedSource source) => _game(source.filename, source.size);

BatchPlan _plan(
  List<PackGridEntry> entries, {
  Set<String> regions = const {'USA'},
  List<String> priority = const [],
  GameResolver? resolver,
}) =>
    planFromEntries(
      entries,
      preferredRegions: regions,
      resolveGame: resolver ?? _resolve,
      sourcePriority: priority,
    );
```

And the tests at the end of `main`:

```dart
  test('with a single source, the reason says there was no choice', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [_source('Crystal Vanguard (Japan).zip')]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard (Japan).zip');
    expect(plan.picks.single.reason, 'the only source that has this game');
    // The region is not preferred and even so the source was chosen: the rule
    // orders candidates, it does not discard any.
    expect(plan.failures, isEmpty);
  });

  test('the preferred region wins, and the reason names the region', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (Japan).zip'),
        _source('Crystal Vanguard (USA).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard (USA).zip');
    expect(plan.picks.single.reason, 'chosen by your preferred region (USA)');
  });

  test('with an empty region filter the axis is neutral and the revision decides', () {
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [
          _source('Crystal Vanguard (USA).zip'),
          _source('Crystal Vanguard (Japan) (Rev A).zip'),
        ]),
      ],
      regions: const {},
    );

    expect(plan.picks.single.filename, 'Crystal Vanguard (Japan) (Rev A).zip');
    expect(plan.picks.single.reason, 'the newest revision (Rev A)');
  });

  test('the file with no region tag does not lose to the preferred one', () {
    // Mirrors `filtering_service.dart:61-65`, where metadata with no region
    // passes the filter instead of being discarded.
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard.zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard.zip');
  });

  test('within the same region, the higher revision wins', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (USA) (Rev A).zip'),
      ]),
    ]);

    expect(plan.picks.single.filename, 'Crystal Vanguard (USA) (Rev A).zip');
    expect(plan.picks.single.reason, 'the newest revision (Rev A)');
  });

  test('with region and revision tied, the higher confidence wins', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (USA).zip', confidence: MatchConfidence.guess),
        _source('Crystal Vanguard (USA).zip', confidence: MatchConfidence.confirmed),
      ]),
    ]);

    expect(plan.picks.single.reason, 'the most confident match among the 2 sources');
    expect(plan.picks.single.uncertain, isFalse);
  });

  test('everything else tied, addon priority decides', () {
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [
          _source('Crystal Vanguard (USA).zip', sourceId: 'slow'),
          _source('Crystal Vanguard (USA).zip', sourceId: 'fast'),
        ]),
      ],
      priority: const ['fast', 'slow'],
    );

    expect(plan.picks.single.reason, 'comes from the higher-priority addon');
  });

  test('addon priority picks the source, not only writes the reason', () {
    // The reason recomputes its own priority rank, so a mutant that neutralizes
    // the addon axis in `_compare` would keep the reason text right while
    // downloading the wrong file. The two sources differ in `size`, which is
    // not in `_compare`, so the sort winner is observable; the slow one is
    // first on purpose, since it would win by arrival order.
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [
          _source('Crystal Vanguard (USA).zip', sourceId: 'slow', size: 10),
          _source('Crystal Vanguard (USA).zip', sourceId: 'fast', size: 20),
        ]),
      ],
      priority: const ['fast', 'slow'],
    );

    expect(plan.picks.single.size, 20);
  });

  test('tied on everything it keeps the first, and the reason admits the tie', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [
        _source('Crystal Vanguard (USA).zip', size: 10),
        _source('Crystal Vanguard (USA).zip', size: 20),
      ]),
    ]);

    expect(plan.picks.single.size, 10);
    expect(plan.picks.single.reason, 'tie among 2 sources, kept the first');
  });

  test('a guess pick goes marked as uncertain', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [_source('Crystal Vanguard (USA).zip', confidence: MatchConfidence.guess)]),
    ]);

    // The batch does not verify CRC before enqueueing (section 6). It marks.
    expect(plan.picks.single.uncertain, isTrue);
  });

  test('a game with no source becomes a failure, not a pick', () {
    final plan = _plan([
      _entry('Crystal Vanguard', [_source('Crystal Vanguard (USA).zip')]),
      _entry('Emberfall', const []),
    ]);

    expect(plan.picks.map((p) => p.title), ['Crystal Vanguard']);
    expect(plan.failures.single.title, 'Emberfall');
    expect(plan.failures.single.gameId, 'pack:snes/emberfall');
    expect(plan.failures.single.reason, 'no installed source has this game');
  });

  test('the game whose sources do not resolve becomes a failure with another reason', () {
    final plan = _plan(
      [
        _entry('Crystal Vanguard', [_source('Crystal Vanguard (USA).zip')]),
      ],
      resolver: (_) => null,
    );

    expect(plan.picks, isEmpty);
    expect(plan.failures.single.reason, 'the source left the listing before the queue started');
  });
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/source_pick_service_test.dart
```

Expected: `The function 'planFromEntries' isn't defined` and `Undefined class 'GameResolver'`.

- [ ] **Step 3: Implement**

Add to `lib/services/source_pick_service.dart`. The new imports, at the top:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_metadata_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/utils/title_metadata_parser.dart';
```

E o corpo, abaixo de `planFromGames`:

```dart
/// How the caller turns a source into the `Game` that goes to the queue.
///
/// In this slice it is a catalog lookup by file name (Task 20). In slice 4 it
/// is the addon that answers. Returns `null` when the source no longer exists,
/// and then the game becomes a `PickFailure` instead of a pick.
typedef GameResolver = Game? Function(MatchedSource source);

typedef _Candidate = ({MatchedSource source, GameMetadata meta, Game game, int order});

/// The choice rule of section 6 of the UI spec, in its order: preferred region,
/// highest revision, highest confidence, addon priority.
///
/// It is the same rule that chooses the highlight of the detail screen. One
/// rule, two places: if you need a variation, change this function, do not
/// write another one.
BatchPlan planFromEntries(
  List<PackGridEntry> entries, {
  required Set<String> preferredRegions,
  required GameResolver resolveGame,
  List<String> sourcePriority = const [],
}) {
  final picks = <SourcePick>[];
  final failures = <PickFailure>[];

  for (final entry in entries) {
    if (entry.sources.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'no installed source has this game',
      ));
      continue;
    }

    final candidates = <_Candidate>[];
    for (var i = 0; i < entry.sources.length; i++) {
      final source = entry.sources[i];
      final game = resolveGame(source);
      if (game == null) continue;
      candidates.add((
        source: source,
        meta: TitleMetadataParser.parseRomTitle(source.filename),
        game: game,
        order: i,
      ));
    }

    if (candidates.isEmpty) {
      failures.add(PickFailure(
        gameId: entry.selectionKey,
        title: entry.game.title,
        reason: 'the source left the listing before the queue started',
      ));
      continue;
    }

    candidates.sort((a, b) => _compare(a, b, preferredRegions, sourcePriority));
    final winner = candidates.first;

    picks.add(SourcePick(
      gameId: entry.selectionKey,
      title: entry.game.title,
      filename: winner.source.filename,
      size: winner.source.size,
      sourceId: winner.source.sourceId,
      reason: _reason(winner, candidates, preferredRegions, sourcePriority),
      // The batch does not verify CRC before enqueueing (section 6): it marks
      // the guess and leaves the safety net to the post-download verification.
      uncertain: winner.source.confidence == MatchConfidence.guess,
      game: winner.game,
    ));
  }

  return BatchPlan(picks: picks, failures: failures);
}

int _compare(_Candidate a, _Candidate b, Set<String> preferred, List<String> priority) {
  final region = _regionRank(a, preferred).compareTo(_regionRank(b, preferred));
  if (region != 0) return region;

  // Inverted on purpose: the higher revision comes first.
  final revision = _compareRevision(b.meta.revision, a.meta.revision);
  if (revision != 0) return revision;

  // `MatchConfidence` is declared from most confident to least, so the lower
  // index is the best.
  final confidence = a.source.confidence.index.compareTo(b.source.confidence.index);
  if (confidence != 0) return confidence;

  final addon = _priorityRank(a, priority).compareTo(_priorityRank(b, priority));
  if (addon != 0) return addon;

  // The final tie-break is arrival order. It is here because `List.sort` does
  // not promise stability, and a batch that changes its result between two runs
  // with the same input would be impossible to report as a bug.
  return a.order.compareTo(b.order);
}

/// 0 is preferred, 1 is not.
///
/// With no region in the name the candidate does **not** lose, which mirrors
/// `filtering_service.dart:61-65`, where metadata with no region passes the
/// filter instead of being discarded.
int _regionRank(_Candidate candidate, Set<String> preferred) {
  if (preferred.isEmpty) return 0;
  if (candidate.meta.regions.isEmpty) return 0;
  return candidate.meta.regions.any(preferred.contains) ? 0 : 1;
}

/// Positive when [a] is newer than [b].
///
/// Lexical comparison, same as in `filtering_service.dart:151-157`, with the
/// same known limitation: `Rev A` beats `Rev 1`, and `1.10` loses to `1.2`.
/// Diverging from here would make the grid and the batch disagree.
int _compareRevision(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return -1;
  if (b.isEmpty) return 1;
  return a.compareTo(b);
}

int _priorityRank(_Candidate candidate, List<String> priority) {
  final index = priority.indexOf(candidate.source.sourceId);
  return index < 0 ? priority.length : index;
}

/// The spelled-out reason, which is the axis on which the winner beat the
/// runner-up. Mandatory, not decorative: it is the only thing that separates
/// "the app chose for you" from "the app chose at random" (section 7).
String _reason(
  _Candidate winner,
  List<_Candidate> ordered,
  Set<String> preferred,
  List<String> priority,
) {
  if (ordered.length == 1) return 'the only source that has this game';
  final runnerUp = ordered[1];

  if (_regionRank(winner, preferred) != _regionRank(runnerUp, preferred)) {
    final region = winner.meta.regions.where(preferred.contains).firstOrNull;
    return region == null
        ? 'chosen by your preferred region'
        : 'chosen by your preferred region ($region)';
  }

  // If the revisions differ, the winner's is the higher one, otherwise it would
  // not be the winner. That is why it can be named without checking again.
  if (_compareRevision(winner.meta.revision, runnerUp.meta.revision) != 0) {
    return 'the newest revision (Rev ${winner.meta.revision})';
  }

  if (winner.source.confidence != runnerUp.source.confidence) {
    return 'the most confident match among the ${ordered.length} sources';
  }

  if (_priorityRank(winner, priority) != _priorityRank(runnerUp, priority)) {
    return 'comes from the highest-priority addon';
  }

  return 'tie between ${ordered.length} sources, first one kept';
}
```

`firstOrNull` does **not** need an import. Verified by running a Dart file with no imports at all: `<String>[].firstOrNull` compiles and returns `null`. It is the same usage as `game_model.dart:90`, which also does not import `package:collection`.

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/source_pick_service_test.dart
```

Expected: `+16`, zero failures. These are the 4 from Task 6 plus the 12 from this one.

If the total-tie test fails by choosing the second source, the culprit is the `order` tiebreaker: verify that it is the **last** line of `_compare` and that `order` is the loop index, not the index after the `sort`.

Now the full suite, because this Task closes Group 3:

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Expected: `+272 -1`, with the only failure being the usual one, `test/rar_decompress_screen_test.dart: renders with extract disabled until a file and folder are picked`. Any other failure is a regression introduced by this Task.

- [ ] **Step 5: Commit**

```bash
# test agent
git add test/source_pick_service_test.dart
git commit -m "test(lote): regra de escolha por regiao, revisao, confianca e prioridade"

# production agent
git add lib/services/source_pick_service.dart
git commit -m "feat(lote): regra de escolha por regiao, revisao, confianca e prioridade"
```

---

# Group 4: the detail screen

Here the slice moves beyond the grid and into the screen that justifies it. The three Tasks in this group cover section 7 of the UI spec, and none of them touch the network: the CRC verification of section 8 belongs to Group 5.

---

### Task 15: the detail screen, common case

**Files:**
- Create: `lib/screens/game_detail_screen.dart`
- Create: `test/game_detail_screen_test.dart`
- Modify: `lib/providers/pack_grid_provider.dart` (two new providers at the end)
- Modify: `test/pack_grid_provider_test.dart` (two new tests at the end)

The section 7 screen: a top area with cover, title, metadata, synopsis, favorite heart and checkbox; a body with the highlight card, the reason in full, and the Download button.

**The screen does not know about the queue.** `onDownload` is a callback, for the same reason that `PackGrid.onOpenGame` is a callback: `TaskQueueService.startDownloads` drives the entire download pipeline, and a screen that calls it directly cannot be tested. The `HomeScreen` wires the two together, in Task 19.

**The screen does not choose the version on its own.** It calls `planFromEntries` with a single entry. That is literally the batch rule, and that is what section 6 means by "one rule, two places". If the screen's highlight and the batch's choice ever diverge, there is one bug and one file to fix.

**The favorite key in PACK MODE is `entry.selectionKey`**, with the `pack:` prefix. The SOURCE MODE favorite key remains `Game.gameId`. Both coexist in the same `Set` in `favorites_model.dart`, and that is precisely why the prefix exists (see the "Fourth locked decision").

**What this Task deliberately does not render:** the "no source" banner and the "N other sources" list. Both belong to Task 16. Here, when there is no pick, the card simply does not appear, and one test proves that, so Task 16 has a clear insertion point for the banner.

- [ ] **Step 1: Write the two failing provider tests**

At the end of `main` in `test/pack_grid_provider_test.dart`:

```dart
  test('the resolver finds the catalog game by the file name', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    final resolver = container.read(gameResolverProvider);
    final found = resolver(const MatchedSource(
      filename: 'Crystal Vanguard (USA).zip',
      sourceId: kBuiltinAddonId,
      confidence: MatchConfidence.likely,
      size: 2048,
    ));

    expect(found?.filename, 'Crystal Vanguard (USA).zip');
  });

  test('the resolver returns null for a source not in the catalog', () async {
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')]);
    await _ready(container);

    final resolver = container.read(gameResolverProvider);
    final found = resolver(const MatchedSource(
      filename: 'A Game That Left The Listing.zip',
      sourceId: kBuiltinAddonId,
      confidence: MatchConfidence.likely,
      size: 10,
    ));

    // It is the path that becomes a `PickFailure` in Task 14, and it has to
    // exist for real, otherwise the batch would break with a `null check` on
    // the first catalog reloaded during a selection.
    expect(found, isNull);
  });
```

Add at the top of the file the missing imports:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/pack_grid_provider_test.dart
```

Expected: `Undefined name 'gameResolverProvider'`.

- [ ] **Step 3: Implement the two providers**

At the end of `lib/providers/pack_grid_provider.dart`:

```dart
/// The user's preferred region, read from the filter that already exists.
///
/// It is a test seam, like `catalogGamesProvider` and `gridSearchQueryProvider`:
/// override **this** provider in tests, never the `catalogProvider`.
final preferredRegionsProvider = Provider<Set<String>>((ref) {
  return ref.watch(catalogProvider.select((state) => state.filter.regions));
});

/// How a source becomes the `Game` that enters the queue.
///
/// In this slice every source came from the console listing, so resolving is
/// finding the `Game` back by the file name. In slice 4 the one that answers is
/// the addon, and this provider starts consulting it. `planFromEntries` does not
/// need to know about either of the two.
final gameResolverProvider = Provider<GameResolver>((ref) {
  final byFilename = <String, Game>{};
  for (final game in ref.watch(catalogGamesProvider)) {
    // `putIfAbsent`: if two listing files have the same name, the first in the
    // catalog wins, which is the same order that `SourceIndex.build` already
    // uses. Two different answers for the same name would be worse.
    byFilename.putIfAbsent(game.filename, () => game);
  }
  return (source) => byFilename[source.filename];
});
```

The new import, at the top of the file:

```dart
import 'package:roms_downloader/services/source_pick_service.dart';
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/pack_grid_provider_test.dart
```

Expected: `+9`, zero failures. It is the 7 from Task 10 plus the 2 from this one.

- [ ] **Step 5: Write the screen test, which fails**

Create `test/game_detail_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';

import 'support/favorites_stub.dart';

const _target = PackTarget('snes', 'Super Nintendo');

PackGame _pg() => const PackGame(
      id: 'snes/crystal-vanguard',
      title: 'Crystal Vanguard',
      dumps: [PackDump(name: 'Crystal Vanguard (USA)')],
      synopsis: 'A boy, a fair and a time machine.',
      genre: 'RPG',
      publisher: 'Square',
      year: 1995,
    );

// No `cover` on purpose in every test: with a URL, `CachedNetworkImage` would
// attempt the network inside the test.
PackGridEntry _entry({List<MatchedSource> sources = const []}) =>
    PackGridEntry(game: _pg(), sources: sources);

MatchedSource _source(String filename, {int size = 4 * 1024 * 1024}) => MatchedSource(
      filename: filename,
      sourceId: kBuiltinAddonId,
      confidence: MatchConfidence.likely,
      size: size,
    );

Game _game(String filename) => Game(
      title: filename,
      url: 'https://example.org/snes/$filename',
      size: 4 * 1024 * 1024,
      consoleId: 'snes',
    );

Widget _host(
  PackGridEntry entry, {
  void Function(SourcePick)? onDownload,
}) {
  return ProviderScope(
    overrides: [
      withoutFavoritesDisk,
      packTargetProvider.overrideWithValue(_target),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue((source) => _game(source.filename)),
    ],
    child: MaterialApp(
      home: GameDetailScreen(entry: entry, onDownload: onDownload ?? (_) {}),
    ),
  );
}

void main() {
  testWidgets('shows title, system, year, publisher and genre', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [_source('Crystal Vanguard (USA).zip')])));

    expect(find.text('Crystal Vanguard'), findsWidgets);
    expect(find.text('Super Nintendo, 1995, Square, RPG'), findsOneWidget);
  });

  testWidgets('shows the synopsis', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [_source('Crystal Vanguard (USA).zip')])));

    expect(find.text('A boy, a fair and a time machine.'), findsOneWidget);
  });

  testWidgets('the highlight card brings file, size and reason', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    expect(find.text('Crystal Vanguard (USA).zip'), findsOneWidget);
    expect(find.text('4.0 MB, listing'), findsOneWidget);
    // The reason is mandatory, not decorative (section 7).
    expect(find.text('chosen by your preferred region (USA)'), findsOneWidget);
  });

  testWidgets('the Download button returns the whole pick', (tester) async {
    final downloaded = <String>[];
    await tester.pumpWidget(_host(
      _entry(sources: [_source('Crystal Vanguard (USA).zip')]),
      onDownload: (pick) => downloaded.add(pick.game.filename),
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Download'));
    await tester.pump();

    // The `Game` that comes out of the callback is the one the queue understands,
    // not a synthetic one.
    expect(downloaded, ['Crystal Vanguard (USA).zip']);
  });

  testWidgets('with no source the screen opens in full and with no highlight card', (tester) async {
    await tester.pumpWidget(_host(_entry()));

    // The 3% of section 3.1: the game still exists and is still favoritable.
    expect(find.text('A boy, a fair and a time machine.'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
  });

  testWidgets('the heart toggles the favorite', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [_source('Crystal Vanguard (USA).zip')])));

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pump();

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('the checkbox toggles the selection by the pack key', (tester) async {
    late WidgetRef captured;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        withoutFavoritesDisk,
        packTargetProvider.overrideWithValue(_target),
        preferredRegionsProvider.overrideWithValue(const {'USA'}),
        gameResolverProvider.overrideWithValue((source) => _game(source.filename)),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          captured = ref;
          return GameDetailScreen(
            entry: _entry(sources: [_source('Crystal Vanguard (USA).zip')]),
            onDownload: (_) {},
          );
        }),
      ),
    ));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(
      captured.read(catalogProvider).selectedGames,
      contains('pack:snes/crystal-vanguard'),
    );
  });
}
```

- [ ] **Step 6: Run and watch it fail**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: `Target of URI doesn't exist: '.../game_detail_screen.dart'`.

- [ ] **Step 7: Implement the screen**

Create `lib/screens/game_detail_screen.dart`:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// The section 7 UI-spec screen: one game, its sources and the reason for the
/// choice.
///
/// Not a bottom sheet and not an inline expansion. It is a route.
class GameDetailScreen extends ConsumerWidget {
  final PackGridEntry entry;

  /// What to do when the user taps Download.
  ///
  /// The screen does not know about the queue, for the same reason that
  /// `PackGrid` does not know about `Navigator`: `TaskQueueService.startDownloads`
  /// drives the entire download pipeline, and a screen that calls it directly
  /// cannot be tested. The `HomeScreen` wires the two together.
  final void Function(SourcePick pick) onDownload;

  const GameDetailScreen({super.key, required this.entry, required this.onDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = entry.game;
    final key = entry.selectionKey;
    final favorite = ref.watch(favoritesProvider).isFavorite(key);
    final isSelected = ref.watch(catalogProvider.select((s) => s.selectedGames)).contains(key);

    // The same batch rule, with a single entry. Section 6: one rule, two
    // places. Do not write a different choice here.
    final plan = planFromEntries(
      [entry],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: ref.watch(gameResolverProvider),
    );
    final pick = plan.picks.firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(game.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              favorite ? Icons.favorite : Icons.favorite_border,
              color: favorite ? Colors.red : null,
            ),
            onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(key),
          ),
          Checkbox(
            value: isSelected,
            onChanged: (_) => ref.read(catalogProvider.notifier).toggleGameSelection(key),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Top(game: game, system: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (pick != null) ...[
            const SizedBox(height: 16),
            _Highlight(pick: pick, onDownload: () => onDownload(pick)),
          ],
        ],
      ),
    );
  }
}

class _Top extends StatelessWidget {
  final PackGame game;
  final String system;

  const _Top({required this.game, required this.system});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Only what exists joins the line, else a game with no year or publisher
    // (most homebrews) leaves a dangling comma.
    final details = [
      system,
      if (game.year != null) '${game.year}',
      if ((game.publisher ?? '').isNotEmpty) game.publisher!,
      if ((game.genre ?? '').isNotEmpty) game.genre!,
    ].where((part) => part.isNotEmpty).join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _cover(context),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(details, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cover(BuildContext context) {
    final url = game.cover;
    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.videogame_asset_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, _, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorListener: (_) {},
    );
  }
}

/// The highlight card for the chosen version. The reason line is mandatory.
class _Highlight extends StatelessWidget {
  final SourcePick pick;
  final VoidCallback onDownload;

  const _Highlight({required this.pick, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(pick.filename, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            '${formatBytes(pick.size)}, ${pick.sourceId}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(pick.reason, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onDownload, child: const Text('Download')),
          ),
        ],
      ),
    );
  }
}
```

`pick.sourceId` is the field that Task 4 already created in `SourcePick` and that Task 14 already fills with `winner.source.sourceId`. It is the origin of the "4.0 MB, Myrient" line of section 7. In this slice it always comes out as `listing`, because there is only one source, and that is precisely why it is a field and not a hardcoded string.

- [ ] **Step 8: Run and watch it pass**

```bash
flutter test test/game_detail_screen_test.dart test/source_pick_model_test.dart test/source_pick_service_test.dart test/pack_grid_provider_test.dart
```

Expected: `+38`, zero failures. These are 7 from this screen, 6 from the model, 16 from the service, and 9 from the providers.

Likely pitfall: if `find.text('Crystal Vanguard')` finds more than one widget in the first test, it is the title in the `AppBar` plus the title at the top. That is why the test uses `findsWidgets` and not `findsOneWidget`.

- [ ] **Step 9: Commit**

```bash
# test agent
git add test/game_detail_screen_test.dart test/pack_grid_provider_test.dart
git commit -m "test(detalhe): tela de detalhe com destaque, motivo, favorito e selecao"

# production agent
git add lib/screens/game_detail_screen.dart lib/providers/pack_grid_provider.dart
git commit -m "feat(detalhe): tela de detalhe com destaque, motivo, favorito e selecao"
```

---

### Task 16: the "no source" banner and the "N other sources" list

**Files:**
- Modify: `lib/screens/game_detail_screen.dart`
- Modify: `test/game_detail_screen_test.dart`

The two pieces that Task 15 left out, which close section 7 of the UI spec: the banner that appears in place of the card when no source has the game, and the collapsed list with the sources that lost the highlight.

**The banner does not write its own text.** It shows `plan.failures.first.reason`, which is the same string the batch sheet shows for the same game. If the rule ever distinguishes more cases, both places change together for free. It is the "one rule, two places" of section 6 applied to failures as well.

**The banner does not yet have the shortcut to the addon screen** that section 7 asks for. The addon screen is slice 4, and a button that navigates nowhere is worse than no button at all. When slice 4 creates the screen, the shortcut goes here, inside `_NoSource`.

**The list rows have no Download button.** Section 8 asks for a per-row button only in the "cannot verify" state, which is Task 18. Here the list is informational: it exists so the user can confirm the app saw the other sources and chose deliberately.

**The source type is `HTTP` and is fixed in this slice.** Every source comes from the console listing, which is HTTP and nothing else. `SEED` and `RD` arrive when the addon declares its type, in slices 4 and 6. The constant exists for the day the value stops being a single one.

**Watch the word "confidence" in the rows.** The row label is the **match** confidence (`MatchConfidence`, from slice 2), not the CRC verification. See the "Second locked decision" at the top: they are two axes and they do not mix. Task 18 adds the CRC state as a fifth piece of the same row, without removing this one.

- [ ] **Step 1: Adjust the two test-file helpers**

In `test/game_detail_screen_test.dart`, `_source` needs to be able to vary the confidence and `_host` needs to be able to swap the resolver. Replace `_source` and `_host` in full with these:

```dart
MatchedSource _source(
  String filename, {
  int size = 4 * 1024 * 1024,
  MatchConfidence confidence = MatchConfidence.likely,
}) =>
    MatchedSource(
      filename: filename,
      sourceId: kBuiltinAddonId,
      confidence: confidence,
      size: size,
    );

// Top-level function, not a lambda variable, because of the
// `prefer_function_declarations_over_variables` lint that comes enabled in
// `flutter_lints`.
Game? _resolveDefault(MatchedSource source) => _game(source.filename);

Widget _host(
  PackGridEntry entry, {
  void Function(SourcePick)? onDownload,
  GameResolver? resolver,
}) {
  return ProviderScope(
    overrides: [
      withoutFavoritesDisk,
      packTargetProvider.overrideWithValue(_target),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue(resolver ?? _resolveDefault),
    ],
    child: MaterialApp(
      home: GameDetailScreen(entry: entry, onDownload: onDownload ?? (_) {}),
    ),
  );
}
```

And add the missing import at the top:

```dart
import 'package:roms_downloader/services/source_pick_service.dart';
```

The seven tests from Task 15 continue calling `_source('x.zip')` and `_host(entry)` with no named parameters, so none of them change.

- [ ] **Step 2: Write the eleven missing tests**

At the end of `main`, in the same file:

```dart
  testWidgets('with no source, the band says why there is nothing to download', (tester) async {
    await tester.pumpWidget(_host(_entry()));

    // The same string the batch sheet shows for the same game. If you just
    // wrote a new string here, it already exists in `source_pick_service.dart`
    // and must come from there.
    expect(find.text('no installed addon has this game'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
  });

  testWidgets('when the source does not resolve, the band uses the other reason', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [_source('Crystal Vanguard (USA).zip')]),
      resolver: (_) => null,
    ));

    expect(find.text('the source left the listing before the queue started'), findsOneWidget);
  });

  testWidgets('with no pick, the unresolved source still appears in the list', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [_source('Crystal Vanguard (USA).zip')]),
      resolver: (_) => null,
    ));

    // Nothing was picked, so no source is "the other". The list still opens:
    // hiding what exists would make the band look like a lie.
    expect(find.text('1 other source'), findsOneWidget);
  });

  testWidgets('with a single source there is no other-sources list', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [_source('Crystal Vanguard (USA).zip')])));

    // This test passes before and after the implementation. It is not an
    // implementation lock; it is a lock against the list appearing empty later.
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('with three sources, the counter says 2 other sources', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
      _source('Crystal Vanguard (Europe).zip'),
    ])));

    expect(find.text('2 other sources'), findsOneWidget);
  });

  testWidgets('with two sources, the counter is singular', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    // "2 other sources" with count 1 would be the text produced by a counter
    // written without thinking, and the UI spec writes counters correctly.
    expect(find.text('1 other source'), findsOneWidget);
  });

  testWidgets('the list starts collapsed', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    expect(find.text('1 other source'), findsOneWidget);
    expect(find.text('Crystal Vanguard (Japan).zip'), findsNothing);
  });

  testWidgets('expanded, each row carries file, size, addon, type and confidence', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [
      _source('Crystal Vanguard (Japan).zip'),
      _source('Crystal Vanguard (USA).zip'),
    ])));

    await tester.tap(find.text('1 other source'));
    await tester.pumpAndSettle();

    expect(find.text('Crystal Vanguard (Japan).zip'), findsOneWidget);
    expect(find.text('4.0 MB, listing, HTTP, likely match'), findsOneWidget);
  });

  testWidgets('the guess row shows a guessed match', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [
      _source('Crystal Vanguard (USA).zip'),
      _source('Crystal Vanguard (Japan).zip', confidence: MatchConfidence.guess),
    ])));

    await tester.tap(find.text('1 other source'));
    await tester.pumpAndSettle();

    // Match confidence, not CRC. See the "Second locked decision".
    expect(find.text('4.0 MB, listing, HTTP, guessed match'), findsOneWidget);
  });

  testWidgets('two identical sources: the pick leaves the list only once', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [
      _source('Crystal Vanguard (USA).zip', size: 10),
      _source('Crystal Vanguard (USA).zip', size: 20),
    ])));

    await tester.tap(find.text('1 other source'));
    await tester.pumpAndSettle();

    // The 10-byte one won by arrival order (Task 14). If the list removed all
    // sources with the same name, the 20-byte one would vanish with it and the
    // user would lose a real source from view.
    expect(find.text('10.0 B, listing'), findsOneWidget);
    expect(find.text('20.0 B, listing, HTTP, likely match'), findsOneWidget);
  });

  testWidgets('the highlight card marks the source type', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [_source('Crystal Vanguard (USA).zip')])));

    // The `HTTP` in the top-right corner of the section 7 mockup. With a
    // single source there is no list, so this is the only `HTTP` on screen.
    expect(find.text('HTTP'), findsOneWidget);
  });
```

- [ ] **Step 3: Run and watch it fail**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: `+8 -10`. The 7 from Task 15 pass plus `with a single source there is no other-sources list`, which is the test that was already passing by design. The ten others fail with `Expected: exactly one matching candidate` and `Actual: _TextFinder:<zero widgets with text ...>`, and the two that `tap` fail earlier, on the `tap` itself, because there is nothing to tap.

- [ ] **Step 4: Implement**

In `lib/screens/game_detail_screen.dart`, add the `MatchConfidence` import at the top:

```dart
import 'package:roms_downloader/models/game_match_model.dart';
```

Inside `build`, right below the line `final pick = plan.picks.firstOrNull;`:

```dart
    final failure = plan.failures.firstOrNull;
    final others = _otherSources(entry, pick);
```

And replace the `ListView`'s whole `children:` list with this one:

```dart
        children: [
          _Top(game: game, system: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (pick != null) ...[
            const SizedBox(height: 16),
            _Highlight(pick: pick, onDownload: () => onDownload(pick)),
          ] else if (failure != null) ...[
            const SizedBox(height: 16),
            _NoSource(reason: failure.reason),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OtherSources(sources: others),
          ],
        ],
```

In `_Highlight`, replace the first line of the `Column`, currently `Text(pick.filename, ...)`, with this `Row`:

```dart
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pick.filename,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _kSourceKind,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
```

And add, at the end of the file:

```dart
/// The source kind, which in this slice is a single one.
///
/// Every source comes from the console's HTTP listing. The `SEED` and `RD` of
/// section 7 of the UI spec arrive when the addon declares the kind (slice 4
/// and slice 6). It is a constant instead of a loose literal for the day it
/// becomes a field.
const _kSourceKind = 'HTTP';

/// The sources that did not win the highlight, in the order the source gave them.
///
/// Removes **one** copy of the winner, not every source with the same name: two
/// sources can serve homonymous files of different sizes, and dropping both
/// would hide a real source. With no pick at all it returns everything, because
/// then none of them is "the other one" and hiding what exists would make the
/// "no source" banner look like a lie.
List<MatchedSource> _otherSources(PackGridEntry entry, SourcePick? pick) {
  if (pick == null) return entry.sources;

  final others = <MatchedSource>[];
  var alreadyRemoved = false;
  for (final source in entry.sources) {
    final isTheWinner = !alreadyRemoved &&
        source.filename == pick.filename &&
        source.size == pick.size &&
        source.sourceId == pick.sourceId;
    if (isTheWinner) {
      alreadyRemoved = true;
      continue;
    }
    others.add(source);
  }
  return others;
}

String _otherLabel(int count) => count == 1 ? '1 other source' : '$count other sources';

/// The **match** confidence, which is not the CRC verification.
///
/// See the "Second locked decision" of the slice 3 plan: they are two axes and
/// they do not mix. Task 18 adds the CRC state as one more piece of the same
/// row, without removing this one.
String _confidenceLabel(MatchConfidence confidence) => switch (confidence) {
      MatchConfidence.confirmed => 'confirmed match',
      MatchConfidence.likely => 'likely match',
      MatchConfidence.guess => 'guessed match',
    };

/// The banner that replaces the card when there is nothing to download.
///
/// The text comes from `PickFailure.reason`, meaning from the same rule the
/// batch sheet uses. The screen does not invent its own reason.
///
/// The shortcut to the addon screen that section 7 asks for is not here yet.
/// The addon screen is slice 4; when it exists, the button goes inside this
/// widget.
class _NoSource extends StatelessWidget {
  final String reason;

  const _NoSource({required this.reason});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reason, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// The collapsed list from section 7. Informational: the per-row Download
/// button belongs to the "cannot verify" state of section 8, which is Task 18.
class _OtherSources extends StatelessWidget {
  final List<MatchedSource> sources;

  const _OtherSources({required this.sources});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // `ExpansionTile` draws a divider above and below as soon as it opens,
      // and inside a `ListView` of cards that becomes two stray lines in the
      // middle of the screen.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _otherLabel(sources.length),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [for (final source in sources) _SourceRow(source: source)],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final MatchedSource source;

  const _SourceRow({required this.source});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(source.filename, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            // The five pieces that section 7 asks for, in this order.
            '${formatBytes(source.size)}, ${source.sourceId}, '
            '$_kSourceKind, ${_confidenceLabel(source.confidence)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: Run and watch it pass**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: `+18`, zero failures. These are the 7 from Task 15 plus the 11 from this one.

Two likely pitfalls:

If `the list starts collapsed` fails finding `Crystal Vanguard (Japan).zip` with the list closed, you replaced `ExpansionTile` with a `Column` + `Visibility` or set `maintainState: true`. A closed `ExpansionTile` does **not** build its children, and that is what this test depends on.

If the two `tap` tests fail with `Actual: _TextFinder:<zero widgets>` right after `pumpAndSettle`, verify that you called `pumpAndSettle` and not `pump`: the opening is animated, and a single `pump` leaves the list halfway, still `Offstage`.

- [ ] **Step 6: Run the full suite**

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Expected: `+292 -1`, with the usual failure, `test/rar_decompress_screen_test.dart: renders with extract disabled until a file and folder are picked`. Closes Group 4: 178 from the baseline plus 114 from the sixteen Tasks.

- [ ] **Step 7: Commit**

```bash
# test agent
git add test/game_detail_screen_test.dart
git commit -m "test(detalhe): faixa de sem fonte e lista de outras fontes"

# production agent
git add lib/screens/game_detail_screen.dart
git commit -m "feat(detalhe): faixa de sem fonte e lista de outras fontes"
```

---

# Group 5: CRC verification

The full section 8 of the UI spec. It is the only group in this slice that touches the network, and only lightly: two requests of 326 bytes per suspect source, without downloading anything.

Read the "Second locked decision" at the top before writing the first line. The expensive mistake in this group is assuming `MatchConfidence` gains a new value. It does not.

---

### Task 17: `SourceVerification`, the service and the provider

**Files:**
- Create: `lib/models/source_verification_model.dart`
- Create: `lib/services/source_verification_service.dart`
- Create: `lib/providers/source_verification_provider.dart`
- Test: `test/source_verification_service_test.dart`
- Test: `test/source_verification_provider_test.dart`

The verification plumbing, with no screen at all. Task 18 plugs it in.

**Why it is not the `CrcConfirmService` from slice 2.** That service answers an **open** question: "which game is this file?", and its answer is a `GameMatch` that can correct the name guess. Here the question is **closed**: "does this file belong to this game?", and the answer is a three-value verdict that the screen paints. The difference is not style: `confirm` returns `byName` unchanged both when it could not read anything and when it read and could not decide, and for section 8 those are two different states, `impossible` and `crcDiscarded`. Squeezing both into one method would cost a return type with optional fields that only one of the two callers reads.

**What the two truly share** is `ZipCentralDirectory.read`, which is where the hard part lives and which both call without copying a single line.

**The cache is the Riverpod family itself.** The provider is **not** `autoDispose`, and that is the literal implementation of "the verification result is cached per (source, file), so the second opening of the same game is instant". What stays in memory is one enum per file seen, not the bytes.

- [ ] **Step 1: Write the service tests, failing**

Create `test/source_verification_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_verification_service.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

/// Test pack CRCs, in the numeric form the central directory stores.
const crystalUsa = 0x2D206BF7;
const crystalJapan = 0xABCD1234;
const pixelEurope = 0xA31BEAD4;
const outsider = 0xDEADBEEF;

const crystalVanguard = 'snes/crystal-vanguard';

void main() {
  late PackMatcher matcher;
  final uri = Uri.parse('https://example/file.zip');

  setUp(() => matcher = PackMatcher(buildPack()));

  test('does not hit the network when the file is not a zip', () async {
    var calls = 0;
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: (u, r) async {
        calls++;
        throw StateError('should not have hit the network');
      },
    );

    final out = await service.verify(uri, 'Crystal Vanguard (USA).7z', crystalVanguard);

    // There is no Range reader for 7z or rar. Impossible is not "bad source",
    // it is "cannot tell".
    expect(out, SourceVerification.impossible);
    expect(calls, 0);
  });

  test('an inner CRC that is a dump of this game', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)])).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcOk,
    );
  });

  test('any dump of the game matches, not only the named one', () async {
    // The file is named USA but contains the Japanese dump. It is still Crystal
    // Vanguard, and the question this class answers is about the game, not the
    // version.
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', crystalJapan)])).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcOk,
    );
  });

  test('an inner CRC that belongs to another game is discarded', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', pixelEurope)])).fetch,
    );

    // The name says one thing and the CRC says another. This is the source
    // section 8 says to remove from the highlight.
    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcDiscarded,
    );
  });

  test('an inner CRC that belongs to no game in the pack is discarded', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([cdEntry('rom.sfc', outsider)])).fetch,
    );

    // A hack, a bad dump, a translation. Not this game, so it goes down.
    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.crcDiscarded,
    );
  });

  test('a zip with no ROM inside disproves nothing', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(buildZip([
        cdEntry('readme.txt', outsider),
        cdEntry('bonus.zip', outsider),
      ])).fetch,
    );

    // Neither entry has a CRC comparable with the pack (section 5.8, limit 1),
    // so there is no evidence either way.
    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.impossible,
    );
  });

  test('a server without Range support leaves verification impossible', () async {
    final service = SourceVerificationService(
      matcher: matcher,
      fetch: FakeRangeServer(
        buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]),
        status: 200,
      ).fetch,
    );

    expect(
      await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard),
      SourceVerification.impossible,
    );
  });

  test('two short requests, not the whole file', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final service = SourceVerificationService(matcher: matcher, fetch: server.fetch);

    await service.verify(uri, 'Crystal Vanguard (USA).zip', crystalVanguard);

    // The 326 bytes from section 8: one suffix to find the EOCD and one exact
    // range for the central directory.
    expect(server.asked.length, 2);
    expect(server.asked.first, 'bytes=-256');
  });
}
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/source_verification_service_test.dart
```

Expected: `Target of URI doesn't exist: 'package:roms_downloader/models/source_verification_model.dart'`.

- [ ] **Step 3: Implement the model and the service**

Create `lib/models/source_verification_model.dart`:

```dart
/// The **a-posteriori** axis of confidence in a source: what the CRC
/// verification said after reading the remote file's header.
///
/// Do not confuse with `MatchConfidence`, which is the **a-priori** axis and
/// comes from the name tier (slice 2). They are two axes and they do not mix:
/// see the "Second locked decision" in the slice 3 plan. If you find yourself
/// wanting to add a `crcOk` to `MatchConfidence`, this is the enum you wanted.
///
/// Pure Dart, with no imports, by design.
enum SourceVerification {
  /// Nobody asked. It is the state of every source outside the detail screen:
  /// the grid does not verify and the batch does not verify (UI spec section 6),
  /// and a console without a pack has nothing to verify against.
  notVerified,

  /// Both requests are in flight.
  verifying,

  /// A dump of this game is inside. Certainty, not a guess.
  crcOk,

  /// Read the CRC and it does not belong to this game. The source leaves the
  /// highlight and moves to the list, flagged (section 8).
  crcDiscarded,

  /// Could not tell: no Range support, file is not a ZIP, ZIP has no ROM.
  /// **Not** a synonym for a bad source, so it does not discard.
  impossible,
}
```

Create `lib/services/source_verification_service.dart`:

```dart
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// Answers a closed question: does **this** remote file contain a dump of
/// **this** game?
///
/// It is a cousin of `CrcConfirmService`, not the same thing. There the
/// question is open, "which game is this file", and the answer is a `GameMatch`
/// that can correct the name guess. Here the answer is a verdict that the
/// screen paints. `confirm` returns `byName` unchanged both when it could not
/// read anything and when it read and could not decide, and here those two
/// cases are different states. What the two truly share is
/// `ZipCentralDirectory.read`, which is where the hard part lives.
///
/// Pure Dart by design. Do not add a `package:flutter` import.
class SourceVerificationService {
  final PackMatcher matcher;
  final RangeFetch fetch;

  const SourceVerificationService({required this.matcher, required this.fetch});

  /// Never throws: every failure becomes [SourceVerification.impossible].
  Future<SourceVerification> verify(
      Uri uri, String sourceName, String gameId) async {
    // No Range reader for 7z or rar, so don't spend the request.
    if (!sourceName.toLowerCase().endsWith('.zip')) {
      return SourceVerification.impossible;
    }

    final entries = await ZipCentralDirectory.read(uri, fetch);
    if (entries == null) return SourceVerification.impossible;

    var sawRom = false;
    for (final entry in entries) {
      // `crcMatchesRom` excludes the compressed-inside-compressed case, whose
      // CRC belongs to the compressed bytes, not the ROM (section 5.8, limit 1).
      if (!entry.crcMatchesRom) continue;
      sawRom = true;
      final hit = matcher.matchCrc(entry.crc, sourceName: sourceName);
      if (hit != null && hit.game.id == gameId) return SourceVerification.crcOk;
    }

    // A zip with only a readme and cover disproves nothing, so do not discard.
    // A zip with a ROM that is not this game does disprove, and discards.
    return sawRom
        ? SourceVerification.crcDiscarded
        : SourceVerification.impossible;
  }
}
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/source_verification_service_test.dart
```

Expected: `+8`, zero failures.

- [ ] **Step 5: Write the provider tests, failing**

Create `test/source_verification_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/services/pack_matcher.dart';
import 'package:roms_downloader/services/source_verification_service.dart';

import 'support/pack_fixture.dart';
import 'support/zip_fixture.dart';

const _target = PackTarget('snes', 'Super Nintendo');
const crystalUsa = 0x2D206BF7;

SourceVerificationRequest _request({String? url = 'https://example/ct.zip'}) => (
      sourceId: 'listing',
      filename: 'Crystal Vanguard (USA).zip',
      url: url,
      gameId: 'snes/crystal-vanguard',
    );

SourceVerificationService _service(FakeRangeServer server) =>
    SourceVerificationService(matcher: PackMatcher(buildPack()), fetch: server.fetch);

ProviderContainer _container({
  PackTarget? target = _target,
  SourceVerificationService? service,
}) {
  final container = ProviderContainer(overrides: [
    packTargetProvider.overrideWithValue(target),
    if (service != null)
      sourceVerificationServiceProvider(_target).overrideWith((ref) => service),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('no selected console verifies nothing', () async {
    final container = _container(target: null);

    expect(
      await container.read(sourceVerificationProvider(_request()).future),
      SourceVerification.notVerified,
    );
  });

  test('console without a pack stays notVerified', () async {
    final container = ProviderContainer(overrides: [
      packTargetProvider.overrideWithValue(_target),
      packMatcherProvider(_target).overrideWith((ref) => null),
    ]);
    addTearDown(container.dispose);

    expect(
      await container.read(sourceVerificationProvider(_request()).future),
      SourceVerification.notVerified,
    );
  });

  test('a source without a url is impossible', () async {
    final container = _container();

    expect(
      await container.read(sourceVerificationProvider(_request(url: null)).future),
      SourceVerification.impossible,
    );
  });

  test('a url that does not parse is impossible', () async {
    final container = _container();

    // `Uri.tryParse` returns null here because of the unmatched bracket.
    expect(
      await container.read(sourceVerificationProvider(_request(url: 'http://[')).future),
      SourceVerification.impossible,
    );
  });

  test('the service verdict passes through intact', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final container = _container(service: _service(server));

    expect(
      await container.read(sourceVerificationProvider(_request()).future),
      SourceVerification.crcOk,
    );
  });

  test('the state is verifying while the read runs', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final container = _container(service: _service(server));

    // `verifying` is not a value the provider returns: it is the translated
    // `AsyncLoading`.
    expect(
      verificationOf(container.read(sourceVerificationProvider(_request()))),
      SourceVerification.verifying,
    );

    await container.read(sourceVerificationProvider(_request()).future);

    expect(
      verificationOf(container.read(sourceVerificationProvider(_request()))),
      SourceVerification.crcOk,
    );
  });

  test('the same source and file pair is read only once', () async {
    final server = FakeRangeServer(buildZip([cdEntry('Crystal Vanguard (USA).sfc', crystalUsa)]));
    final container = _container(service: _service(server));

    await container.read(sourceVerificationProvider(_request()).future);
    await container.read(sourceVerificationProvider(_request()).future);

    // Two requests, not four. It is the cache from section 8, and it is the
    // live Riverpod family, not a hand-written `Map`.
    expect(server.asked.length, 2);
  });

  test('an error becomes impossible, not a red screen', () async {
    expect(
      verificationOf(AsyncError(Exception('pack did not load'), StackTrace.empty)),
      SourceVerification.impossible,
    );
  });
}
```

- [ ] **Step 6: Run and watch it fail**

```bash
flutter test test/source_verification_provider_test.dart
```

Expected: `Target of URI doesn't exist: '.../source_verification_provider.dart'`.

- [ ] **Step 7: Implement the provider**

Create `lib/providers/source_verification_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/pack_index_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/identity_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/services/source_verification_service.dart';
import 'package:roms_downloader/services/zip_central_directory.dart';

/// What identifies a verification request.
///
/// It is a record, not a class, because records have structural equality for
/// free, and that equality is what makes the Riverpod family cache. With a
/// class without `operator ==`, every rebuild would create a new key and the
/// verification would run again every frame, with two requests at a time.
///
/// The effective key is (source, file), as section 8 of the UI spec requires.
/// The other two fields are derived from those two and are here only so the
/// provider does not need to receive the full source.
typedef SourceVerificationRequest = ({
  String sourceId,
  String filename,
  String? url,
  String gameId,
});

/// The verifier for the current console. Null when the console has no pack,
/// which is the same contract as `packMatcherProvider`.
///
/// Kept separate from the verdict provider because it is the one that carries
/// the production `fetch`, and it is the one tests override to avoid the network.
final sourceVerificationServiceProvider =
    FutureProvider.family<SourceVerificationService?, PackTarget>((ref, target) async {
  final matcher = await ref.watch(packMatcherProvider(target).future);
  if (matcher == null) return null;
  return SourceVerificationService(
    matcher: matcher,
    fetch: ZipCentralDirectory.httpRangeFetch,
  );
});

/// The CRC verdict for one source.
///
/// **Not `autoDispose`, by design.** The live family is the cache that section
/// 8 asks for when it says the second opening of the same game is instant. What
/// stays in memory is one enum per (source, file) seen, not the bytes.
///
/// Never returns [SourceVerification.verifying]: while the read runs, the
/// `AsyncValue` itself is in `verifying`. Translate it with [verificationOf].
final sourceVerificationProvider =
    FutureProvider.family<SourceVerification, SourceVerificationRequest>((ref, request) async {
  final target = ref.watch(packTargetProvider);
  if (target == null) return SourceVerification.notVerified;

  final url = request.url;
  if (url == null) return SourceVerification.impossible;
  final uri = Uri.tryParse(url);
  if (uri == null) return SourceVerification.impossible;

  final service = await ref.watch(sourceVerificationServiceProvider(target).future);
  if (service == null) return SourceVerification.notVerified;

  return service.verify(uri, request.filename, request.gameId);
});

/// The state the screen paints, derived from what the provider returned.
///
/// An error becomes `impossible` and not a red screen: `verify` never throws,
/// so reaching here means the console pack did not load, and in that case
/// what the user needs to know is that verification was not possible.
SourceVerification verificationOf(AsyncValue<SourceVerification> value) => value.when(
      data: (verdict) => verdict,
      loading: () => SourceVerification.verifying,
      error: (_, __) => SourceVerification.impossible,
    );
```

- [ ] **Step 8: Run and watch it pass**

```bash
flutter test test/source_verification_service_test.dart test/source_verification_provider_test.dart
```

Expected: `+16`, zero failures.

Likely pitfall: if `console without a pack stays notVerified` blows up trying the network, it is because `packMatcherProvider` did not accept the override and fell through to the real body, which calls `metadataPackProvider`. The correct form for a family member in Riverpod 2.6 is `packMatcherProvider(_target).overrideWith((ref) => null)`, with the argument in parentheses **before** `overrideWith`.

- [ ] **Step 9: Commit**

```bash
# test agent
git add test/source_verification_service_test.dart test/source_verification_provider_test.dart
git commit -m "test(crc): veredito de verificacao por CRC e o cache por fonte e arquivo"

# production agent
git add lib/models/source_verification_model.dart lib/services/source_verification_service.dart lib/providers/source_verification_provider.dart
git commit -m "feat(crc): veredito de verificacao por CRC e o cache por fonte e arquivo"
```

---

### Task 18: CRC verification on the detail screen

**Files:**
- Modify: `lib/services/source_pick_service.dart` (one new function at the end)
- Modify: `lib/screens/game_detail_screen.dart` (the entire file)
- Modify: `test/source_pick_service_test.dart` (eight new tests at the end)
- Modify: `test/game_detail_screen_test.dart` (ten new tests at the end, plus `_host`)

Section 8 of the UI spec wired into the screen. It is the longest Task in the slice, and the reason is that the highlight rule now depends on one asynchronous state per source.

**The rule, locked, in order:**

1. A `crcDiscarded` source **never** competes for the highlight. It moves to the list, flagged.
2. If any `crcOk` remains, the highlight comes **only** from the `crcOk` sources, and the reason becomes `confirmed by CRC, this is exactly the dump`. This is where the highlight switches files, which is the entire point of section 8.
3. If no `crcOk` remains and **all** remaining sources are `impossible`, the "not sure about any" state kicks in: nothing in the highlight, the list opens expanded and each row gets its own Download.
4. Outside those cases, the highlight is the Task 16 one, chosen by name.
5. If no source remains because all were discarded, the banner appears with the reason `no source passed CRC verification`.

**The button says "Download anyway" when `verifying && !confirmed`.** If one source already beat the CRC, the certainty is given and the read still running on a losing source can no longer change the highlight. Making the button hesitate at that point would be hesitating for nothing.

**The rule is a pure function, outside the widget.** `splitByVerification` goes into `source_pick_service.dart`, next to `planFromEntries`, and receives already-resolved states instead of a `WidgetRef`. Eight of the eighteen tests in this Task raise no widget at all because of that.

**Do not call `ref.watch` from inside a child widget.** The screen resolves the source states **once**, in the `ConsumerWidget`'s `build`, and passes ready data downward. `_OtherSources` and `_SourceRow` remain dumb widgets, like everything else in this slice.

**The `"no source passed CRC verification"` banner string is the only one on this screen that does not come from `PickFailure`.** And it must be that way: the batch does not verify CRC, so the batch rule cannot know this state. It is annotated in the code so nobody "fixes" it by moving the string to the service.

- [ ] **Step 1: Write the eight failing pure-function tests**

At the end of `main` in `test/source_pick_service_test.dart`:

```dart
  test('no sources means nothing eligible and no uncertainty', () {
    final split = splitByVerification(const []);

    expect(split.eligible, isEmpty);
    expect(split.discarded, isEmpty);
    expect(split.confirmed, isFalse);
    expect(split.verifying, isFalse);
    // Zero sources is the "no source" banner of Task 16, not the new state.
    expect(split.noCertainty, isFalse);
  });

  test('without verification all sources compete', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.notVerified),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.eligible.length, 2);
    expect(split.confirmed, isFalse);
    expect(split.noCertainty, isFalse);
  });

  test('one CRC-confirmed source removes the unconfirmed from the race', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.notVerified),
      _v('b.zip', SourceVerification.crcOk),
    ]);

    // This is where the highlight switches files (section 8).
    expect(split.eligible.map((v) => v.source.filename), ['b.zip']);
    expect(split.confirmed, isTrue);
  });

  test('a discarded source never competes and is counted apart', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.crcDiscarded),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.eligible.map((v) => v.source.filename), ['b.zip']);
    expect(split.discarded.map((v) => v.source.filename), ['a.zip']);
  });

  test('while one is verifying, none is excluded', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.verifying),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    expect(split.verifying, isTrue);
    expect(split.eligible.length, 2);
    expect(split.noCertainty, isFalse);
  });

  test('all impossible becomes the not-sure-about-any state', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.impossible),
      _v('b.zip', SourceVerification.impossible),
    ]);

    expect(split.noCertainty, isTrue);
  });

  test('one impossible and one unverified is not total uncertainty', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.impossible),
      _v('b.zip', SourceVerification.notVerified),
    ]);

    // The second was never asked, so it is still unknown. Opening the list
    // and giving up on the highlight here would be giving up too early.
    expect(split.noCertainty, isFalse);
    expect(split.eligible.length, 2);
  });

  test('all discarded leaves the race empty without becoming uncertainty', () {
    final split = splitByVerification([
      _v('a.zip', SourceVerification.crcDiscarded),
      _v('b.zip', SourceVerification.crcDiscarded),
    ]);

    expect(split.eligible, isEmpty);
    expect(split.discarded.length, 2);
    // Not uncertainty: it is certainty that none fits. The screen shows the banner.
    expect(split.noCertainty, isFalse);
  });
```

Add the missing import at the top of the file:

```dart
import 'package:roms_downloader/models/source_verification_model.dart';
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/source_pick_service_test.dart
```

Expected: `Undefined name 'splitByVerification'` and `Undefined class 'VerifiedSource'`.

- [ ] **Step 3: Implement the pure function**

At the end of `lib/services/source_pick_service.dart`, with the new import at the top:

```dart
import 'package:roms_downloader/models/source_verification_model.dart';
```

```dart
/// A source with its CRC verdict already resolved.
typedef VerifiedSource = ({MatchedSource source, SourceVerification state});

/// How CRC verification reorganizes a game's sources.
typedef VerificationSplit = ({
  /// Who can contest the highlight: only the confirmed ones when any is
  /// confirmed, otherwise everything not discarded.
  List<VerifiedSource> eligible,

  /// Who left the contest because the CRC contradicted the name.
  List<VerifiedSource> discarded,

  /// Some read still in flight.
  bool verifying,

  /// Some source confirmed by CRC.
  bool confirmed,

  /// Sources remain, none confirmed, and all that remain are impossible to
  /// verify.
  bool noCertainty,
});

/// The verification rule, in order. Pure, so the detail screen only draws.
VerificationSplit splitByVerification(List<VerifiedSource> sources) {
  final ok = <VerifiedSource>[];
  final discarded = <VerifiedSource>[];
  final rest = <VerifiedSource>[];
  var verifying = false;
  var impossible = 0;

  for (final item in sources) {
    switch (item.state) {
      case SourceVerification.crcOk:
        ok.add(item);
      case SourceVerification.crcDiscarded:
        discarded.add(item);
      case SourceVerification.verifying:
        verifying = true;
        rest.add(item);
      case SourceVerification.impossible:
        impossible++;
        rest.add(item);
      case SourceVerification.notVerified:
        rest.add(item);
    }
  }

  return (
    eligible: ok.isNotEmpty ? ok : rest,
    discarded: discarded,
    verifying: verifying,
    confirmed: ok.isNotEmpty,
    // `impossible == rest.length`, not `!verifying`: a source nobody asked
    // about has not given up yet.
    noCertainty: ok.isEmpty && rest.isNotEmpty && impossible == rest.length,
  );
}
```

The `switch` without `break` is Dart 3 and passes the analyzer. Verified by running `dart analyze` on a file with exactly this form.

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/source_pick_service_test.dart
```

Expected: `+24`, zero failures. That is 16 from Tasks 6 and 14 plus 8 from this one.

- [ ] **Step 5: Adjust the `_host` in the screen test**

In `test/game_detail_screen_test.dart`, `_host` needs a seam for verification. **Without it the tests hit the real network**, because `sourceVerificationProvider` loads the console pack to build the matcher, and the screen would be stuck on "verifying" forever, breaking the eighteen tests from Tasks 15 and 16.

Replace the entire `_host` with this one:

```dart
Widget _host(
  PackGridEntry entry, {
  void Function(SourcePick)? onDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verification,
}) {
  return ProviderScope(
    overrides: [
      withoutFavoritesDisk,
      packTargetProvider.overrideWithValue(_target),
      preferredRegionsProvider.overrideWithValue(const {'USA'}),
      gameResolverProvider.overrideWithValue(resolver ?? _resolveDefault),
      // Required, not convenience: without it the real provider reads
      // `addonProvider`, which opens `AddonStore` via `path_provider` and throws
      // `MissingPluginException` in a widget test with no platform.
      sourceVerificationProvider.overrideWith((ref, request) {
        final state = verification?.call(request.filename) ?? SourceVerification.notVerified;
        // `verifying` is not a value the provider returns; it is `AsyncLoading`.
        // A never-completing `Completer` holds the screen there without leaving
        // a pending timer at the end of the test.
        if (state == SourceVerification.verifying) {
          return Completer<SourceVerification>().future;
        }
        return state;
      }),
    ],
    child: MaterialApp(
      home: GameDetailScreen(entry: entry, onDownload: onDownload ?? (_) {}),
    ),
  );
}
```

And the new imports, at the top:

```dart
import 'dart:async';

import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
```

The checkbox test from Task 15 builds its own `ProviderScope` by hand and **also** needs the override, otherwise it goes to the network. Add the same line to its `overrides` list:

```dart
        sourceVerificationProvider.overrideWith((ref, request) => SourceVerification.notVerified),
```

- [ ] **Step 6: Write the ten screen tests, which fail**

At the end of `main`, in the same file:

```dart
  testWidgets('while verifying, the button says Download anyway', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [_source('Crystal Vanguard (USA).zip')]),
      verification: (_) => SourceVerification.verifying,
    ));

    expect(find.widgetWithText(FilledButton, 'Download anyway'), findsOneWidget);
    expect(find.text('4.0 MB, listing, verifying'), findsOneWidget);
  });

  testWidgets('CRC ok swaps the reason for the CRC reason', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [_source('Crystal Vanguard (USA).zip')]),
      verification: (_) => SourceVerification.crcOk,
    ));

    expect(find.text('confirmed by CRC, this is exactly the dump'), findsOneWidget);
    expect(find.text('4.0 MB, listing, CRC ok'), findsOneWidget);
    // With certainty given, the button does not hesitate.
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
  });

  testWidgets('the discarded source leaves the highlight and the other rises', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.crcDiscarded
          : SourceVerification.crcOk,
    ));

    // By name, USA would win on preferred region. CRC overruled it and the
    // highlight switched file.
    expect(find.text('Crystal Vanguard (Japan).zip'), findsOneWidget);
    expect(find.text('other source, 1 discarded'), findsOneWidget);
  });

  testWidgets('the discarded row shows up flagged', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.crcDiscarded
          : SourceVerification.crcOk,
    ));

    await tester.tap(find.text('other source, 1 discarded'));
    await tester.pumpAndSettle();

    expect(
      find.text('4.0 MB, listing, HTTP, likely match, discarded by CRC'),
      findsOneWidget,
    );
  });

  testWidgets('with one confirmed, a still-verifying source does not make the button hesitate', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.verifying
          : SourceVerification.crcOk,
    ));

    // The still-running read is of a source that already lost, so it can no
    // longer change the highlight.
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
    expect(find.text('confirmed by CRC, this is exactly the dump'), findsOneWidget);
  });

  testWidgets('none verifiable: the card says it is not sure about any', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (_) => SourceVerification.impossible,
    ));

    expect(find.text('not sure about any of them'), findsOneWidget);
    // Nothing highlighted means no name-based pick reason.
    expect(find.text('chosen by your preferred region (USA)'), findsNothing);
  });

  testWidgets('in that state the list opens and each row has its own Download', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (_) => SourceVerification.impossible,
    ));

    // No tap: the list is born open.
    expect(find.text('Crystal Vanguard (USA).zip'), findsOneWidget);
    expect(find.text('Crystal Vanguard (Japan).zip'), findsOneWidget);
    // Two buttons, no third: there is no highlight card.
    expect(find.widgetWithText(FilledButton, 'Download'), findsNWidgets(2));
  });

  testWidgets('the row Download returns that source, flagged uncertain', (tester) async {
    final downloaded = <SourcePick>[];
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      onDownload: downloaded.add,
      verification: (_) => SourceVerification.impossible,
    ));

    await tester.tap(find.widgetWithText(FilledButton, 'Download').first);
    await tester.pump();

    expect(downloaded.single.filename, 'Crystal Vanguard (USA).zip');
    expect(downloaded.single.uncertain, isTrue);
  });

  testWidgets('all discarded: the band says none passed', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (_) => SourceVerification.crcDiscarded,
    ));

    expect(find.text('no source passed CRC verification'), findsOneWidget);
    expect(find.text('2 other sources, 2 discarded'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Download'), findsNothing);
  });

  testWidgets('the unverifiable source says so on its row', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip'),
        _source('Crystal Vanguard (Japan).zip'),
      ]),
      verification: (filename) => filename.contains('USA')
          ? SourceVerification.crcOk
          : SourceVerification.impossible,
    ));

    await tester.tap(find.text('other source'));
    await tester.pumpAndSettle();

    expect(
      find.text('4.0 MB, listing, HTTP, likely match, cannot verify'),
      findsOneWidget,
    );
  });
```

- [ ] **Step 7: Run and watch it fail**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: `+18 -10`. The eighteen tests from Tasks 15 and 16 keep passing, and that is half the value of this round: if any of them fail now, the culprit is `_host`, not the screen.

- [ ] **Step 8: Rewrite the screen**

`lib/screens/game_detail_screen.dart` becomes this file in full:

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/game_match_model.dart';
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/models/metadata_pack_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/models/source_verification_model.dart';
import 'package:roms_downloader/providers/catalog_provider.dart';
import 'package:roms_downloader/providers/favorites_provider.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/providers/source_verification_provider.dart';
import 'package:roms_downloader/services/source_pick_service.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// The source type, which in this slice is only one. A constant rather than a
/// loose literal for the day it becomes a field.
const _kSourceKind = 'HTTP';

/// One game, its sources, the reason for the pick and what CRC verification said
/// about each. A route, not a bottom sheet or an inline expansion.
class GameDetailScreen extends ConsumerWidget {
  final PackGridEntry entry;

  /// What to do when the user presses Download. The screen does not know the
  /// queue, for the same reason `PackGrid` does not know `Navigator`:
  /// `HomeScreen` wires the two together.
  final void Function(SourcePick pick) onDownload;

  const GameDetailScreen({super.key, required this.entry, required this.onDownload});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final game = entry.game;
    final key = entry.selectionKey;
    final favorite = ref.watch(favoritesProvider).isFavorite(key);
    final isSelected = ref.watch(catalogProvider.select((s) => s.selectedGames)).contains(key);
    final resolver = ref.watch(gameResolverProvider);

    // The verdicts are resolved here, once, and passed down as data. The child
    // widgets never see `ref`. The per-source `watch` is cheap because the
    // Riverpod family caches by (source, file).
    final verified = <VerifiedSource>[
      for (final source in entry.sources) (source: source, state: _stateOf(ref, game.id, source)),
    ];
    final split = splitByVerification(verified);

    // The same batch rule, with a single entry, over what survived
    // verification. One rule, two places.
    final plan = planFromEntries(
      [PackGridEntry(game: game, sources: [for (final v in split.eligible) v.source])],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: resolver,
    );

    final choice = split.noCertainty ? null : plan.picks.firstOrNull;
    final winner = _winner(split.eligible, choice);
    final others = [
      for (final v in verified)
        if (!identical(v.source, winner?.source)) v,
    ];

    // The only string on this screen that does not come from `PickFailure`, and
    // it has to be: the batch does not verify CRC, so the batch rule does not
    // know this state. Do not "fix" it by moving the string to the service.
    final reason = split.eligible.isEmpty && split.discarded.isNotEmpty
        ? 'no source passed CRC verification'
        : (split.noCertainty ? null : plan.failures.firstOrNull?.reason);

    void downloadSource(VerifiedSource item) {
      final game_ = resolver(item.source);
      if (game_ == null) return;
      onDownload(SourcePick(
        gameId: key,
        title: game.title,
        filename: item.source.filename,
        size: item.source.size,
        sourceId: item.source.sourceId,
        reason: 'chosen by you, no verification possible',
        uncertain: true,
        game: game_,
      ));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(game.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: favorite ? 'Remove from favorites' : 'Add to favorites',
            icon: Icon(
              favorite ? Icons.favorite : Icons.favorite_border,
              color: favorite ? Colors.red : null,
            ),
            onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(key),
          ),
          Checkbox(
            value: isSelected,
            onChanged: (_) => ref.read(catalogProvider.notifier).toggleGameSelection(key),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Top(game: game, system: ref.watch(packTargetProvider)?.consoleName ?? ''),
          if ((game.synopsis ?? '').isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(game.synopsis!, style: const TextStyle(fontSize: 13, height: 1.4)),
          ],
          if (choice != null && winner != null) ...[
            const SizedBox(height: 16),
            _Highlight(
              pick: choice,
              verification: winner.state,
              crcConfirmed: split.confirmed,
              // Only hesitate while hesitating can still change something.
              hesitating: split.verifying && !split.confirmed,
              onDownload: () => onDownload(choice),
            ),
          ] else if (split.noCertainty) ...[
            const SizedBox(height: 16),
            const _NoCertainty(),
          ] else if (reason != null) ...[
            const SizedBox(height: 16),
            _NoSource(reason: reason),
          ],
          if (others.isNotEmpty) ...[
            const SizedBox(height: 8),
            _OtherSources(
              sources: others,
              discarded: split.discarded.length,
              startsOpen: split.noCertainty,
              onDownload: split.noCertainty ? downloadSource : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// The verdict for a source. A `checksum`-tier match was already born from a CRC
/// checked against the pack, so it never passes through `verifying`.
SourceVerification _stateOf(WidgetRef ref, String gameId, MatchedSource source) {
  if (source.confidence == MatchConfidence.confirmed) return SourceVerification.crcOk;
  return verificationOf(ref.watch(sourceVerificationProvider((
    sourceId: source.sourceId,
    filename: source.filename,
    url: source.url,
    gameId: gameId,
  ))));
}

/// Which object in the eligible list became the pick. Compares the three fields
/// and returns the instance, because the caller removes the winner from the
/// list by identity, and two sources can serve files of the same name.
VerifiedSource? _winner(List<VerifiedSource> eligible, SourcePick? pick) {
  if (pick == null) return null;
  for (final item in eligible) {
    if (item.source.filename == pick.filename &&
        item.source.size == pick.size &&
        item.source.sourceId == pick.sourceId) {
      return item;
    }
  }
  return null;
}

/// Null when there is nothing to say, and then the line matches the plain one.
String? _verificationLabel(SourceVerification state) => switch (state) {
      SourceVerification.notVerified => null,
      SourceVerification.verifying => 'verifying',
      SourceVerification.crcOk => 'CRC ok',
      SourceVerification.crcDiscarded => 'discarded by CRC',
      SourceVerification.impossible => 'cannot verify',
    };

String _otherLabel(int count, int discarded) {
  final base = count == 1 ? 'other source' : '$count other sources';
  if (discarded == 0) return base;
  // The discarded ones are inside [count]: they moved down into the list,
  // they did not vanish.
  return discarded == 1 ? '$base, 1 discarded' : '$base, $discarded discarded';
}

class _Top extends StatelessWidget {
  final PackGame game;
  final String system;

  const _Top({required this.game, required this.system});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Only what exists joins the line, else a game with no year or publisher
    // (most homebrews) leaves a dangling comma.
    final details = [
      system,
      if (game.year != null) '${game.year}',
      if ((game.publisher ?? '').isNotEmpty) game.publisher!,
      if ((game.genre ?? '').isNotEmpty) game.genre!,
    ].where((part) => part.isNotEmpty).join(', ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: AspectRatio(
            aspectRatio: 0.75,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: _cover(context),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(game.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(details, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cover(BuildContext context) {
    final url = game.cover;
    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(Icons.videogame_asset_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (context, _, __) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorListener: (_) {},
    );
  }
}

/// The highlight card for the chosen version. The reason line is mandatory.
class _Highlight extends StatelessWidget {
  final SourcePick pick;
  final SourceVerification verification;
  final bool crcConfirmed;
  final bool hesitating;
  final VoidCallback onDownload;

  const _Highlight({
    required this.pick,
    required this.verification,
    required this.crcConfirmed,
    required this.hesitating,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _verificationLabel(verification);
    final reason = crcConfirmed
        ? 'confirmed by CRC, this is exactly the dump'
        : pick.reason;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  pick.filename,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _kSourceKind,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${formatBytes(pick.size)}, ${pick.sourceId}${badge == null ? '' : ', $badge'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          Text(reason, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onDownload,
              child: Text(hesitating ? 'Download anyway' : 'Download'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner that replaces the card when there is nothing to download. The
/// text comes from `PickFailure.reason` in most cases, i.e. the same rule the
/// batch sheet uses, with the single exception noted in the screen's `build`.
class _NoSource extends StatelessWidget {
  final String reason;

  const _NoSource({required this.reason});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(reason, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

/// The card for the "verification impossible" state. It never fakes certainty.
class _NoCertainty extends StatelessWidget {
  const _NoCertainty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'not sure about any of them',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'None of the sources let the CRC be read. Pick one below.',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The list of other sources, with the discarded counter.
class _OtherSources extends StatelessWidget {
  final List<VerifiedSource> sources;
  final int discarded;
  final bool startsOpen;

  /// Null most of the time: the per-row button is only for the "verification
  /// impossible" state.
  final void Function(VerifiedSource item)? onDownload;

  const _OtherSources({
    required this.sources,
    required this.discarded,
    required this.startsOpen,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // `ExpansionTile` draws a divider above and below once it opens, which
      // inside a `ListView` of cards becomes two stray lines mid-screen.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: startsOpen,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Text(
          _otherLabel(sources.length, discarded),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final item in sources)
            _SourceRow(
              item: item,
              onDownload: onDownload == null ? null : () => onDownload!(item),
            ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final VerifiedSource item;
  final VoidCallback? onDownload;

  const _SourceRow({required this.item, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badge = _verificationLabel(item.state);
    final download = onDownload;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.source.filename, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            // The five pieces, plus the verification verdict when there is one.
            '${formatBytes(item.source.size)}, ${item.source.sourceId}, '
            '$_kSourceKind, ${_confidenceLabel(item.source.confidence)}'
            '${badge == null ? '' : ', $badge'}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (download != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: download, child: const Text('Download')),
            ),
          ],
        ],
      ),
    );
  }
}

/// The match confidence, which is not the CRC verification. Two axes that never
/// mix; the CRC verdict joins the same line, after this, as a separate piece.
String _confidenceLabel(MatchConfidence confidence) => switch (confidence) {
      MatchConfidence.confirmed => 'confirmed match',
      MatchConfidence.likely => 'likely match',
      MatchConfidence.guess => 'guessed match',
    };
```

The `_otherSources` helper from Task 16 is gone: the identity filter in `build`, over the already-verified list, is now the one that removes the winner. The behavior is the same, including removing only one copy when two sources share the same name. The Task 16 test that proves this keeps working without change.

- [ ] **Step 9: Run and watch it pass**

```bash
flutter test test/game_detail_screen_test.dart test/source_pick_service_test.dart
```

Expected: `+52`, zero failures. That is 28 from the screen and 24 from the service.

Three likely stumbles:

If the eighteen tests from Tasks 15 and 16 start failing with timeout or "pending timer", `_host` is not overriding `sourceVerificationProvider` and the screen is trying to load the real pack.

If `the discarded source leaves the highlight and the other rises` keeps showing USA, check that `planFromEntries` is receiving `split.eligible` and not `entry.sources`.

If `the row Download returns that source, flagged uncertain` picks the wrong button, check the order: `others` preserves the order of `entry.sources`, so `.first` is USA.

- [ ] **Step 10: Run the full suite**

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Expected: `+326 -1`, with the usual failure, `test/rar_decompress_screen_test.dart: renders with extract disabled until a file and folder are picked`. Closes Group 5.

- [ ] **Step 11: Commit**

```bash
# test agent
git add test/source_pick_service_test.dart test/game_detail_screen_test.dart
git commit -m "test(crc): destaque, descarte e incerteza total na tela de detalhe"

# production agent
git add lib/services/source_pick_service.dart lib/screens/game_detail_screen.dart
git commit -m "feat(crc): destaque, descarte e incerteza total na tela de detalhe"
```

---

# Group 6: the full app

Up to here the slice is a stack of tested pieces that nobody wires together. The pack grid exists and is never drawn, the detail screen exists and nothing pushes its route, and the batch sheet only knows how to sum SOURCE MODE files. This group wires the cables and then proves that wiring the cables did not break the app as it is today.

Three code tasks and one sweep. The three code tasks touch `home_screen.dart`, which is the only file in this slice that has no widget test (the test note in Task 3 explains why), so all three push as much logic as possible out of it and into testable pure functions. That is why Task 19 is born with a two-assertion test instead of none, why Task 20 starts by splitting one provider into two, and why Task 21 tests the selection bar in the detail screen instead of the callback that `home_screen.dart` passes to it. Task 22 closes the slice with the regression sweep.

---

### Task 19: mode routing and the funnel label

**Files:**
- Create: `test/header_filter_label_test.dart`
- Modify: `lib/widgets/header/header.dart`
- Modify: `lib/screens/home_screen.dart:90-94`

Two wirings and one cleanup:

1. `HomeScreen` now chooses between `PackGrid` and today's grid based on `gridModeProvider`.
2. `PackGrid.onOpenGame` now pushes the `GameDetailScreen` route, and `GameDetailScreen.onDownload` now calls `TaskQueueService.startDownloads`. Both callbacks have existed since Task 12 and Task 15 exactly so they could meet **here**, and nowhere else.
3. The funnel button in the header gains a per-mode label, which is the "Fifth locked decision".

**What this Task deliberately does not do: touch `FilterModal`.** The "File structure" table lists **three** existing production files modified in this slice, and `lib/widgets/header/filter_modal.dart` is not one of them. In PACK MODE the revision and dump-quality chips keep appearing in the filter sheet and keep having no effect on the grid, because the pack grid has no version to filter. This is a known and accepted gap, and the new button label exists to not lie about it: instead of promising "Filters", it promises only what survives.

**Why the SOURCE MODE label does not change by a single character.** `'Filters'` is today's string. Task 22 requires that SOURCE MODE be the app as it is today, and "the tooltip text changed" is a regression like any other. The new label only appears when there is a pack.

**Test note.** `HomeScreen` and `Header` cannot be mounted in widget tests, for the reason written in the test note for Task 3: both pull providers that do disk and network IO in their constructors. What can be tested without mounting anything is the label decision, because it becomes a top-level function in `header.dart`. That is little and it is honest: two assertions that lock the "Fifth locked decision" against someone who decides to "simplify" by removing the button. The routing itself is proven by a clean `flutter analyze`, a green full suite, and the manual walkthrough in Step 6.

- [ ] **Step 1: Write the failing test**

Create `test/header_filter_label_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/widgets/header/header.dart';

void main() {
  test('in source mode the label is today\'s, without changing a character', () {
    // SOURCE MODE is the app as it is today. Changing this text is a
    // regression, and Task 22 treats SOURCE MODE regression as a slice failure.
    expect(filterButtonLabel(GridMode.source), 'Filters');
  });

  test('in pack mode the label says only what the funnel still does', () {
    // In PACK MODE the grid does not go through FilteringService, so revision
    // and dump quality filter nothing. Region survives because it feeds the
    // version choice in `planFromEntries`. See "Fifth locked decision".
    expect(filterButtonLabel(GridMode.pack), 'Region preference');
  });
}
```

This is `test`, not `testWidgets`, on purpose: nothing here mounts a widget, so there is no binding to initialize. Importing `header.dart` in a pure test is safe because top-level `final` in Dart is lazy, meaning no provider is constructed just because of the import.

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/header_filter_label_test.dart
```

Expected: `Undefined name 'filterButtonLabel'`.

- [ ] **Step 3: Write the function and wire it to the button**

In `lib/widgets/header/header.dart`, add the import:

```dart
import 'package:roms_downloader/providers/pack_grid_provider.dart';
```

And write the function **outside the class**, right after the imports and before `class Header`:

```dart
/// The funnel button label, which depends on the grid mode.
///
/// "Fifth locked decision": in PACK MODE the revision and dump-quality chips
/// do not filter the grid, because the pack grid has no version to filter.
/// What survives from that sheet is the region, which feeds the version
/// choice in `planFromEntries`. The label says that instead of promising a
/// filter that does not happen.
///
/// The button does **not** disappear in PACK MODE. Removing it would take
/// away the only path to the region preference, which is exactly what still
/// has an effect.
String filterButtonLabel(GridMode mode) =>
    mode == GridMode.pack ? 'Region preference' : 'Filters';
```

Now wire it. In `_HeaderState.build`, alongside the other reads at the top of the method (currently lines 36 to 40):

```dart
    final gridMode = ref.watch(gridModeProvider);
```

`_buildActionWidgets` is called in **two** places, the `isMobile` branch (currently line 109) and the `Row` branch (currently line 152). In both, replace the argument `canDownload: canDownload,` with:

```dart
                          gridMode: gridMode,
```

And in the signature of `_buildActionWidgets`, replace `required bool canDownload,` with `required GridMode gridMode,`. Inside it, the first item in the list becomes:

```dart
      _buildActionButton(
        context: context,
        icon: catalogState.filter.isActive ? Icons.filter_alt : Icons.filter_alt_outlined,
        isActive: catalogState.filter.isActive,
        onPressed: () => FilterModal.show(context),
        tooltip: filterButtonLabel(gridMode),
      ),
```

- [ ] **Step 4: Clean up what Task 3 left behind**

Task 3 removed the "Download Selected" button, but `canDownload` survived, because an unused method parameter is **not** flagged by `flutter analyze` under this repository's rules. Step 3 just removed its last use. Delete now, in this order:

1. In `build`, the line `final canDownload = !appState.loading && downloadNotifier.hasDownloadableSelectedGames();` (currently line 46).
2. In `build`, the line `final downloadNotifier = ref.read(downloadProvider.notifier);` (currently line 36), **replaced by the line below, not deleted**. Read the "Line 36 is not dead code" paragraph before touching it.
3. The import `package:roms_downloader/providers/download_provider.dart` (currently line 7): **keep it**, because the new line still uses it.

> **Check the line content before deleting, not the number.** These three numbers were measured after Task 3 closed (commit `b31f052`), which shortened `header.dart` by 14 lines. The first version of this plan said 47 and 37, measured before Task 3, and was wrong on two of the three. If the file changes again before you get here, `grep -n "canDownload\|downloadNotifier\|download_provider" lib/widgets/header/header.dart` is the source of truth, and this paragraph is just a hint.

**Line 36 is not dead code, it is the app startup.**

It looks like a dead read after item 1 is gone, and the first version of this plan said to delete it. That was wrong, and a QA review caught it. `ref.read(downloadProvider.notifier)` is the **only eager construction of `downloadProvider` in the entire app**, and the `DownloadNotifier` constructor does startup work: it subscribes to the `background_downloader` `updates` stream, calls `resumeFromBackground()`, `_syncWithBackgroundTasks()`, and `_cleanupInterruptedNsz()` (`download_provider.dart:37-58`).

Verified with `grep -rn "downloadProvider" lib/`, which gives six occurrences besides the declaration. Five are `ref.read` inside methods, in `task_queue_service.dart:69,83,88,118`, and one `ref.watch` in `sport_patcher_wizard_screen.dart:743`. None of them run at startup: the first five only run after the user has queued a download, and the sixth only if they open the sport patcher wizard. Too late to resume a download left half-done in the previous process, and too late for the stream subscription to exist when the first task is enqueued.

So item 2 is a **replacement**, not a deletion. Put in its place:

```dart
    // Not dead code: it is the only eager construction of `downloadProvider`
    // in the app. The `DownloadNotifier` constructor subscribes to the
    // `background_downloader` updates stream, calls `resumeFromBackground()`,
    // `_syncWithBackgroundTasks()`, and `_cleanupInterruptedNsz()`
    // (`download_provider.dart:37-58`). The other six readers are `read`
    // inside a method or a secondary screen, and none run at startup.
    // The right fix is to move startup out of the header, but that touches
    // `download_provider.dart`, which slice 3 does not touch (see the
    // untouched-files table that Task 22 checks). Stays here, now with the
    // reason written down.
    ref.read(downloadProvider.notifier);
```

It is `read` and not `watch` on purpose: `watch` would rebuild the header on every progress event, which arrives many times per second during a download. `downloadProvider` is not `autoDispose`, so a single read on first construction is enough for it to live for the rest of the session.

Then run:

```bash
flutter analyze lib/widgets/header/header.dart
```

Expected: `No issues found`. If `unused_import` appears for something else, delete only what it points to and nothing more. If `undefined_identifier` appears for `downloadNotifier` or `canDownload`, some other button was still using them: undo the deletion of that item and continue. **Run first; do not guess.**

- [ ] **Step 5: Run the test and watch it pass**

```bash
flutter test test/header_filter_label_test.dart
```

Expected: `+2`, zero failures.

- [ ] **Step 6: Wire the routing in `HomeScreen`**

In `lib/screens/home_screen.dart`, add the missing imports:

```dart
import 'package:roms_downloader/models/grid_entry_model.dart';
import 'package:roms_downloader/providers/pack_grid_provider.dart';
import 'package:roms_downloader/screens/game_detail_screen.dart';
import 'package:roms_downloader/widgets/game_grid/pack_grid.dart';
```

Inside `_HomeScreenState`, alongside the `_confirmBatch` that Task 6 wrote, add the two methods:

```dart
  /// Pushes the detail screen.
  ///
  /// The grid does not navigate (Task 12) and the screen does not know the
  /// queue (Task 15). The two loose cables meet here, and only here.
  void _openDetail(PackGridEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GameDetailScreen(entry: entry, onDownload: _downloadOne)),
    );
  }

  /// A single pick from the detail screen goes straight to the queue.
  ///
  /// No confirmation sheet, and that is a decision, not an oversight: the
  /// detail screen **is** the confirmation. It already shows the chosen file,
  /// the size, the full reason, and the CRC verdict. Opening a single-item
  /// batch sheet on top of that would be asking the same question twice. The
  /// sheet exists for the batch, where the user saw no pick before pressing
  /// Download.
  Future<void> _downloadOne(SourcePick pick) async {
    await TaskQueueService.startDownloads(
      ref,
      context,
      [pick.game],
      ref.read(appStateProvider).selectedConsole?.id,
    );
  }
```

`SourcePick` and `TaskQueueService` are already imported since Task 6.

Now replace the `switch (appState.viewMode)` in the body, currently lines 90 to 94, with an outer `switch` that has today's switch nested inside:

```dart
                    : switch (ref.watch(gridModeProvider)) {
                        GridMode.pack => PackGrid(onOpenGame: _openDetail),
                        GridMode.source => switch (appState.viewMode) {
                            ViewMode.grid => GameGrid(),
                            ViewMode.coverflow => const GameCoverFlow(),
                            ViewMode.list => GameList(),
                          },
                      },
```

Three things about this block:

1. **The inner `switch` stays intact, word for word.** It is the app as it is today and it stays that way. Do not use this visit to "improve" the grid, the list, or the coverflow.
2. **The view mode does not apply in PACK MODE.** `PackGrid` is the only form of the pack grid in this slice: list and coverflow are SOURCE MODE things and UI spec section 12 explicitly puts them out of scope. The view-mode button stays in the header and keeps working; in PACK MODE it changes a state that nobody reads, and it becomes visible again as soon as the console reverts to one without a pack. It is ugly and it is cheap; hiding the button would cost one more per-mode label and one more test, for a gain nobody asked for.
3. **`ref.watch(gridModeProvider)` stays in `build`, not in `initState`.** The mode changes when the user switches console, and it is a synchronous `Provider` derived from `metadataPackProvider`, so it re-evaluates on its own when the pack arrives from the network. Storing it in a `State` field would freeze the grid in SOURCE MODE on the first load.

- [ ] **Step 7: Check manually, because no test covers this**

This is the first moment the full slice appears on screen, so it is worth more than usual:

```bash
flutter run -d linux
```

1. Pick a console **with** a pack (SNES). The grid must switch to the pack grid: one tile per game, pack cover art, and the tile count matches the number of games in the pack, not the number of files in the listing.
2. Tap a tile. The detail screen opens as a route, with a back button.
3. Press Download on the detail screen. The download must appear in the footer with the selected file name, and the screen stays open.
4. Go back and open the filter sheet. The funnel tooltip is "Region preference" and the sheet opens normally.
5. Switch to a console **without** a pack (any that has no DAT). The grid must go back to exactly today's grid, and the funnel tooltip goes back to "Filters".
6. On that console without a pack, switch the view to list and to coverflow. Both keep working.

If step 1 shows today's grid on a console that has a pack, the culprit is almost always `metadataPackProvider` still `loading` in the first frame; wait for the pack to finish loading before concluding it broke.

- [ ] **Step 8: Prove nothing broke**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Expected: 22 findings and zero errors in analyze; `+328 -1` in the suite, being the 326 from Task 18 plus the 2 from this one.

- [ ] **Step 9: Commit**

```bash
# test agent
git add test/header_filter_label_test.dart
git commit -m "test(grade): rotulo do funil por modo de grade"

# production agent
git add lib/widgets/header/header.dart lib/screens/home_screen.dart
git commit -m "feat(grade): roteamento de modo, rota de detalhe e rotulo do funil por modo"
```

---

### Task 20: PACK MODE feeds the batch sheet

**Files:**
- Modify: `lib/models/grid_entry_model.dart`
- Modify: `lib/services/pack_grid_filter.dart`
- Modify: `test/pack_grid_filter_test.dart`
- Modify: `lib/providers/pack_grid_provider.dart`
- Modify: `test/pack_grid_provider_test.dart`
- Modify: `lib/screens/home_screen.dart`

Task 6 made the purple bar open the confirmation sheet with `planFromGames`, which only knows how to sum SOURCE MODE files. Task 14 wrote `planFromEntries`, the real rule, and until now only the detail screen uses it, with a single entry. This Task routes the PACK MODE batch through it, and it is the last piece of code in the slice.

Three real problems are hidden in a wiring that looks like two lines. Read all three before writing anything.

**Problem 1: the search cannot shrink the batch.** Today `packGridEntriesProvider` already comes out filtered by the search box text. If the batch reads from there, then checking three games, typing anything in the header, and pressing Download enqueues only the ones still visible on screen. The selection is not the screen. The fix is to split the provider in two: one with everything, which the batch reads, and one filtered, which the grid draws.

**Problem 2: the keys from both modes share the same `Set`.** The "Fourth locked decision" guarantees they do not collide, and they truly do not, but they do share the set, and there is a real window where this happens on the same console: the catalog loads from disk in milliseconds and the pack arrives from the network seconds later. In that interval the grid is SOURCE MODE, the user checks three files, the pack arrives and the grid becomes PACK MODE with those three keys still in the selection. Without handling, the purple bar says "3 selected", the user presses Download, and **nothing happens, silently**, because none of the keys match a pack entry. The fix is for the bar to count only what the current mode knows how to enqueue.

Switching console does not have this problem: `CatalogNotifier.loadCatalog` already resets `selectedGames` (`catalog_provider.dart:53`, and again at `:379`).

**Problem 3: one selection, two paths, one sheet.** What changes between modes is only how the `BatchPlan` is born. The sheet, the `showModalBottomSheet`, the `withoutPick`, the enqueuing, and the selection clearing are the same and must stay the same: that is what Task 6 bought by writing `planFromGames` instead of an inline `map`.

- [ ] **Step 1: Write the failing pure-function tests**

At the end of `main` in `test/pack_grid_filter_test.dart`, six new tests:

```dart
  test('selection returns entries in list order, not in the order they were checked', () {
    final entries = [_e('Crystal Vanguard'), _e('Emberfall'), _e('Super Vectron')];

    final out = entriesForSelection(entries, {entries[2].selectionKey, entries[0].selectionKey});

    expect(out.map((e) => e.game.title), ['Crystal Vanguard', 'Super Vectron']);
  });

  test('a key no longer in the pack is ignored, without throwing', () {
    // Happens when the pack is republished with a different slug while the
    // user's selection still points to the old one.
    expect(entriesForSelection([_e('Crystal Vanguard')], {'pack:snes/game-that-vanished'}), isEmpty);
  });

  test('a source-mode key brings back no pack entry', () {
    expect(entriesForSelection([_e('Crystal Vanguard')], {'snes/Crystal Vanguard (USA).zip'}), isEmpty);
  });

  test('in pack mode only pack-prefixed keys count', () {
    final out = selectionKeysFor(
      {'pack:snes/crystal-vanguard', 'snes/Crystal Vanguard (USA).zip'},
      pack: true,
    );

    expect(out, {'pack:snes/crystal-vanguard'});
  });

  test('in source mode only unprefixed keys count', () {
    final out = selectionKeysFor(
      {'pack:snes/crystal-vanguard', 'snes/Crystal Vanguard (USA).zip'},
      pack: false,
    );

    expect(out, {'snes/Crystal Vanguard (USA).zip'});
  });

  test('an empty selection returns an empty set in both modes', () {
    expect(selectionKeysFor(const {}, pack: true), isEmpty);
    expect(selectionKeysFor(const {}, pack: false), isEmpty);
  });
```

The `_e` helper from Task 9 works unchanged: it builds the `PackGame` with id `'snes/${title.toLowerCase()}'`, which is why the tests above get the key from `entries[i].selectionKey` instead of writing it by hand. Writing `'pack:snes/crystal vanguard'` in the test would work and would be worse: it would end up testing the helper's format.

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/pack_grid_filter_test.dart
```

Expected: `Undefined name 'entriesForSelection'` and `Undefined name 'selectionKeysFor'`.

- [ ] **Step 3: Write the two functions**

First, in `lib/models/grid_entry_model.dart`, the prefix becomes a constant, because from now on it is read in two files and a literal duplicated across two files is a bug waiting to happen. Add before the class:

```dart
/// The PACK MODE selection key prefix.
///
/// See "Fourth locked decision": the `:` cannot come out of
/// `CatalogService._nameToId`, so a key with this prefix never collides
/// with a `Game.gameId`.
const kPackSelectionPrefix = 'pack:';
```

And update the getter to use it:

```dart
  String get selectionKey => '$kPackSelectionPrefix${game.id}';
```

The Task 7 test (`expect(entry.selectionKey, 'pack:snes/crystal-vanguard')`) keeps passing, and it is good that it does: it now proves that the constant is worth what the literal was worth.

Now, at the end of `lib/services/pack_grid_filter.dart`:

```dart
/// The entries the user selected, in the order [entries] arrived. Unknown keys
/// are ignored silently.
List<PackGridEntry> entriesForSelection(List<PackGridEntry> entries, Set<String> keys) =>
    [for (final entry in entries) if (keys.contains(entry.selectionKey)) entry];

/// The selection keys that belong to the current mode.
///
/// The selection is one `Set<String>` shared by both modes, and both can
/// briefly coexist in the same console. Does not clear the other mode's
/// selection: if the pack fails and the mode falls back to SOURCE, the user's
/// marks are still there.
Set<String> selectionKeysFor(Set<String> keys, {required bool pack}) =>
    {for (final key in keys) if (key.startsWith(kPackSelectionPrefix) == pack) key};
```

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/pack_grid_filter_test.dart
```

Expected: `+13`, zero failures. That is 7 from Task 9 plus 6 from this one.

- [ ] **Step 5: Write the failing provider tests**

At the end of `main` in `test/pack_grid_provider_test.dart`:

```dart
  test('the header search does not shrink the list the batch reads', () async {
    // The bug this test locks: selecting three games, typing in the header,
    // and pressing Download enqueuing only the ones still on screen.
    final container = _container(games: [_game('Crystal Vanguard (USA).zip')], search: 'vectron');
    await _ready(container);

    expect(container.read(packGridEntriesProvider).map((e) => e.game.id), ['snes/super-vectron']);
    expect(
      container.read(allPackEntriesProvider).map((e) => e.game.id),
      ['snes/crystal-vanguard', 'snes/super-vectron'],
    );
  });

  test('the batch list comes out sorted by title, not in pack order', () async {
    final container = _container(
      pack: Future.value(MetadataPack(
        pack: 'snes',
        system: 'Super Nintendo',
        built: '2026-01-01',
        games: [
          _pg('snes/super-vectron', 'Super Vectron (USA)'),
          _pg('snes/crystal-vanguard', 'Crystal Vanguard (USA)'),
        ],
      )),
    );
    await _ready(container);

    expect(
      container.read(allPackEntriesProvider).map((e) => e.game.id),
      ['snes/crystal-vanguard', 'snes/super-vectron'],
    );
  });
```

- [ ] **Step 6: Run and watch it fail**

```bash
flutter test test/pack_grid_provider_test.dart
```

Expected: `Undefined name 'allPackEntriesProvider'`.

- [ ] **Step 7: Split the provider in two**

In `lib/providers/pack_grid_provider.dart`, replace the entire `packGridEntriesProvider` with the two below:

```dart
/// Every pack game with matched sources, sorted, without the search applied.
/// The batch reads from here; the grid reads from the filtered provider below.
/// A batch reading the filtered list would lose games selected before typing.
final allPackEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  final target = ref.watch(packTargetProvider);
  if (target == null) return const [];
  final pack = ref.watch(metadataPackProvider(target)).valueOrNull;
  if (pack == null) return const [];

  final index = ref.watch(sourceIndexProvider);
  // Empty query: `filterPackEntries` filters nothing and only sorts, where the
  // grid and the batch must agree on the order.
  return filterPackEntries([
    for (final game in pack.games)
      PackGridEntry(game: game, sources: index?.sourcesFor(game.id) ?? const []),
  ], '');
});

/// What the pack-mode grid draws: the above, with the header search applied.
final packGridEntriesProvider = Provider<List<PackGridEntry>>((ref) {
  return filterPackEntries(
    ref.watch(allPackEntriesProvider),
    ref.watch(gridSearchQueryProvider),
  );
});
```

- [ ] **Step 8: Run and watch it pass**

```bash
flutter test test/pack_grid_provider_test.dart
```

Expected: `+11`, zero failures. That is 7 from Task 10, 2 from Task 15, and 2 from this one. The seven old ones pass without a single changed line, and that is the point: `packGridEntriesProvider` keeps its name and semantics; it only changed what it reads from.

- [ ] **Step 9: Wire the PACK MODE batch in `HomeScreen`**

In `lib/screens/home_screen.dart`, add the import:

```dart
import 'package:roms_downloader/services/pack_grid_filter.dart';
```

In `build`, right after `final errorMessage = ...`, hoist the mode and filter the selection:

```dart
    final gridMode = ref.watch(gridModeProvider);
    final selected = selectionKeysFor(
      ref.watch(catalogProvider.select((s) => s.selectedGames)),
      pack: gridMode == GridMode.pack,
    );
```

The `select` now delivers the `Set` instead of the `length` that Task 3 wrote. The trigger remains narrow: `CatalogNotifier` builds a new `Set` on every change (`catalog_provider.dart:229-237`) and returns the same object when nothing changes, and Riverpod's `select` compares with `==`, which for `Set` is identity.

Note that the trigger became **wider** than Task 3's, and on purpose: `length` did not distinguish swapping one game for another, and the bar now needs to know which ones, not how many. As before, the entire `HomeScreen` rebuilds, because that is where the `watch` lives. Do not write "only the bar rebuilds" here; the sentence is false and was corrected once already in Task 3.

`SelectionBar` now counts the filtered selection and passes it to the batch:

```dart
          SelectionBar(
            count: selected.length,
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () => _confirmBatch(selected),
          ),
```

And the body `switch` now uses the hoisted variable instead of reading the provider a second time:

```dart
                    : switch (gridMode) {
```

- [ ] **Step 10: Make the plan born from the mode**

Still in `lib/screens/home_screen.dart`, replace the beginning of the `_confirmBatch` that Task 6 wrote, and add the deciding method:

```dart
  /// Opens the section-6 sheet and only enqueues what comes back from it.
  Future<void> _confirmBatch(Set<String> selected) async {
    var plan = _selectionPlan(selected);
    // A plan of only failures is **not** empty: the sheet opens to say why
    // nothing will be downloaded. See `BatchPlan.isEmpty` in Task 4.
    if (plan.isEmpty) return;

    final confirmed = await showModalBottomSheet<BatchPlan>(
```

The rest of the method, from `showModalBottomSheet` to `clearSelection()`, stays **exactly** as Task 6 left it. The only line removed is the old `if (games.isEmpty) return;`, together with the `final games = ...` that fed it, because `build` now computes the selection.

And the new method, just above it:

```dart
  /// The batch plan, by current mode.
  ///
  /// Both branches return the same type and flow into the same sheet, the
  /// same enqueuing, and the same selection clearing. If you find yourself
  /// writing a second `showModalBottomSheet` here, you stopped in the wrong
  /// place: what varies between modes is only how the `BatchPlan` is born.
  BatchPlan _selectionPlan(Set<String> selected) {
    if (ref.read(gridModeProvider) == GridMode.pack) {
      // The section-6 rule, the same one that picks the detail screen's
      // highlight. `allPackEntriesProvider` not `packGridEntriesProvider`:
      // see Problem 1 at the top of this Task.
      return planFromEntries(
        entriesForSelection(ref.read(allPackEntriesProvider), selected),
        preferredRegions: ref.read(preferredRegionsProvider),
        resolveGame: ref.read(gameResolverProvider),
      );
    }
    // SOURCE MODE: each key is already a file, nothing to choose.
    final games = ref.read(catalogProvider).games;
    return planFromGames(games.where((game) => selected.contains(game.gameId)).toList());
  }
```

A note on the `clearSelection()` at the end of `_confirmBatch`: it clears the **entire** selection, including the keys from the other mode, which this Task just taught the app to ignore. That is correct. The user just sent a batch to the queue; leaving on the marks they made before the pack arrived would be holding on to an intention they no longer have.

- [ ] **Step 11: Check manually, because no test covers the wiring**

```bash
flutter run -d linux
```

1. On a console with a pack, long-press a tile to select it, then select two more. The purple bar says "3 selected".
2. Type in the search field until only one tile remains on screen. The bar still says "3 selected".
3. Press Download. The sheet opens with all **three**, each with its filename and reason.
4. Remove one from the sheet and confirm. Two enter the queue and the bar disappears.
5. Select a game that the grid shows without a source. The sheet must open with it under "Not going to the queue", with the reason, and with the Download button disabled.
6. On a console **without** a pack, repeat steps 1, 3, and 4. It must work exactly as before this slice.
7. Select a game that **is already downloading** and press Download. It will enter the queue a second time. **This is expected in this slice, it is not a regression you introduced, and do not fix it here.** See the known limitation below.

**Known limitation, inherited and deliberately not fixed here: the batch enqueues duplicates.** `TaskQueueService.startDownloads` (`task_queue_service.dart:51`) enqueues without filtering by task state, and `TaskQueueNotifier.enqueue` (`task_queue_provider.dart:21`) appends without searching for a duplicate. The one that filters is the other `startDownloads`, the notifier's one (`download_provider.dart:260`), and the batch path never went through it.

This is **pre-slice-3**, verified not inferred: in `f9da109` `header.dart:191` was already calling the same static method without a filter, and the button gate was `hasDownloadableSelectedGames()`, which is `selectedGames.any(isTaskDownloadable)` (`download_provider.dart:337-340` in that commit). **`any`, not `every`**: one new game in the selection was enough to enable the button and send the already-downloading ones along. What slice 3 changes is only the degenerate case where *none* of the selected items are downloadable, which previously kept the button dark and now opens the sheet.

It is not fixed in this slice for two reasons. The right filter lives in `download_provider.dart` and `task_queue_service.dart`, both in the untouched-files table that Task 22 checks. And the alternative of making the `gameResolverProvider` from Task 15 return `null` for the already-enqueued game would give the user the wrong reason, "the source left the listing before the queue started", which is a lie. The honest fix is slice 4, which rewrites the download and accounts layer anyway: either `enqueue` becomes idempotent by `taskId`, or `planFromEntries` gains a set of already-enqueued items and emits a `PickFailure` with its own reason.

- [ ] **Step 12: Prove nothing broke**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Expected: 22 findings and zero errors in analyze; `+336 -1` in the suite, being the 328 from Task 19 plus the 8 from this one.

- [ ] **Step 13: Commit**

```bash
# test agent
git add test/pack_grid_filter_test.dart test/pack_grid_provider_test.dart
git commit -m "test(lote): selecao de MODO PACK sobrevive a busca e alimenta a folha"

# production agent
git add lib/models/grid_entry_model.dart lib/services/pack_grid_filter.dart lib/providers/pack_grid_provider.dart lib/screens/home_screen.dart
git commit -m "feat(lote): selecao de MODO PACK sobrevive a busca e alimenta a folha"
```

---

### Task 21: the selection bar on the detail screen

**Files:**
- Modify: `lib/screens/game_detail_screen.dart`
- Modify: `test/game_detail_screen_test.dart` (three new tests at the end, plus `_host`)
- Modify: `lib/screens/home_screen.dart`

UI spec section 5 ends with a seven-word sentence that is easy to read without seeing: *"The bar exists on both screens, grid and detail, in the same position."*

It is not decoration, and you can see why by looking at what Task 15 already built. The detail screen has a checkbox next to the heart, and section 4 explains it exists so a user who opened a game can select it without going back to the grid. Without the bar, that checkbox is half a feature: the user checks it, **nothing happens on screen**, there is no counter and no button, and they must go back to the grid to find out the selection worked. A checkbox without a bar is a switch without a light.

**The detail screen's bar is not a new bar.** It is the same `SelectionBar` from Task 2, in the same visual position, with the same count and the same destination. The only change is who pays for the `Scaffold`.

**It does not open the sheet on its own**, for the same reason `onDownload` does not enqueue on its own: the detail screen does not know the queue or the sheet. It receives one more callback, `onBatchDownload`, and `HomeScreen` wires that callback to the same `_confirmBatch` from Task 20. One sheet, one enqueuing, two buttons that reach it.

**`HomeScreen` does not pop the route before opening the sheet.** The sheet rises over the detail screen, and that is correct: `showModalBottomSheet` uses the `Navigator` nearest to the `HomeScreen` context, which is the same one showing the detail. Popping first would make the detail screen flicker out in the same frame the sheet rises, and would also leave the user away from the game they were looking at. After confirming, the selection resets, the bar disappears from both screens, and the detail stays where it was.

- [ ] **Step 1: Write the three failing tests**

First, the `_host` from Task 18 needs the new callback. In `test/game_detail_screen_test.dart`, in the `_host` signature, add one parameter:

```dart
Widget _host(
  PackGridEntry entry, {
  void Function(SourcePick)? onDownload,
  VoidCallback? onBatchDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verification,
}) {
```

E no `MaterialApp` do fim dele:

```dart
    child: MaterialApp(
      home: GameDetailScreen(
        entry: entry,
        onDownload: onDownload ?? (_) {},
        onBatchDownload: onBatchDownload ?? () {},
      ),
    ),
```

The `SelectionBar` import at the top of the test file:

```dart
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
```

Now the three tests, at the end of `main`:

```dart
  testWidgets('with no selection the detail screen shows no bar', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [_source('Crystal Vanguard (USA).zip')])));

    // The `SelectionBar` is always mounted and shrinks to zero when the
    // selection is empty, so the test measures height instead of finding it.
    expect(tester.getSize(find.byType(SelectionBar)).height, 0);
  });

  testWidgets('checking the checkbox makes the bar appear with the count', (tester) async {
    await tester.pumpWidget(_host(_entry(sources: [_source('Crystal Vanguard (USA).zip')])));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.getSize(find.byType(SelectionBar)).height, greaterThan(0));
  });

  testWidgets('the bar Download is the batch one, not the highlight one', (tester) async {
    // Both buttons say "Download" and do different things: the card one queues
    // this game, the bar one opens the batch sheet. Swapping them is the bug
    // this test locks.
    final called = <String>[];
    await tester.pumpWidget(_host(
      _entry(sources: [_source('Crystal Vanguard (USA).zip')]),
      onDownload: (_) => called.add('highlight'),
      onBatchDownload: () => called.add('batch'),
    ));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    await tester.tap(find.descendant(
      of: find.byType(SelectionBar),
      matching: find.text('Download'),
    ));
    await tester.pump();

    expect(called, ['batch']);
  });
```

- [ ] **Step 2: Run and watch it fail**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: `No named parameter with the name 'onBatchDownload'`.

- [ ] **Step 3: Put the bar on the screen**

In `lib/screens/game_detail_screen.dart`, add the imports:

```dart
import 'package:roms_downloader/services/pack_grid_filter.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';
```

Add the field, right below `onDownload`:

```dart
  /// What to do when the user presses Download **on the footer bar**, which is
  /// the batch and not this game. A callback for the same reason as [onDownload]:
  /// this screen does not know the queue or the confirmation sheet. `HomeScreen`
  /// wires the two together.
  final VoidCallback onBatchDownload;
```

And in the constructor:

```dart
  const GameDetailScreen({
    super.key,
    required this.entry,
    required this.onDownload,
    required this.onBatchDownload,
  });
```

In `build`, the line that currently computes `isSelected` now stores the full set, because the bar needs the count and the checkbox needs membership:

```dart
    final selected = ref.watch(catalogProvider.select((s) => s.selectedGames));
    final isSelected = selected.contains(key);
```

And the screen's `Scaffold` gains the bar:

```dart
      bottomNavigationBar: SelectionBar(
        // `pack: true` literal, not read from `gridModeProvider`: this screen
        // only exists in PACK MODE, because only `PackGrid` pushes it.
        count: selectionKeysFor(selected, pack: true).length,
        onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
        onDownload: onBatchDownload,
      ),
```

`bottomNavigationBar` and not a `Column` in the body, on purpose: it is what keeps the bar pinned to the bottom without competing with the body scroll, and prevents the keyboard from pushing it off screen.

- [ ] **Step 4: Run and watch it pass**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: `+31`, zero failures. That is the 28 that Tasks 15, 16, and 18 left in this file, plus the 3 from this one.

- [ ] **Step 5: Wire the callback in `HomeScreen`**

In `lib/screens/home_screen.dart`, `_openDetail` gains the third argument:

```dart
  void _openDetail(PackGridEntry entry) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDetailScreen(
        entry: entry,
        onDownload: _downloadOne,
        onBatchDownload: () => _confirmBatch(_modeSelection),
      ),
    ));
  }
```

And add the getter the line above uses, alongside the other private methods:

```dart
  /// The current-mode selection, read at the moment of the tap.
  ///
  /// `build` computes the same thing for the bar count, but the batch reads
  /// here, not from that value, because the sheet can be opened from the detail
  /// screen, which is **on top of** this one. Reading at tap time removes the
  /// question "is that value still current" from the path.
  Set<String> get _modeSelection => selectionKeysFor(
        ref.read(catalogProvider).selectedGames,
        pack: ref.read(gridModeProvider) == GridMode.pack,
      );
```

And `HomeScreen`'s own `SelectionBar` now uses the same getter, so there is not a second path to the batch:

```dart
          SelectionBar(
            count: selected.length,
            onClear: () => ref.read(catalogProvider.notifier).clearSelection(),
            onDownload: () => _confirmBatch(_modeSelection),
          ),
```

The `selected` variable from `build`, created in Task 20, keeps existing and keeps serving **only** for the count.

- [ ] **Step 6: Check manually**

```bash
flutter run -d linux
```

1. On a console with a pack, open a game by tapping the tile. No purple bar.
2. Check the checkbox next to the heart. The purple bar rises in the footer of the detail screen, saying "1 selected".
3. Go back to the grid. The bar is still there, with the same count and in the same position.
4. Open another game, select it, and press Download **on the bar**. The batch sheet rises over the detail screen, with both games.
5. Confirm. Both enter the queue, the bar disappears, and the detail screen stays open.
6. Press Download **on the highlight card**. Only that game enters the queue, with no sheet.

- [ ] **Step 7: Prove nothing broke**

```bash
flutter analyze
flutter test 2>&1 | tr '\r' '\n' | tail -3
```

Expected: 22 findings and zero errors; `+339 -1` in the suite, being the 336 from Task 20 plus the 3 from this one.

- [ ] **Step 8: Commit**

```bash
# test agent
git add test/game_detail_screen_test.dart
git commit -m "test(selecao): barra de selecao na tela de detalhe abre a folha do lote"

# production agent
git add lib/screens/game_detail_screen.dart lib/screens/home_screen.dart
git commit -m "feat(selecao): barra de selecao na tela de detalhe abre a folha do lote"
```

---

### Task 22: regression sweep and acceptance criterion

**Files:** none, if everything is right. This Task does not write code: it checks. If any step fails, the fix is done here and becomes a commit; if nothing fails, it closes the slice with no commit at all.

**This slice makes a double promise.** The easy half to prove is "the pack grid works", and the 155 new tests handle that. The hard half is **"SOURCE MODE continues to be the app as it is today"**, which no new test proves, because a test that passes today and would pass equally with the grid broken proves nothing. That half is proven by diff and by eye, and that is what this Task is.

**The baseline commit is `f9da109`** (`fix(rede): teto de tempo no httpFetch do MetadataPackService`), the repository `HEAD` at the moment this plan was written, before the first slice-3 commit. If you need to confirm it yourself: it is the last commit whose tree does not contain `lib/widgets/footer/selection_bar.dart`.

- [ ] **Step 1: Prove that the untouched stayed untouched**

```bash
git diff --stat f9da109 -- \
  lib/widgets/game_grid/game_grid_item.dart \
  lib/widgets/game_grid/game_grid.dart \
  lib/widgets/game_grid/game_cover_flow.dart \
  lib/services/filtering_service.dart \
  lib/services/task_queue_service.dart \
  lib/widgets/footer/footer.dart \
  lib/widgets/game_list/
```

Expected: **completely empty output**, not a single line. Not "a few lines", not "just one import": zero.

The first three and `filtering_service` are the "Third locked decision", and the reason is there: a synthetic `Game` poisons `gameStateProvider` and the filters. The two in the middle are in the "Modified" table with the column saying "none", deliberately, because at some point someone will want a one-line `startDownloadsFromPicks` or will want to shove the selection bar inside `Footer`. `game_list/` is what UI spec section 12 leaves out of scope.

If anything shows up here, **the fix is to revert that file**, not to justify the change:

```bash
git checkout f9da109 -- <the file>
flutter analyze && flutter test 2>&1 | tr '\r' '\n' | tail -3
```

If reverting something causes a break, the slice created a dependency that should not exist, and that is a QA finding, not an implementation detail. Write what broke before touching anything else.

- [ ] **Step 2: Prove that no other existing production file was touched**

```bash
git diff --name-only f9da109 -- lib/ | sort
```

The output must be exactly these eighteen lines, not one more:

```
lib/models/grid_entry_model.dart
lib/models/source_pick_model.dart
lib/models/source_verification_model.dart
lib/providers/catalog_provider.dart
lib/providers/owned_games_provider.dart
lib/providers/pack_grid_provider.dart
lib/providers/source_verification_provider.dart
lib/screens/game_detail_screen.dart
lib/screens/home_screen.dart
lib/services/pack_grid_filter.dart
lib/services/source_index.dart
lib/services/source_pick_service.dart
lib/services/source_verification_service.dart
lib/widgets/footer/selection_bar.dart
lib/widgets/game_grid/batch_confirm_sheet.dart
lib/widgets/game_grid/pack_grid.dart
lib/widgets/game_grid/pack_grid_item.dart
lib/widgets/header/header.dart
```

That is the fifteen new files from the "File structure" table plus the three old files modified: `catalog_provider.dart` (Task 1), `header.dart` (Tasks 3 and 19), and `home_screen.dart` (Tasks 3, 6, 19, and 20).

Any extra line is a production file the slice touched without it being in the plan. It is not automatically wrong, but it is automatically **unplanned**, and it must be explained in writing in the QA report, with the reason and the commit it came in.

- [ ] **Step 3: Prove that the new tests are the expected ones**

```bash
git diff --name-only f9da109 -- test/ | sort
```

Expected, seventeen lines:

```
test/batch_confirm_sheet_test.dart
test/catalog_selection_test.dart
test/game_detail_screen_test.dart
test/grid_entry_model_test.dart
test/header_filter_label_test.dart
test/owned_games_provider_test.dart
test/pack_grid_filter_test.dart
test/pack_grid_item_test.dart
test/pack_grid_provider_test.dart
test/pack_grid_test.dart
test/selection_bar_test.dart
test/source_index_test.dart
test/source_pick_model_test.dart
test/source_pick_service_test.dart
test/source_verification_provider_test.dart
test/source_verification_service_test.dart
test/support/favorites_stub.dart
```

`test/support/favorites_stub.dart` is not a test case; it is the support for the "Sixth locked decision", created in Task 1 and used by Tasks 1, 12, 15, 16, 18, and 21. It adds no `+` to the suite count.

No **old** test file may appear in this list. If one does, someone fixed an old test to accommodate the slice, and that is exactly the regression Step 1 looks for, just disguised as a green test.

> **Exception registered after the sweep, in `5d21b14`.** Today the list has **eighteen** lines, and the eighteenth is `test/rar_decompress_screen_test.dart`, which is old. It is not the regression this Step looks for: the fix came after slice 3 had already passed Steps 1 through 5 and 7, did not change any `lib/` file, and has no relation to the slice. The test never passed once since `b011601`, the commit that created it, because `FilledButton.icon` returns `_FilledButtonWithIcon` and `find.byType` matches by exact type. It died with `Bad state: No element` before asserting anything. Whoever repeats this Step, verify that the eighteenth line is that one and only that one.

- [ ] **Step 4: Analyze**

```bash
flutter analyze 2>&1 | tail -30
```

Expected: `22 issues found.` and zero `error`. Verify the breakdown against the "Before starting" table: 11 `avoid_print` in `tool/verify_matcher.dart`, 1 in `tool/probe_zip_cd.dart`, 6 `deprecated_member_use` in `network_address_setting.dart`, 2 `use_build_context_synchronously` in `fbi_server_screen.dart`, 1 `unnecessary_non_null_assertion` in `webdav_server_test.dart`, 1 `dangling_library_doc_comments` in `rom_search.dart`.

The criterion is **22, and no finding in any file touched by this slice**. To check the second half without reading all 22 lines one by one:

```bash
flutter analyze 2>&1 | grep -E 'grid_entry|source_pick|source_index|pack_grid|source_verification|selection_bar|batch_confirm|game_detail|home_screen|header\.dart|catalog_provider|owned_games'
```

Expected: **empty output**. If anything comes out, fix it, even if the total stays at 22, because "we swapped an old finding for a new one" is not the criterion.

The most likely suspect is `use_build_context_synchronously` in `home_screen.dart`, coming from an `await` without `if (!mounted) return;` after it. Task 6 explains where they go and why `mounted` and not `context.mounted` in a `State`.

- [ ] **Step 5: Run the full suite**

```bash
flutter test 2>&1 | tr '\r' '\n' | tail -5
```

Expected, in the original sweep: `+339 -1`. The only failure is `test/rar_decompress_screen_test.dart`, the case `renders with extract disabled until a file and folder are picked`, the same one as before slice 1. **If there are two failures, the slice is not ready**, even if the second one seems unrelated.

> **After `5d21b14`, the expected is `+340`, with no failures.** That `-1` was a test that never passed since it was born, fixed outside the slice. The case is still a single one; it now counts as `+`. If you run today and see `+339 -1`, your HEAD is before `5d21b14`; **any failure is a regression**, "the usual failure" no longer exists.

The slice's count of 339, in case the number does not match and you need to know where to look (the 340 is this 339 plus the `rar` fix, which is external):

| Task | New | Running total |
| --- | --- | --- |
| baseline | n/a | 178 |
| 1, `clearSelection` | 2 | 180 |
| 2, `SelectionBar` | 5 | 185 |
| 3, wiring | 0 | 185 |
| 4, `BatchPlan` | 6 | 191 |
| 5, batch sheet | 11 | 202 |
| 6, `planFromGames` | 4 | 206 |
| 7, `PackGridEntry` | 4 | 210 |
| 8, `SourceIndex` | 7 | 217 |
| 9, `filterPackEntries` | 8 | 225 |
| 10, providers | 7 | 232 |
| 11, `PackGridItem` | 11 | 243 |
| 12, `PackGrid` | 7 | 250 |
| 13, games on disk | 10 | 260 |
| 14, `planFromEntries` | 12 | 272 |
| 15, detail screen | 9 | 281 |
| 16, no source and other sources | 11 | 292 |
| 17, CRC verification | 16 | 308 |
| 18, CRC on detail screen | 18 | 326 |
| 19, mode routing | 2 | 328 |
| 20, PACK MODE batch | 8 | 336 |
| 21, bar on detail screen | 3 | 339 |

- [ ] **Step 6: SOURCE MODE regression, manual**

```bash
flutter run -d linux
```

Pick a console **without** a metadata pack and run through today's app workflow. Nothing here can differ from before slice 1, with the **single** noted exception:

1. The grid draws the listing files, with cover art, tags, and progress bar as always.
2. The view-toggle button switches between grid, list, and coverflow, and all three render.
3. The search box filters.
4. The filter sheet opens from the funnel, the region, revision, and dump-quality chips filter the grid, and the funnel lights up when there is an active filter. Its tooltip is `Filters`.
5. Selecting a game and downloading works, the download appears in the footer, the progress bar advances, and the file arrives on disk.
6. **The exception:** the download button from the header no longer exists; in its place is the purple bar in the footer, which opens a confirmation sheet before enqueuing. That is Task 3 plus Task 6, it is UI spec section 5, and it is the only visible change to SOURCE MODE in this entire slice.

- [ ] **Step 7: Spec coverage, section by section**

Open `docs/stremio-de-jogos-ui.md` and verify that each section in this slice's scope has somewhere to point:

| UI spec section | Where it was done |
| --- | --- |
| 3.1, the tile only marks the exception | Task 11, and the "Read trap" at the top of this plan |
| 3.2, empty-state banner | Task 12 |
| 4, "already downloaded" border | Task 13 |
| 4, selection: gestures and checkbox | Tasks 11 and 12 on the grid, Task 15 on the detail screen. Desktop hover is a divergence noted in Task 11 |
| 5, selection bar | Tasks 1, 2, 3, and 21 |
| 6, batch confirmation sheet | Tasks 4, 5, 6, 14, 20, and 21 |
| 7, detail screen | Tasks 15 and 16 |
| 8, CRC verification | Tasks 17 and 18 |
| 11, file structure table | "File structure" at the top, with the three deliberate divergences noted there |
| 12, out of scope | Steps 1, 2, and 3 of this Task |

Sections 9 and 10 are for slices 4 and 6. If you get here and any row in the table above has nowhere to point, the gap is in the slice, not in the report.

- [ ] **Step 8: Close**

If the seven steps above passed, there is nothing to commit: the slice is fully in commits from Tasks 1 through 21. Write the report with the **full** output of every command from Steps 1 through 5, pasted, not summarized.

If any step required a fix, it is a single commit scoped to what was fixed:

```bash
git add <only the fixed files>
git commit -m "fix(<scope>): <what the regression sweep caught>"
```

And run Steps 4 and 5 again after the fix. A fix that was not re-analyzed and re-tested does not count.
