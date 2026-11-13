# Save Sync — redesign

**Spine: `wizard-first`** (two of three judges, and it owns the only hub change that is safe under concurrent edits). Everything below is that design with five grafts and two corrections the judges did not have.

## Grafts

| Grafted | From | Why |
|---|---|---|
| `hub.open` runs **before** the privileged shell | catalog-first | Verified: `lib/providers/save_sync_provider.dart` returns early on `if (shell == null || choice == null)` with `games: const []`, so a device with no Shizuku/root never opens the hub. Without this graft every "blocked rows still show" promise renders an empty screen. |
| `publishRecipe` called at **adopt**, not only inside `push` | catalog-first | Verified: `publishRecipe` has exactly one call site, `lib/services/save_sync/engine.dart:210`, behind `if (pushed)`. One added call site is what makes "the other device updates itself" true with no catalog and no network on device 2. |
| One-time migration: hub with `units/` but no `config/` adopts itself | catalog-first | Existing hubs land in the new flow with zero owner action. |
| ETag + `If-None-Match` + 304 on the catalog index; `RecipeIndex`, not `CatalogService` | catalog-first | Free daily refresh, and `CatalogService` / `add_catalog_source_screen.dart` already mean ROM sources in this repo. |
| Collapsed hub strip (hub + access + freshness on one line), editable `deviceName`, `notOpenableHere` as its own block reason, `HubKind.unknown` → progress bar only | list-first | The strip absorbs wizard-first's third step, so first run stays at the two decisions the owner described. `deviceName` is why "newest by …" is readable on two handhelds of the same model. `notOpenableHere` preserves what commit `32c6890` just established. |
| Slice 1 = scrub + icons + row title from the PackageManager label, one commit | list-first | Moving the row title off `recipe.name` is what makes the recipe-id rename invisible to the user instead of a visible regression. |

## Two corrections to the research

1. `test/save_sync_recipe_bundle_test.dart` has **7 grouping cases for 9 bundled recipes**, not 8. Two are uncovered; one of those two is the **only `verified` recipe** and the only one carrying `beforeRestore`, `checks` and `inProgress`. `verified` is load-bearing — `lib/services/save_sync/binding.dart:109,125` return `Bound(b)` instead of `NeedsConfirm(b, files)` for it — so the one recipe that binds without ever asking the owner to confirm the save location is one of the two with no grouping test.
2. The stale `source` doc comment is `lib/services/save_sync/engine.dart:46`, not `:52`.

**Blind spot none of the three designs found** (verified): `FolderBackend.list` returns `const []` for a directory that does not exist (`lib/services/save_sync/hub_backend.dart:51`), and `Hub.open` treats a top listing without `hub.json` as a fresh hub and **writes one with a new random id**. A removed SD card or a stale SAF tree therefore does not throw — it silently mints a second hub, changes `hub.key`, and orphans every stored base. Fixed here by `Hub.open({bool create = false})`: only the bind step in the wizard passes `create: true`.

## Two questions that gate slice 1

- **"arruma o `<that game>`"** — reading alone, that recipe parses and groups correctly. What it *is*: the only `verified` one, the only one using `beforeRestore`/`checks`/`inProgress`, one of two with no grouping case, and the file whose id/name/package breaks the no-real-titles rule. If "arruma" means a symptom on hardware, that symptom is needed; otherwise slice 0 + slice 1 below are the fix.
- **Is there a hub with real history on it?** A recipe id is a hub directory name (`units/<recipeId>/`, `recipes/<recipeId>/`). Renaming orphans every gen already pushed, on every hub that exists. Recovery is one push per app from the device holding the saves; the dead folders stay forever because the hub never deletes. One-way change — confirm before slice 1.

---

## 1. The flow end to end

A real first run on the **second** handheld. Device 1 is already set up and its folder is carried here by Syncthing.

1. **Menu → Save Sync.** `sync.hubChoice` is null, so the tile pushes the two-step setup instead of the list. First painted frame is the wizard header, never an error card.
2. **Step 1 — Where.** One question, two cards: *Google Drive* / *A folder on this device*. Tapping the folder card opens `pickDirectory` **immediately** — the picker is the first action, not a recovery. The path lands in the bordered monospace container as a *suggestion*; `defaultHubFolder` is pre-filled but nothing is committed. **Next** is the only call that writes `setHubChoice`.
3. **Bind and read.** `Hub.open(deviceId: …, create: true)` (the one place `create` is true), then `hub.config()`. No privileged shell is involved: reading a hub needs no privilege, so this works on a device with neither Shizuku nor root.
4. **Step 2 — Found here.** The hub holds a config, so the adopt face shows: *"This hub already has 7 apps, last changed by `<device name>`, 3 days ago"*, then three buckets — **Will apply here (5)**, **Not on this device (2)**, **Needs a look (0)**. Every row carries its app icon and label resolved locally through PackageManager. One primary button: **Adopt these 5**.
5. **Adopt.** Local only — nothing is written back to the hub. The device now has the same app list as device 1, intersected with what is installed here.
6. **Land on the list.** Header strip, one line: `📁 <folder name>   ·   Shizuku · read just now` — or `no access — 5 apps listed, none syncable from this device`. The device tier is stated once, here; fifty rows never re-explain it.
7. **Five rows, every one `Needs download — <device 1 name> is newer (2h)`**, download arrow badge, `Download` as the **FilledButton** (Push is the outlined one on a device that has nothing yet). Above them, one card: **Download 5**, whose confirm names how many rows it will skip and why.
8. **Access, if it is missing.** The access card sits above the rows with exactly one button — `Grant Shizuku access` when grantable now, `Retry` when Shizuku is not running, and **no button at all** when it is structurally impossible on this build or OS. The list is still there, still readable, with every row blocked and saying why.
9. **An app device 1 adopted that has no recipe anywhere** arrives as a real row: `No recipe yet`, with `Create recipe` — because the config is keyed by package and `"recipe": null` is a legal entry, that intent travels between devices instead of dying as an error line.
10. **Adding one more app from here.** List footer → **Add an app** → launchable installed apps with icons, catalog hits pre-ticked → **Add 1**. The recipe is fetched from the catalog, written into the hub config as a delta, **and its body published into `recipes/<id>/`** in the same action. Device 1 picks it up on its next refresh with no network and no catalog of its own.

---

## 2. Screens

Four screens and three sheets. House idiom throughout: `Card + Padding(12|16) + Column(crossAxisAlignment: start)`, action rows always `Wrap(spacing: 8, runSpacing: 8)`, `FilledButton` = affirmative, `OutlinedButton` = secondary, `TextButton` = inspect. Errors inline, never a SnackBar. No hint bars, legends or button glyphs.

### 2.1 Setup — step 1 of 2, "Where"

New file `lib/screens/save_sync_setup_screen.dart`. Third verbatim copy of the six helpers from `lib/screens/setup_wizard_screen.dart` (`_header` 205, `_stepDot` 254, `_sectionTitle` 273, `_statusRow` 512, `_navButtons` 526, `_footer` 563). Not extracted — see §8.

- No AppBar. Header: `Icon(Icons.sync)` + `Text('Save Sync', titleLarge)` + a **2**-dot rail (`Where · Apps`) collapsing to `Text('1/2 · Where', labelLarge, primary)` when `MediaQuery.sizeOf(context).height < 640`; `< 480` pulls nav into the header row and drops the footer.
- Body: `Align > ConstrainedBox(maxWidth: 640) > SingleChildScrollView(padding: EdgeInsets.all(24))`.
- `_sectionTitle(theme, Icons.place, 'Where should saves go?', 'One place both handhelds can reach.')`
- Two `InfoCard`s (`lib/widgets/about/info_card.dart`), `SizedBox(height: 8)` apart: `Icons.cloud` / *Google Drive* / "Sign in and pick the account on the next screen" (only when `googleAvailable`); `Icons.folder_shared` / *A folder on this device* / "Another app (Syncthing, FolderSync) carries it between devices".
- Under the folder card, the path container copied from `setup_wizard_screen.dart:421-449`: `Container(border: outlineVariant, radius 8, padding 12) > Row[Icon(Icons.folder, 20), SizedBox(10), Expanded(Text(path, fontFamily 'monospace', fontSize 12, ellipsis)), OutlinedButton('Choose')]`.
- `Next` disabled until a path is picked or an account is bound. `PopScope` + `_leaving` guard, copied from `setup_wizard_screen.dart:120-146`. `Actions{PrimaryActionIntent → Next}`.
- **The `SimpleDialog('Where should saves go?')` at `save_sync_screen.dart:49-79` is deleted.** The question is asked in exactly one place, in one wording.

### 2.2 Setup — step 2 of 2, "Found here"

Same chassis, dot 2 filled. While reading: `Center(child: HammerLoader())` + `_statusRow(theme, Icons.cloud_sync, primary, 'Reading the hub…')`.

**Face A — a config was found.** Satisfied card (`setup_wizard_screen.dart:300-349`): `Card(color: colorScheme.primaryContainer) > Padding(16) > Row[Icon(Icons.check_circle, color: primary), SizedBox(12), Expanded(Text('This hub already has 7 apps, last changed by <device name>, 3 days ago', bodyMedium))]`. Then three buckets, each omitted when empty, each a `_sectionTitle` + rows of `[icon 40, SizedBox(12), Column(label titleMedium / package bodySmall monospace)]`:

| Bucket | Contents | Controls |
|---|---|---|
| **Will apply here (N)** | entry's package is installed and a recipe resolves | `CheckboxListTile(contentPadding: zero)`, all pre-ticked |
| **Not on this device (N)** | package not installed | `Opacity(0.5)`, no control — the honest form of the silent filter in `63bf359` |
| **Needs a look (N)** | `"recipe": null`, or no recipe resolves, or the body fails `Recipe.parse`, or `RecipeTooNew` | one `bodySmall` line each: *"No recipe for this one yet"* / *"Written by a newer Retro Toolbox — update to use it"*. Never a raw `'$e'` |

Primary: `FilledButton('Adopt these 5')`. Unticking a row is a **local** choice this device makes once, at adopt time — it simply does not apply that entry now. There is no per-device mute afterwards (§8).

**Face B — nothing here.** `Icon(Icons.inbox, 48, onSurfaceVariant)`, `Text('This hub is empty.', titleMedium)`, `Text('Add the first app and Retro Toolbox looks it up in the recipe catalog.', bodySmall onSurfaceVariant)`, then `FilledButton.icon(Icons.add, 'Add an app')`. If `units/` exists but `config/` does not, the migration has already run by the time this paints, so face A shows instead.

**Blocked:** the hub cannot be read (missing SD card, stale SAF tree, Drive offline) → one Card, one sentence, one control: `OutlinedButton('Pick the folder again')` or `FilledButton('Sign in again')`. This is where the `Hub.open(create: false)` guard pays: without it this state is invisible and a second empty hub is created instead.

### 2.3 Save Sync — the list

Rewrite of `lib/screens/save_sync_screen.dart`. House tool-screen shape, plus the `DpadScope` wiring this screen is the only tool screen to lack.

```
Scaffold(appBar: AppBar('Save Sync', actions: [IconButton(Icons.refresh)]))
  > Actions({PrimaryActionIntent: …})           // bound to Sync all; null while busy
  > SafeArea > RefreshIndicator > ListView(padding: EdgeInsets.all(16))
```

Fixed child order — no `if`-guard reordering, so nothing is ever inserted above what the user is reading:

1. **`hubKind == HubKind.unknown` → `LinearProgressIndicator` and nothing else.** One guard, and today's first-frame bug is gone: the "No access to game folders" card can no longer paint before the hub is read and then be shoved down.
2. **Header strip.** `Card > Padding(12) > Column[ Row[Icon(Icons.folder_shared|Icons.cloud, 18), SizedBox(10), Expanded(Text(folder basename | googleEmail, bodyMedium, ellipsis)), TextButton('Change')], SizedBox(4), Text(statusLine, bodySmall onSurfaceVariant) ]`. `statusLine` is one `' · '`-joined phrase: `7 apps · last synced 2h ago · this device: Shizuku` / `… · this device: no access — nothing syncs from here` / `can't reach the hub — showing what this device last knew, 2h ago`. Tapping the strip expands an `ExpansionTile` (`shape: Border(), collapsedShape: Border(), tilePadding: zero`) holding the full path in the monospace container, a `TextField('This device is called')` bound to `SyncState.deviceName`, the other devices read from `devices/*.json` as `bodySmall` lines, and for Drive a `TextButton('Sign out — this also forgets the hub')` (today's label hides that `signOut()` calls `setHubChoice(null)`).
3. **Access card**, only when it changes what the user can do. House blocked-step shape: one-line condition, one sentence of remedy, `SizedBox(8)`, exactly ONE button — `FilledButton('Grant Shizuku access')` when `shizukuRunning`, `OutlinedButton('Retry')` when not, **no button** when it is structurally impossible. Plus `TextButton.icon(Icons.open_in_new, 'What is Shizuku?')`, and when `appFlavor == 'play'` one extra `bodySmall`: *"This build does not look for root, so a rooted device still shows no access here."* (`save_sync_provider.dart:283` skips the root probe silently today.)
4. **Attention card**, only when something needs the user: `FilledButton.icon(Icons.download, 'Download 4')` or `'Upload 3'`. Disabled while any row is `Conflict`, with the reason inline: *"2 conflicts to settle first."* Blocked rows never gate it. Its confirm states how many rows it will skip.
5. **The rows.**
6. **`ExpansionTile('Not on this device (2)')`** and **`ExpansionTile('Recipes that did not load (1)')`** — the latter swallows `recipeProblems`, with `load.tooNew` rendered as *"Update Retro Toolbox to use this one"*, not as a raw string under every card.
7. **Footer:** `FilledButton.icon(Icons.add, 'Add an app')`. The empty state is literally this button under `Icon(Icons.inbox)` + *"Nothing is set up to sync yet"* — never today's lone grey sentence.

**The row** (`_AppRow`: `Card > InkWell > Padding(12) > Row`):

```
Stack(48×48)                     ← the app icon, see below
SizedBox(width: 12)
Expanded(Column(start, [
  Text(appLabel, titleMedium, maxLines: 1, ellipsis),       // PackageManager label
  Text(stateLine, bodySmall, onSurfaceVariant),             // closed vocabulary, below
  Text(sourceChip, labelSmall, onSurfaceVariant),           // catalog | hub | bundled | yours
]))
trailing: the ONE action for this state, or a 16×16 CircularProgressIndicator(strokeWidth: 2)
```

**Where the icon goes.** The 48×48 leading slot is a `Stack`: base is the house thumbnail container from `lib/widgets/game_list/game_boxart.dart` — sized `Container`, `BorderRadius.circular(8)`, `colorScheme.outline` border at alpha 0.2, `ClipRRect` — holding `Image.memory(info.icon, width: 48, height: 48, cacheWidth: thumbnailDecodeWidth(…))` from `lib/utils/image_memory.dart`. No icon (no launcher activity, or any non-Android test run) falls back to `Icon(Icons.videogame_asset, onSurfaceVariant)` in the same frame. Overlaid bottom-right, 14 px, is the **state badge — four shapes only**:

| Badge | Colour | Means |
|---|---|---|
| `Icons.check_circle` | `primary` | up to date |
| `Icons.arrow_circle_up` / `arrow_circle_down` | `primary` | pending, in a named direction |
| `Icons.lock_outline` | `onSurfaceVariant` | blocked — a fact about this device |
| `Icons.error` | `colorScheme.error` | an action failed — an incident |

Blocked and failed never share a shape or a colour. Deliberately excluded/not-installed uses the neutral lock, not the error.

**How the rows read.** One sentence, direction always named, time always relative:

- `Up to date · 3h ago`
- `Needs download — <device name> is newer (2h)`
- `Needs upload — this device is newer (12m)`
- `Both sides changed since the last sync`
- `Confirm where the saves are`
- `No recipe yet`
- `Not installed here`
- blocked lines: see §6.

**One verb per row**, never two: `Download` / `Upload` / `Choose version` / `Confirm location` / `Create recipe` / nothing. `Push` is no longer the visual primary by default — whichever direction the row needs is the `FilledButton`.

**Sorting** happens once in the provider, keyed by package, never in `build`: Conflict → Confirm location → Needs download → Needs upload → Up to date → Blocked → No recipe → Not installed; label-sorted inside each bucket. Blocked and not-installed render at `Opacity(0.5)` and are never hidden.

**Busy** is per row *visually*: only the working row shows a spinner and greys its own buttons. The engine stays one-action-at-a-time (§8), so other rows' action buttons are also disabled — but the strip, the sheets, row taps and navigation stay live, which is the actual complaint today (`final busy = …` at line 152 greys everything including `Check` on unrelated rows).

### 2.4 App detail sheet

`showModalBottomSheet`, full height, `SafeArea > ListView(padding: 16)` — **no `SizedBox(width: 480)`**, which breaks on a handheld. Replaces all three current dialogs.

- Header `Row`: icon 48 with badge, `SizedBox(12)`, `Column[Text(label, titleMedium), Text(packageId, monospace 12, onSurfaceVariant)]`.
- One `' · '` line: `<recipe name> · <source> recipe · version X`.
- The bound save folder in the monospace path container (taken from the **notifier's** `_paths`, not a `const DevicePaths()` the screen builds itself).
- One `ListTile(contentPadding: zero, dense: true)` per unit: unit key, `planLabel`, `newest by <device name>, 2h ago`. Absolute timestamps only on expand.
- `TextButton.icon(Icons.fact_check, 'Check')` runs inline; `CheckLine`s render as dense rows on `colorScheme.primary` / `tertiary` / `error` — the literal `Colors.green` / `Colors.orange` die here.
- `TextButton.icon(Icons.remove_circle_outline, 'Remove from the list')`, last, in `colorScheme.error`. Confirm: *"Removed on every device. The saves already in the hub stay where they are."*
- Last: `ExpansionTile('Details')` holding `g.error`, this id's `recipeProblems` entry, and the failing shell output. **This is the only place a raw `'$e'` is allowed to appear.**

### 2.5 Add an app

`Scaffold(appBar: AppBar('Add an app')) > SafeArea > Column`.

- Top: search field matching **label OR package id**, case-insensitive, over one untouched master list, never re-sorting while typing. A search that narrows to exactly one row opens that row's preview immediately.
- One `bodySmall` catalog line: `Catalog updated 3h ago` / `Catalog unreachable — showing what was cached 2 days ago` / `Catalog unreachable and nothing cached`.
- Rows (56 px): `[icon 40, SizedBox(12), Expanded(Column[label titleMedium, packageId bodySmall]), status, Checkbox]`. Status right-aligned `labelSmall`: `Recipe available` (primary) / `No recipe yet` (onSurfaceVariant) / `Already syncing` (dimmed, checkbox disabled).
- Source: **launchable, user-installed apps only**, from the batched PackageManager call. "Show everything" is a settings escape hatch, not a control here.
- **One comparator, no section headers:** already-added first (disabled), then catalog hits, then the rest label-sorted.
- **Selection is a `Set<String>` of package names, never list positions** — filtering while rows are ticked cannot re-point the selection.
- First open on a fresh device: every installed app the catalog or the bundle covers is pre-ticked. First run is one tap.
- Footer: `FilledButton('Add 7')`.

### 2.6 Recipe preview sheet

Shown before a catalog recipe is adopted — a recipe is a set of globs that moves the owner's save files, so it is looked at once. `[icon 48, label, package]`, then `<recipe name> · draft|verified · updated 3 weeks ago`, then `_sectionTitle(theme, Icons.folder_open, 'Paths it touches', …)` with one monospace path container per `RecipeLocation` showing the absolute path, then `include` and `deviceLocal` as two `bodySmall` lists, then the version rule in words (*"Only restores onto the same app version"*). `Wrap[FilledButton('Add to sync'), TextButton('Create my own instead')]`. Trust is asked **once per catalog URL**, not once per recipe.

### 2.7 Choose version sheet

For `Diverged` — today a dead end whose own body copy says picking a version "comes in a later update" while both buttons sit disabled and `Diverged.heads` is populated and never shown.

One `Card` per head: `[Icon(Icons.smartphone|Icons.cloud, 18), Column[Text(meta.deviceName, bodyMedium), Text('2h ago · 412 KB · 6 files', bodySmall)], FilledButton('Keep this')]`; the local head is labelled *"On this device"*. Under both, one line: *"Every save this replaces is kept in history on this device."* Keeping one writes a merge gen naming **both heads as parents** — `GenMeta` already carries `parents[]` and `kind: 'merge'`, so the data model needs nothing new.

---

## 3. The hub data model change

One new folder. `hub.json`, `units/`, `devices/`, `README.txt` and `recipes/` are untouched in shape.

### `config/<genId>.json` — append-only, package-keyed, delta writes

`<genId>` is the existing `yyyyMMddTHHmmssZ-<deviceId>-<sha8>` form that `Hub._genFile` already matches, produced by `makeGenId`. Each file holds **only the entries the writing device changed** — never a merged snapshot.

```json
{
  "format": 1,
  "device": "handheld-a1b2",
  "writtenAt": "2026-11-12T09:14:03.000Z",
  "entries": {
    "com.example.app": {
      "recipe": "example-app",
      "updatedAt": "2026-11-12T09:14:03.000Z",
      "by": "handheld-a1b2"
    },
    "com.example.other": {
      "recipe": null,
      "updatedAt": "2026-11-12T09:14:03.000Z",
      "by": "handheld-a1b2"
    },
    "com.example.third": {
      "removed": true,
      "updatedAt": "2026-11-12T09:14:03.000Z",
      "by": "handheld-a1b2"
    }
  }
}
```

**Keyed by package**, because that is what the owner picks, what PackageManager resolves an icon and label from, and the only key that can exist *before* a recipe does. `"recipe": null` is the "wanted, nothing resolves yet" state the model has no slot for today — such an id can currently only land in `recipeProblems`, an error channel rendered as *"Recipe X not loaded"*. `"removed": true` is the hub's first tombstone. Package regex is the one already in `recipe.dart`: `^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)+$`.

**Why a folder and not one `config.json`.** `Hub`'s own invariant (`hub.dart:37-38`) is that every file is written once by one device, except `devices/<id>.json` (one writer) and `README.txt` (derived, disposable). A mutable root config would be the first file many devices edit whose loss costs the owner's intent — and on Drive, where duplicate names in one parent are legal and `DriveBackend`'s rule is *reads take the union, writes go to the oldest copy*, two devices writing one root name is an already-documented hazard. `config/` copies the shape `recipes/<id>/` already proves in production.

**Why delta writes are the whole safety story.** Each device writes only what it changed, so two devices editing different apps collide never, with no revision counter, no compare-and-set and no conflict UI. (This is the one clause `list-first` got wrong — it wrote the merged snapshot back, which resurrects a tombstone from a stale read.)

### Two methods on `Hub`

```dart
/// Union of every readable file under config/; per package the entry with the
/// greatest updatedAt wins, ties broken by `by` string compare. Unreadable
/// files are skipped, exactly as recipes() already does.
Future<HubConfig> config();

/// Writes ONE new file holding only [changed]. Never rewrites an existing file.
/// Skips the write when a file ending -<sha8>.json already exists, the same
/// dedup guard publishRecipe uses at hub.dart:157-169.
Future<void> putConfig(Map<String, ConfigEntry> changed, {required String deviceId});
```

Merge, parse and the tombstone live in a new pure `lib/services/save_sync/hub_config.dart` (~80 lines, unit-testable with no backend). Two entries naming the same recipe id under different packages are deduped by greatest `updatedAt` — the only way that happens is a migration-written key meeting a picker-written one.

**No pruning.** One small file per edit. `// ponytail: keep newest K the way prune keeps gens, when a real hub has hundreds.`

### Recipe bodies travel with the config

`hub.publishRecipe(r.raw, source: source, …)` gains a second call site: the **adopt/add** path in the provider, for any recipe whose source is not `'hub'`. Today its only call site is `engine.dart:210`, inside `push` behind `if (pushed)` — so an app chosen but never pushed leaves no trace in the hub at all. With this one line the adoption and the recipe body travel together, and device 2 needs neither the network nor a catalog.

### How an existing hub keeps working

- `backend.list('config')` returns `const []` for a hub that has no `config/`. Nothing throws.
- **Migration, once, no owner action:** a hub with `units/` but no `config/` is pre-existing. The first device to open it writes one delta adopting every recipe id that already has a unit folder, keyed by `recipe.packages.first` (deterministic from the recipe, so every device computes the same key), with `by` = that device. Existing hubs land in the new flow showing exactly the list they showed before.
- A hub with neither `units/` nor `config/` is empty and gets face B.
- A `config/` file with `format > 1` is skipped like an unreadable gen, **and** its package lands in the "Needs a look" bucket as *"Written by a newer Retro Toolbox"* — so a newer device's adoptions are never silently invisible.
- `hub.json`'s existing `format` + `HubTooNew` remains the only version gate.
- `SyncState` gains exactly three keys: `deviceName` (editable; today the name is the model, so two identical handhelds are indistinguishable in *"newest by …"*), `saveSyncConfig` (the merged config cached per `hub.key`, so an unreachable hub shows the last known list instead of an empty one), and `catalogFetchedAt`. Nothing else moves to prefs — membership lives in the hub, which is the point.
- `engine.dart:46`'s doc comment is corrected to the vocabulary actually used: `bundled | hub | catalog | user`.

### What changes in the provider

`_doRefresh` order becomes, and the first line is the important one:

```
_sync() → hub.open(create: false) → hub.config() → shell/access
        → resolve each configured package to a recipe → build engine → statuses → report
```

`hub.open` moves **ahead of** the shell, and the early return splits: `choice == null` → first run; `shell == null` → still open, still read the config, still build rows, with `access: none` and every row `Blocked(noAccess)`. Reading a hub needs no privilege.

**Membership is the config; content is the source.** `games` is built for `cfg.entries` only. A bundled recipe not in the config is an *Add an app* candidate, not a row. Recipe resolution per entry, first hit wins: `user > catalog > hub > bundled`; the winner is rendered as the row's source chip, so which layer won is never implicit. This replaces the line that makes bundled unconditionally win (`if (known != null && known.$2 != 'hub') continue;`).

### The closed row vocabulary

```dart
sealed class RowState {}          // UpToDate · NeedsPush · NeedsPull · Conflict
                                  // NeedsConfirm · Blocked(BlockReason) · NoRecipe · NotInstalled
enum BlockReason { needsRoot, notOpenableHere, folderMissing, locationUnknown,
                   noAccess, backupOnly, platformCannot }
```

One top-level function maps `GameStatus` + `BindResult` + `UnitPlan` onto it, living where `planLabel` lives today. The UI cannot invent a ninth state out of an exception string.

---

## 4. The GitHub catalog lookup

New file `lib/services/save_sync/recipe_index.dart` — **`RecipeIndex`, not `CatalogService`**, which already means ROM sources in this repo (`lib/services/catalog_service.dart`, `lib/screens/add_catalog_source_screen.dart`). "Catalog" stays a UI word only.

**Shape.** One static index and one file per recipe, both plain files over HTTPS — no API, no auth, no rate limits, works offline from cache:

```
<base>/index.json
<base>/recipes/<recipe-id>.json
```

```json
{
  "format": 1,
  "updated": "2026-11-10T00:00:00.000Z",
  "recipes": [
    { "id": "example-app", "packages": ["com.example.app"],
      "status": "draft", "sha": "9f2c1ab4", "updated": "2026-10-28T00:00:00.000Z" }
  ]
}
```

Bodies are fetched only when a row is previewed or added, so the index stays a few KB for hundreds of entries and a cold *Add an app* is instant.

**The base URL is not committed.** The standing no-source-names rule forbids it. It lives in `lib/services/settings_service.dart`, seeded from a git-ignored `assets/catalog/` file when the build has one — the precedence `lib/services/catalog_service.dart:29-39` already documents. `null` means "whatever this build was seeded with", so the default can move with no migration. No settings UI until a second catalog exists.

**Transport.** `dart:io HttpClient` with a 10 s `connectionTimeout` — this repo's own idiom in six services (`update_service.dart`, `catalog_service.dart`, `link_download.dart`, `drive_transport.dart`). No new dependency; there is no `http` package in `pubspec.yaml` and none is needed.

**What is cached.** `<getApplicationSupportDirectory()>/save_sync/index.json` plus its ETag beside it, and `<…>/save_sync/recipes/<id>.json` for each fetched body. Every fetch sends `If-None-Match`; a 304 keeps the cache and costs nothing. Refresh at most once per 24 h, plus on opening *Add an app* and on pull-to-refresh there. Never a timer, never blocking a paint, never a required "update catalog" button — just a quiet `Catalog updated 3h ago` line.

**Lookup is exact, by package id.** A `Map<String package, IndexEntry>` built once on load by fanning out each entry's `packages`. Package ids are exact, so there is no matcher, no fuzzy scoring, no near-match to silently pick wrong, and one unmatched app never blocks the others.

**Offline, cache present:** use it without complaint; the line reads `Catalog unreachable — showing what was cached 2 days ago`. Stale-but-known beats confidently-wrong; nothing flips to an error badge because the network is down.

**Offline, no cache at all:** *Add an app* still opens and still lists every installed app. Every row reads `No recipe yet` and its action is `Create recipe`. The nine bundled recipes stay in the APK as the offline seed and lose only their precedence, never their place.

**Catalog reachable, nothing for the package:** one flat line naming what was searched — `No recipe for com.example.app yet` — and `FilledButton('Create recipe')` prefilled with the package, the label and the detected data dir. Not an error, not a dead end, not "No suitable release was found".

**Growing the catalog:** the authoring wizard's done face carries `TextButton('Share this recipe')`, which opens a prefilled GitHub new-issue URL via `url_launcher` (already a dependency). That is the only mechanism by which the catalog grows, and it is one tap from authoring.

**The catalog is never a precondition.** Setup, adopt, the list, push and pull all work with it unreachable, because the hub carries the recipe bodies device 2 needs.

---

## 5. On-device recipe authoring

New file `lib/screens/save_sync_recipe_wizard_screen.dart`. Fourth multi-step flow, same six helpers. Requires `access != SyncAccess.none` — adopting does not, authoring does, and that is said **on the row before the tap**, not discovered on step 2.

Four steps: **App · Folder · Shape · What travels**, name and generated JSON on the last one.

### What it derives by looking

| Field | Derived how |
|---|---|
| `packages` | the chosen app's package; the Kotlin `appInfo` reply is itself the answer to "which of these is installed" |
| `locations` | probe `/storage/emulated/0/Android/data/<pkg>` and, with root, `/data/data/<pkg>`; show the real listing and let the user pick the root |
| `id` | slug of the label, validated against `^[a-z0-9][a-z0-9-]{1,63}$` and against existing ids |
| `status` | always `draft`. `verified` is never offered (it skips the confirm prompt in `binding.dart:109,125`); `fromCode` is dead and never emitted |
| `version` | `{"from": "package", "rule": "sameBuild"}` — correct with zero knowledge, and only ever refuses a cross-version restore |
| `include` / `deviceLocal` | pre-ticked from a **before/after diff**: scan, *"Open the app, save once, then come back"*, `OutlinedButton('Scan again')`, re-scan. Files that changed are save data; files that did not are suggested as `deviceLocal`. `UnitScanner` already does this double listing for busy detection. Name heuristics (`*.bak`, `*_old`, `settings*`, `*.log`) only pre-tick — never decide |
| `checks` | sniffed: run the two existing predicates over the candidate files (`binaryFormatterEnvelope` on raw bytes; for XML-ish text, derive the closing tag from the trimmed tail). A derived check is self-validating because it passed on a real file |
| `nativeCloud`, `beforeRestore`, `inProgress` | omitted. Omitting them costs strictness, not safety |

### What it must ask

1. **The shape.** The one question a device genuinely cannot answer, asked in plain words with the real listing still on screen: three `InfoCard`s — *"Each folder here is a separate save"* (`unit: folder`), *"Each file here is a separate save"* (`unit: file`), *"All of this together is one save"* (`unit: all`). A wizard can see "N sibling directories with similar contents" but cannot tell one-folder-per-slot from one-folder-per-subsystem, nor three-files-three-slots from three-files-one-save. The unit key becomes the hub directory name, so getting it wrong later orphans everything already pushed — asked once, explicitly, never guessed.
2. **Which root**, when more than one location holds files.
3. **The name**, since `pm list packages` gives no label for a non-launchable app.

Everything else is derived or omitted.

### Finish

`Recipe.parse` **is** the validator — unknown top-level keys are a hard error — so Finish builds a `Map`, calls `Recipe.parse`, and shows the `RecipeError` message verbatim if it throws. No new validation code.

Two self-checks after a clean parse, because three schema warts let a parseable recipe match nothing:

- run `groupUnits` against the real device listing and **refuse to save a recipe that groups zero files** (a folder-unit `include` without a `/` can never match);
- reject `unit: file` patterns containing `/` beyond what `Recipe.parse` already checks.

Saved to `<DevicePaths.saveSync>/recipes/<id>.json`, read back by the existing `parseRecipeFiles` (which requires file name == `<id>.json`, giving collision-free ids for free) with source `'user'`, first in the resolution order. Adopting it writes the config entry **and** publishes the body into `recipes/<id>/`, so it reaches the other handheld with no network.

One service addition, the only one in this design: a non-recursive `GameFs.listDir` — `listFiles` runs `find <dir> -type f` and so cannot show an empty folder or tell a folder from a file.

---

## 6. How a blocked item reads

Today every error on this screen is a raw exception string: `s.error` is `'$e'` in both catch arms of `_doRefresh`, `GameStatus.error` is `'$e'`, `signInError` is `'$e'`, `_act` sets `messages = ['$e']`, `_showCheck` falls back to `'$e'`. None of it is mapped to guidance.

A blocked row keeps its position in the list, keeps its icon, renders at `Opacity(0.5)`, carries a neutral `Icons.lock_outline` badge in `onSurfaceVariant` — **never the error colour** — and says one sentence. Blocked is a fact about this device; failure is an incident; they never share a shape.

| `BlockReason` | Row line | Control | Where the raw text goes |
|---|---|---|---|
| `needsRoot` | *"Saves live in a folder only root can open. This device isn't rooted."* | none | detail sheet → Details |
| `notOpenableHere` | *"This device can't open this app's save folder — it works on your other handheld."* | none | Details (the `32c6890` case: readable for the same app elsewhere, so "root your device" would be a lie) |
| `folderMissing` | *"Open the app once so it makes its save folder."* | none — the user acts outside the app | Details |
| `locationUnknown` | *"The saves could be in more than one place here."* | `Confirm location` | Details |
| `noAccess` | *"Nothing syncs from this device yet."* | none on the row — the one access card above the list owns the remedy | header strip |
| `backupOnly` | *"This app has its own cloud — uploads only."* | `Upload` | — |
| `platformCannot` | *"This Android version doesn't let apps open this folder."* | **none, deliberately** | Details |

Rules that make this hold:

- **No button that will fail.** `platformCannot` is computed before render from `Build.VERSION.SDK_INT`, whether the recipe path is under `Android/data`/`obb`, whether a persisted URI permission covers it, and whether a privileged shell exists. A `Grant` button that opens a picker which cannot grant what was promised trains the owner to distrust the app.
- **The device tier is explained once**, in the header strip. Fifty rows never re-explain it.
- **Blocked rows never gate the bulk action.** Conflicts do (they are tasks); blocked rows are conditions. The bulk confirm says how many it will skip.
- **A row is never hidden.** Hiding reads as data loss, especially when the hub config lists an app this device cannot handle.
- `recipeProblems` move from raw lines under every card into the `Recipes that did not load (N)` ExpansionTile, with `load.tooNew` rendered as *"Update Retro Toolbox to use this one"*.

---

## 7. Build order

Every slice ships on its own. The app is fully usable after each.

**Slice 0 — the two missing grouping cases.** Add cases for the two uncovered bundled recipes to `test/save_sync_recipe_bundle_test.dart` (7 cases, 9 recipes today; one uncovered is the only `verified` one, which binds without ever asking the owner to confirm). Pure test, no behaviour change, and it is the safety net under slice 1.
*Files:* `test/save_sync_recipe_bundle_test.dart`

**Slice 1 — names off the device, labels onto the screen.** The owner's visible ask and the standing-rule scrub in one commit, because they cancel each other out: the row title stops coming from `recipe.name` at all, so the rename is invisible to the user.
- rename the nine `save_recipes/*.json` ids, file names and `name` fields to neutral slugs;
- scrub the real titles, package names and version strings out of the save-sync tests and fixtures; delete the two title-bearing comments;
- add the `ACTION_MAIN` / `CATEGORY_LAUNCHER` `<intent>` to the existing `<queries>` block (**not** `QUERY_ALL_PACKAGES` — Play-restricted, and the app already files `MANAGE_EXTERNAL_STORAGE`);
- add one batched `"appInfo"` case to the `retrotoolbox/native` channel (`getApplicationInfo` + `loadIcon` + `loadLabel` → 96 px PNG, on a background `Thread` + `runOnUiThread`, like the existing `"copy"` case; `Bitmap`/`Canvas`/`ByteArrayOutputStream`, no androidx dependency);
- `_loadAppInfo` + `appInfo` on `SaveSyncState` (one line in the hand-written `copyWith`), a process-lifetime static map holding the **same** `Uint8List` instance so `MemoryImage` decodes once, wrapped in `on MissingPluginException` so `flutter_test` is a silent no-op and every existing test stays green;
- the 48 px icon ahead of the title in today's `_GameCard`.
*Files:* `save_recipes/*.json`, `test/save_sync_*.dart`, `test/save_sync_support.dart`, `lib/services/save_sync/save_checks.dart`, `lib/services/save_sync/pusher.dart`, `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/name/rafaismy/retrotoolbox/MainActivity.kt`, `lib/providers/save_sync_provider.dart`, `lib/screens/save_sync_screen.dart`
*Check:* one `Stopwatch` around the first `_loadAppInfo` on the real handheld — 150-400 ms for ~20 apps is an estimate, not a measurement.

**Slice 2 — the row and the list.** `RowState` + `BlockReason` beside `planLabel`; sorting moved into the provider, keyed by package; the badge set; one verb per row with direction-correct primacy; per-row progress; the header strip (hub + access + freshness, editable `deviceName`); the `HubKind.unknown` progress-bar guard; the detail sheet replacing all three dialogs (and their `SizedBox(width: 480)` and literal `Colors.green`/`orange`); the two ExpansionTiles; the real empty state; `DpadScope`.
`test/save_sync_screen_test.dart` is **rewritten, not patched** — its 16 cases drive exact labels bound to exact button types, assert vertical order by `getTopLeft().dy`, and pin *"before the first refresh has read the hub, neither the first run nor a hub row shows"*, which this slice exists to delete. `test/save_sync_screenshots_test.dart` gains runs below 640 and below 480.
*Files:* `lib/screens/save_sync_screen.dart`, `lib/providers/save_sync_provider.dart`, `lib/services/save_sync/sync_state.dart`, `test/save_sync_screen_test.dart`, `test/save_sync_screenshots_test.dart`

**Slice 3 — hub before shell.** Split the early return in `_doRefresh` so a device with no Shizuku and no root still opens the hub and still builds rows; `Hub.open({bool create = false})` so a missing folder or stale SAF tree throws `HubMissing` instead of silently minting a second hub; `notOpenableHere` plumbed from the binder.
*Files:* `lib/services/save_sync/hub.dart`, `lib/providers/save_sync_provider.dart`, `lib/services/save_sync/binding.dart`, `test/save_sync_hub_test.dart`, `test/save_sync_provider_test.dart`

**Slice 4 — configuration travels.** New `lib/services/save_sync/hub_config.dart`; `config()` / `putConfig()` on `Hub`; the merge-by-`updatedAt` + `by` tiebreak rule; the `units/`-without-`config/` migration; `publishRecipe` on the adopt path; the `saveSyncConfig` local cache keyed by `hub.key`; membership driven by the config; resolution order `user > catalog > hub > bundled` with the source chip. New test: two devices, overlapping edits, one tombstone, one stale read.
*Files:* `lib/services/save_sync/hub.dart`, `lib/services/save_sync/hub_config.dart`, `lib/providers/save_sync_provider.dart`, `lib/services/save_sync/engine.dart`, `test/save_sync_hub_config_test.dart`, `test/save_sync_hub_test.dart`

**Slice 5 — the two-step setup.** `lib/screens/save_sync_setup_screen.dart` (third chassis copy); `pickDirectory` as the first action; nothing committed until Next; both faces of step 2 with the three buckets; the menu tile routing to setup when `hubChoice` is null and to the list otherwise; the duplicate `SimpleDialog` deleted.
*Files:* `lib/screens/save_sync_setup_screen.dart`, `lib/screens/menu_screen.dart`, `lib/screens/save_sync_screen.dart`, `test/save_sync_setup_screen_test.dart`

**Slice 6 — Add an app and the catalog.** The launchable-app picker; `lib/services/save_sync/recipe_index.dart` with ETag/304, 24 h TTL, cache and age line; the trust ask per catalog URL; the preview sheet. Every failure path lands on `Create recipe`, a stub in this slice that says so — nothing dead ships.
*Files:* `lib/screens/save_sync_add_app_screen.dart`, `lib/services/save_sync/recipe_index.dart`, `lib/services/settings_service.dart`, `lib/providers/save_sync_provider.dart`, `test/save_sync_recipe_index_test.dart` (loopback `HttpServer`, the repo's own pattern)

**Slice 7 — create a recipe.** The four-step wizard; `GameFs.listDir`; the before/after diff; `Recipe.parse` as validator plus the `groupUnits` zero-files refusal; `<DevicePaths.saveSync>/recipes/<id>.json` as the user layer; the prefilled share link. **Extract the wizard chassis here** — this is the fourth copy, which is where it finally pays — and rewire both shipped wizards in the same slice (`setup_wizard_test.dart` asserts the exact `'2/3 · Downloads'` string, so the counter format and the ` · ` separator survive byte-for-byte).
*Files:* `lib/screens/save_sync_recipe_wizard_screen.dart`, `lib/widgets/common/wizard_chassis.dart`, `lib/screens/setup_wizard_screen.dart`, `lib/screens/sport_patcher_wizard_screen.dart`, `lib/services/save_sync/game_fs.dart`, `lib/services/save_sync/recipe_store.dart`, their tests

**Slice 8 — choose version.** `Diverged.heads` surfaced in the conflict sheet; a merge gen naming both heads as parents; conflicts gating the bulk action with a count that decrements. Last, because it is the only slice that changes what the engine writes — and until it lands a conflict row is honestly blocked rather than lying about a later update.
*Files:* `lib/screens/save_sync_screen.dart`, `lib/services/save_sync/engine.dart`, `lib/services/save_sync/sync_planner.dart`, `test/save_sync_engine_test.dart`

---

## 8. What this design deliberately does not do

- **No concurrent actions.** The engine stays one action at a time; `busyRecipe` survives. The UI change is *where the progress shows* and that the strip, sheets and navigation stay live — not parallel pushes. The real cure for "N pulls on a fresh device" is the bulk action plus not ending every `_act` with a full rescan, and that is a provider change for another day. Claiming "the rest of the screen stays live" while two taps reach one serialised engine would be a lie in the spec.
- **No `minAppFormat` field.** `list-first` and `wizard-first` both wanted a Joplin-style minimum-version gate. With per-device delta writes it buys nothing: an old build never rewrites another device's file, so there is no half-understood snapshot to drop fields from. A `config/` file with `format > 1` is skipped and its package shows as *"Written by a newer Retro Toolbox"*. Add the gate when a config file shape actually changes.
- **No revision counter and no clock tiebreak beyond `by`.** Merge trusts device clocks. Skewed clocks can resolve a removal backwards. The blast radius is one row in a list, recoverable by removing it again; save data is never at stake. `// ponytail: add a counter if a race is actually observed.`
- **No pruning of `config/`.** One tiny file per edit, and pruning plus silent skipping of unreadable files is the one path that can permanently lose an adoption.
- **No per-device mute.** Removal is a hub tombstone, stated in the confirm (*"Removed on every device"*). A local mute would need a new prefs key and must never render the same way; Syncthing's introducer docs show what leaving that ambiguous costs. Unticking at adopt time is a one-shot choice, not stored state.
- **No wizard chassis extraction before slice 7.** The two existing copies have already diverged, so a "verbatim lift" today is a reconciliation disguised as a move, touching two shipped screens and their tests for zero user value. Copy a third time in slice 5; extract at the fourth. Debt with a named due date, not a free choice.
- **No `QUERY_ALL_PACKAGES`, no system apps by default.** The `<queries>` launcher intent gets every launchable app with no permission and no Play declaration, and launchable-only is the right default. An app with no launcher activity gets no icon and no label and falls back to the recipe name and `Icons.videogame_asset`.
- **No disk cache for icons.** Memory only. An icon changes when the app updates, so a disk cache saves ~250 ms once per cold start and buys an invalidation problem.
- **No switch of `GameFs.installed()` / `versionName()` to PackageManager**, tempting as it is — the same unprivileged call answers both, and it would make the whole list render without Shizuku or root. It touches the `GameFs` abstraction and its fakes in three test files. Separate change, after the icons land.
- **No second catalog, no catalog settings UI, no deep link.** One index, URL in settings, `null` meaning "built-in". Build the sources screen when a second source exists.
- **No `beforeRestore` authoring, no `verified` from the wizard, no `fromCode`.** `beforeRestore` requires knowing a game writes a crash-recovery file it prefers over the real save — invisible from any listing. `verified` skips the confirm prompt; a device-made recipe has not earned that. `fromCode` is parsed and consumed nowhere.
- **No in-place editing of a catalog or bundled recipe.** Editing forks into the user layer, keyed by the same id. Nothing shipped or published is mutated.
- **No `was: [<oldId>]` alias field on recipes.** It would be a schema 2 bump (`Recipe.parse` rejects unknown top-level keys), so every older build would reject every recipe carrying it. The rename is handled by one push per app, or not at all — the owner's call, before slice 1.
- **No SnackBars, no toasts, no hint bars, legends or button glyphs.** Every message is inline text; the gamepad scheme is already approved and stays invisible.