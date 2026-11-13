# Syncing Switch‑emulator saves

Recommendation for the `feat/save-sync` branch. All code citations verified against the working tree on 2026‑11‑13.

Placeholder convention: `<TITLE-ID>` is the 16‑hex uppercase application id, `<PROFILE-ID>` the 32‑hex account directory. No real ids appear here.

---

## 1. What these emulators actually do

All four installs are forks of one project and share one function. Facts below are read from that source, not inferred, except where marked.

**The save path is one `fmt::format` call, with no index and no manifest.** `SaveDataFactory::GetFullPath` in `src/core/file_sys/savedata_factory.cpp`:

```
fmt::format("{}save/{:016X}/{:016X}{:016X}/{:016X}", out, 0, user_id[1], user_id[0], title_id)
```

`out` is `/user/` for normal saves. `Open()` then calls `dir->GetDirectoryRelative(save_directory)`. **Consequence: a save directory is valid wherever its name matches what the local install computes.** Nothing validates, registers or signs it. Verified identically in three independent fork trees.

**The 16‑hex segment is a hard‑coded literal `0`.** It is the `save_id` argument, and a literal `0` is passed for both `SaveDataType::Account` and `SaveDataType::Device`. It carries a real value only for `SaveDataType::System`. Switchbrew's `SaveDataAttribute` agrees: field 0x18 `StaticSaveDataId` is "0 for SaveData". **Treat `0000000000000000` as a constant.** The measurement is correct and will stay correct.

**The 32‑hex segment is a random UUID minted once per install.** `ProfileManager`'s constructor runs `ParseUserSaveFile(); if (user_count == 0) { CreateNewUser(UUID::MakeRandom(), "<name>"); WriteUserSaveFile(); }`. `UUID::MakeRandom()` (`src/common/uuid.cpp`) seeds TinyMT from `std::random_device` and fills all 16 bytes — no device id, no hostname, no time. It is stored only in `files/nand/system/save/8000000000000010/su/avators/profiles.dat`. This is exactly why two installs on one handheld show different ids. **It is per install, never per person and never per device.**

**It does not survive a data wipe.** Android "Clear data", an uninstall, or deleting the user folder removes `profiles.dat`; the constructor then finds `user_count == 0` and mints a fresh random UUID. The save directory no longer matches the games' existing saves, and the code logs exactly that. (Code‑level: solid. *Which* Android operations wipe `files/` is user‑reported, not documented.)

**The all‑zeros sibling is Device save data, not junk.** `GetFullPath` uses the same format string for `SaveDataType::Device`, with a zero `user_id`. Switchbrew: a zero UserId "indicates the common savedata (savecommon)", and for DeviceSaveData the attribute is "all-zero except for the Type field". The desktop frontend asserts `has_user_save != has_device_save` — **a title is one or the other, never both.** It holds real, non‑reproducible progress.

**Up to 8 real profile directories can exist at once.** `constexpr std::size_t MAX_USERS{8};`.

**The directory name is the UUID's bytes fully reversed.** `AsU128()` memcpy's 16 bytes into `array<u64,2>`; printing `{:016X}{:016X}` as (hi, lo) on little‑endian emits byte 15 down to byte 0, uppercase. `RawString()` prints byte 0 to 15, lowercase. Never map a folder name to a displayed UUID without reversing. (`AsU128()` is commented "DO NOT USE.")

**A newer layout exists and is preferred when present.** `GetFutureSaveDataPath` returns `/user/save/account/<uuid.RawString()>/<title_id & ~0xFF:016X>/0` and `/user/save/device/<title_id & ~0xFF:016X>/0`. `GetFullPath` checks it first and uses it if the directory exists, logging "Using save at new location". **There is no migration code** — something else must create it. Note it uses the *non‑reversed* raw string and masks the low byte of the title id.

**The emulators already ship a zip save format, and it deliberately contains no profile id.** `GamePropertiesFragment.kt` export: `FileUtil.zipFromInternalStorage(File(saveDir), saveLocation.replaceAfterLast("/", ""), ...)` — since `saveDir` ends `.../<PROFILE-ID>/<TITLE-ID>`, the zip root is the `<TITLE-ID>` directory. Import unzips to cache, looks for a top‑level directory whose name equals `game.programIdHex`, then `deleteRecursively(); mkdir(); copyRecursively()`. No match gives "invalid zip structure". **Keying an archive on the title id and letting the destination re‑derive the profile directory is the emulators' own answer, not an invention.**

**Their export does not compress.** `zipFromInternalStorage(..., compression = false)` sets `DEFLATED` with `Deflater.NO_COMPRESSION`. Our pusher already uses real DEFLATE; keep it.

**The Android frontend hardcodes profile index 0.** `native.cpp`: `// TODO: Pass in a selected user once we get the relevant UI working` then `manager.GetUser(0)`, while the running core uses `Settings::values.current_user`. With more than one profile, the directory the built‑in import/export writes may not be the one the game reads. It also always requests `SaveDataType::Account`, so **device saves are invisible to the emulator's own per‑game export on Android.**

**The save directory holds emulator bookkeeping.** `savedata_factory.h` defines `.yuzu_save_size`, written by `WriteSaveDataSize`. Not game state; it makes two otherwise identical saves differ byte‑wise.

**Upstream hit this problem itself.** The Android client removed its global save import/export UI, stating it would not export or import all of a user's saves depending on their profile configuration. Release notes for one fork warn that improper profile handling "may result in you losing save data", that orphaned‑profile dialogs are likely, and that the good profile "should NOT be all zeroes".

### Still unknown

- **The decisive two‑install test has never been run.** Every claim that a title directory dropped under a different profile id is actually read comes from source reading, not execution. The paired handheld has none of these emulators installed, so the cheap version is on‑device: copy a title directory from one install's profile into another install's profile and launch it.
- **Whether the account id is embedded in `.sav` contents.** One community writeup reports a "profile no longer exists" error after a cross‑install copy, requiring an in‑game profile transfer. A Ryujinx change moved the default user from a fixed id to a random one because "some games don't like the fact that by default every player has the same profile ID". No file‑level tool can fix this. A hexdump on the handheld answers it: grep the real profile id *and its byte‑reversed form* across the `.sav` files in one title directory.
- **Only one fork's source was read end to end.** The other three are assumed identical from the measured layout. Whether any has migrated to the `account/<uuid>/` layout, or patched `savedata_factory.cpp`, is unverified per fork.
- **The on‑disk format of `profiles.dat`.** So forcing two installs to share a profile id by editing it is not safe to attempt.
- **Whether omitting `.yuzu_save_size` on restore bothers the emulator.** Untested.
- **Whether the all‑zeros directory is populated on these installs.** The spec is unambiguous about what it means; how many titles in this library use device saves is unmeasured.

Sources: `src/core/file_sys/savedata_factory.{cpp,h}`, `src/core/hle/service/acc/profile_manager.{cpp,h}`, `src/common/uuid.{cpp,h}`, `src/common/fs/{fs_paths.h,path_util.cpp}`, `src/core/file_sys/bis_factory.cpp`, `src/android/.../{native.cpp,GamePropertiesFragment.kt,Game.kt,FileUtil.kt,GpuDriverHelper.kt}`, `src/yuzu/main_window.cpp`, `docs/user/ImportingSaves.md` (its Android section reads, verbatim, "TBD"); switchbrew.org `Filesystem_services` and `Flash_Filesystem`.

---

## 2. Recommendation

**Put one glob segment in the location `root`, expand it once in `RecipeBinder.bind`, store the resolved concrete path in the `Binding`. Change nothing else.**

```
"root": "files/nand/user/save/0000000000000000/*[!0]*"
```

With the root resolved at that depth, `unit: "folder"` already makes the **first segment under root the `<TITLE-ID>`** — which is the key the owner wants: one emulated game is one unit, and one game can be up to date while another is not.

### Why this and not the alternatives

**The profile id sits *above* the root, so it is consumed before anything downstream exists.** `Binding.dir` (`binding.dart:19`) is the only place it ever appears, and a `Binding` is local and never synced (`binding.dart:7`). Everything that travels is `rel`, relative to that root: `pusher.dart:97` puts `rel` in the zip, `:118` keys `GenMeta.files` by `rel`, `puller.dart:108` writes `p.posix.join(locationDir, rel)` on the other device. So:

- the unit key is `<TITLE-ID>` on every device — `units.dart:16-18` unchanged;
- `units/<recipeId>/<TITLE-ID>/` lines up across handhelds — `hub.dart:76,108` unchanged;
- the stored base key `'<hub>|<recipe>|<TITLE-ID>'` lines up — `sync_state.dart:183` unchanged;
- the payload re‑grouping guard at `puller.dart:280-281` passes on both sides;
- the install‑local profile id can never reach a generation, a base record, a backup path, a history folder or the log.

**Nothing in the write path changes.** `units.dart`, `checker.dart`, `hub.dart`, `gen.dart`, `pusher.dart`, `puller.dart`, `sync_state.dart`, `local_history.dart`, `path_guard.dart`, `game_fs.dart`, `hub_report.dart` and both screens are untouched. All seven `groupUnits`/`UnitScanner` call sites (`engine.dart:149`, `puller.dart:69,280,334`, `binding.dart:160`, `checker.dart:95`, wizard `:254`) receive an already‑resolved directory and keep running exactly the code they run today.

**It refuses instead of guessing, for free.** Two real profile directories both holding saves become two candidates, `withSaves.length > 1`, and `binding.dart:127` already returns `NeedsDiscovery('saves found in more than one place')`, shown by `bindLabel` (`engine.dart:74`) as "save location unknown". Zero new logic. The alternative — scoring candidates by newest mtime and picking one — is a guess about *where save data gets written*, it would be frozen into the stored `Binding` that `engine.dart:124-129` never re‑checks, and no UI can correct it. The upstream ambiguity (Android frontend hardcodes profile index 0 while the core uses `current_user`) is a reason to refuse harder, not a reason to guess.

**A free interop win.** Gen payloads for these recipes come out as `<TITLE-ID>/<name>.sav` inside the zip, which is byte‑for‑byte the layout the emulators' own "import saves" dialog demands. A hub generation is hand‑importable through the emulator UI with no repacking, and an emulator's own export zip is accepted by `Puller.pull(payload:)` as‑is.

### Rejected alternatives, briefly

- **Pin the root to a concrete `.../0000000000000000/<PROFILE-ID>`.** Parses on schema 1 today with zero code — and is correct on exactly one install, so it is unpublishable. Worse, `engine.dart:124-129` uses a stored binding unconditionally and nothing in `lib/` calls `clearBinding` (grep: only `test/save_sync_state_test.dart:27`), so a re‑rolled profile id freezes the device on a dead path forever, reported to the user as "open the game once".
- **A `unitDepth` field that skips a level.** It gets the key right and leaves the *source profile id inside every payload path*. Handheld B restores into a directory its own emulator never opens; push and pull both report success and the game offers a new game. That is the worst failure this app can produce.
- **A `unitPrefix` field that strips the segment.** Correct in principle and it covers device saves on day one, but it moves the per‑install segment into the scanner and the write path, and it writes the source install's profile id into `GenMeta` in the shared hub. It also claims `puller.dart` needs no changes, which is false: `puller.dart:69` re‑scans with the redefined scanner over an already‑prefixed `locationDir`, double‑stripping the `<TITLE-ID>` and making every pull over an existing save die at the `sameFiles` guard (`:74`).

### What this deliberately gives up

1. **Two real profiles both holding saves bind to nothing.** The whole recipe goes to `NeedsDiscovery`, including titles that were never ambiguous. Upgrade path, when it bites: reuse the existing `NeedsConfirm` screen with one row per candidate. Not now.
2. **The newer `save/account/<raw-uuid>/<title & ~0xFF>/0` layout is not covered.** A fork that migrates produces a unit key differing in the last two hex digits, which reads as a *second game* in the hub, and nothing detects it — there is no recipe fingerprint next to a generation. Mitigation is a pre‑ship check, section 7 slice 0.
3. **`play_time/<uuid>.bin` and `nand/user/Album` do not travel.** Hours played and in‑game screenshots are unrecoverable once gone. A per‑title unit cannot carry a single file that covers all titles. Say so in the UI rather than letting it surprise someone.
4. **Titles that bind save content to the account id still demand an in‑game re‑bind.** Outside what any file‑level tool can do. One sentence in the UI for these recipes.
5. **Eight recipe files for four emulators** (four account, four device), seven of them near‑copies. One recipe cannot list all four packages: `bind` fans candidates over packages × locations, so four installs with saves gives `NeedsDiscovery` on the exact handheld this was measured on — and two forks' copies of one title are two different saves anyway.

---

## 3. The schema change

Two edits. **No new field.**

### `lib/services/save_sync/recipe.dart:112`

```dart
static const supportedSchema = 2;
```

### `lib/services/save_sync/recipe.dart:280-283`

`_relative` is called from exactly one place, `recipe.dart:162`, for `root`. It currently delegates to `PathGuard.isSafeRelative`, which documents at `path_guard.dart:24-26` that **glob characters are allowed** — so a wildcard root parses today, `Binding.dir` concatenates it literally into `find` argv, nothing matches, and the owner is told to open the game once, forever. One rule closes that trap and enables the feature:

```dart
static String _relative(String s, String field, int schema) {
  if (!PathGuard.isSafeRelative(s)) throw RecipeError('$field "$s" must be a plain relative path');
  // ponytail: one globbed segment keeps expansion to a single listDir with a literal
  // prefix. More than one needs a recursive walk; add it when a recipe needs it.
  final globbed = s.split('/').where((seg) => seg.contains('*') || seg.contains('?')).length;
  if (globbed > (schema >= 2 ? 1 : 0)) {
    throw RecipeError('$field "$s": at most one globbed segment, and only at schema 2');
  }
  return s;
}
```

Note `[` is **not** treated as a glob character here, deliberately. Brackets are legal in real directory names and the wizard builds `root` by slicing a real on‑device path (`save_sync_recipe_wizard_screen.dart:277-284`), so rejecting `[` could break a live wizard‑written recipe for no gain.

The glob dialect is the one `include` already uses (`glob.dart:12-47`): `*` → `[^/]*`, `?` → `[^/]`, `[...]` a class, `[!...]` negated, `\x` literal. Only directory names are matched, and only the one globbed segment.

### Why the bump

A schema‑1 build receiving this recipe would bind to a literal `*` path and silently sync nothing. With `"schema": 2` it throws `RecipeTooNew` (`recipe.dart:85-92,142`) and the loader shows "needs a newer Retro Toolbox". It buys an honest message; an old build cannot corrupt the hub either way, because no local units means no push and a pull dies at `puller.dart:68`.

**One real gap to close in the same change:** `save_sync_provider.dart:366` merges `load.tooNew` but **not** `mine.tooNew`, so a *user‑written* schema‑2 recipe on an old build disappears from the screen with no problem row at all. One‑word fix, same line.

### Worked recipe — account saves

`save_recipes/switch-emu-eden.json`

```json
{
  "schema": 2,
  "id": "switch-emu-eden",
  "name": "Eden",
  "status": "draft",
  "packages": ["dev.eden.eden_emulator"],
  "locations": [
    { "area": "androidData", "root": "files/nand/user/save/0000000000000000/*[!0]*" }
  ],
  "unit": "folder",
  "include": ["*/**"],
  "deviceLocal": ["*/.yuzu_save_size"],
  "inProgress": [],
  "beforeRestore": [],
  "checks": [],
  "version": null,
  "nativeCloud": null
}
```

Line by line:

- **`root`** — `files/` is the app's external files dir (`DirectoryInitialization.userDirectory` is `getExternalFilesDir(null)`). `nand/user/save/` and the 16‑hex `0000000000000000` are constants. `*[!0]*` compiles to `[^/]*[^0][^/]*`: any name with at least one non‑`0` character. That is every real profile id and never the all‑zeros device directory. Scoping one level higher would drag `nand/user/Contents/registered` — the installed content library, gigabytes — into every push.
- **`unit: "folder"`** — first segment under the resolved root is `<TITLE-ID>`, so that is the unit key, the hub directory, and the base key.
- **`include: ["*/**"]`** — everything in the title directory **at any depth**. `.sav` filenames are chosen by the game, not the emulator, and nothing in the emulator source constrains them, so no filename logic is safe. `*/` + `**` is deliberate: `{folder}/*` would silently drop anything a title nests.
- **`deviceLocal: ["*/.yuzu_save_size"]`** — the one emulator bookkeeping dotfile, named explicitly. Not `*/.*`: a blanket dotfile exclusion would eat a save a game chose to name with a leading dot. Carrying this file would make two otherwise identical saves differ byte‑wise, which this branch's both‑sides‑changed detection would report as a conflict.
- **`status: "draft"`** — the first bind routes through `NeedsConfirm` (`binding.dart:109,125`) and the owner sees the real file list before anything syncs. No two‑device test has been run; `draft` is the honest value.
- **No `version`.** `from: "package"` would gate restores on the *emulator's* build, which has nothing to do with whether a save loads — the game decides that. `sameBuild` would block every pull between two handhelds one update apart.
- **No `inProgress`.** `Pusher.pack` already refuses while the package is running, and `Puller.pull` checks twice (`puller.dart:67,122`). Better than a filename guess for an app that holds its save files open.
- **No `checks`.** Nothing in the emulator source constrains `.sav` contents.

The other three are this file with `id`, `name` and `packages` swapped (`org.yuzu.yuzu_emu` for one; read the remaining two packages off the device).

### Worked recipe — device (console‑wide) saves

Plain schema 1 — the all‑zeros name is a constant, so it needs no glob, no new code and no bump.

```json
{
  "schema": 1,
  "id": "switch-emu-eden-device",
  "name": "Eden (console-wide saves)",
  "status": "draft",
  "packages": ["dev.eden.eden_emulator"],
  "locations": [
    { "area": "androidData", "root": "files/nand/user/save/0000000000000000/00000000000000000000000000000000" }
  ],
  "unit": "folder",
  "include": ["*/**"],
  "deviceLocal": ["*/.yuzu_save_size"]
}
```

A title is account‑save **or** device‑save, never both, so a `<TITLE-ID>` appears under exactly one of the two recipe ids and the namespaces never collide. This also covers a case the emulators' own Android export silently skips, since `getSavePath` always requests `SaveDataType::Account`.

---

## 4. Second handheld, several profiles, none

### A second handheld with its own profile id

Works, and never learns the first device's id.

1. Handheld A expands its glob to its own 32‑hex directory and stores that concrete root in its local `Binding`.
2. A pushes `units/switch-emu-eden/<TITLE-ID>/<gen>.zip`, entries `<TITLE-ID>/<name>.sav`, `GenMeta.files` keyed the same way, `GenMeta.unit` = `<TITLE-ID>`.
3. Handheld B runs the same recipe, expands the glob against *its own* data folder, binds to *its own* 32‑hex directory.
4. B's unit key is also `<TITLE-ID>`, so the hub row, the gens and the base key `'<hub>|switch-emu-eden|<TITLE-ID>'` all line up.
5. The pull joins B's own `locationDir` with the gen's rel (`puller.dart:108`) and writes into B's profile directory. `puller.dart:104-105` creates `<locationDir>/<TITLE-ID>` with `makeGameDir` — one level, which is all `makeGameDir` does.

The only place A's profile id ever existed is A's own stored `Binding`, which is local and never synced.

### A handheld with several profile directories

- **One profile holds saves, the rest are empty** (the common case: a profile created in the UI and never used). Empty candidates are dropped at `binding.dart:119`, `withSaves.length == 1`, it binds correctly. **Zero new code.**
- **Two or more hold saves.** `binding.dart:127` returns `NeedsDiscovery('saves found in more than one place')`; the screen shows "save location unknown (saves found in more than one place)". Nothing syncs for that recipe until the owner acts. Blunt but never wrong — and the state is real, not theoretical: up to 8 profiles are supported and the project's own release notes warn that profile directories multiply and get mangled after updates.
- **The all‑zeros directory never competes**, because `*[!0]*` excludes it. It gets its own recipe id, its own unit namespace, and syncs in parallel.

### A handheld with none

Three distinct cases, three different messages, all correct:

- **Emulator not installed** — `fs.installed` is false for every package, `binding.dart:95` returns `NotInstalled`, the screen says "not installed". This is the paired handheld today.
- **Installed, never launched** — `nand/user/save/0000000000000000/` does not exist, the glob matches nothing. **The expansion must then return the candidate with the glob left literal**, not drop it: `fs.isDir` is false for a path containing `*`, so `binding.dart:106` (or `:140`) gives `FolderMissing` → "open the game once so it creates its save folder". That is the truth. Dropping the candidate instead would leave `candidates` empty and throw `StateError` on `candidates.first` at `binding.dart:133` or `open.first` at `:140`.
- **Installed and launched, no game saved yet** — the profile directory exists and is empty. `withSaves` is empty, `existing.length == 1`, `binding.dart:139` returns `Bound`. Correct: a device that has never played the game is the reason to sync in the first place, and the code already says so in a comment at `:128-131`.

Two rough edges, worth stating rather than coding around: `test -d` is false on `EACCES` as well as on absence, so a refused device re‑probes on every status (shell calls, never data); and `listDir` returns `const []` when its shell command fails (`game_fs.dart:101`), so a refused listing during expansion reads as "no profile directory yet" and the owner is told to open the emulator once.

---

## 5. What it does to hubs that already exist

**Nothing.** That is the main reason to put the change in the root rather than in the unit key.

- **No existing unit key changes, no existing root changes.** All nine shipped recipes have literal roots (`files`, `files/Saves`, `files/default`, …) and stay at `"schema": 1`, parsed by the identical code path — `supportedSchema` is compared with `>`.
- **Nothing is orphaned.** `units/<recipeId>/<unitKey>/`, `backups/<device>/<recipe>/<unit>/`, bases at `'<hub>|<recipe>|<unit>'` and local history folders all keep their names. This matters because orphaning is permanent: `HubBackend` has no rename, and `Hub.prune` only deletes non‑head gens *inside* one unit directory — nothing ever removes a unit directory, so an orphan would keep appearing in `Hub.units()`, keep producing a row via `engine.dart:150`, and keep offering a pull that then fails at `puller.dart:281`.
- **No forced divergence.** No unit loses its base or its heads, so nothing plans as a parentless push.
- **`Hub.format` and `GenMeta.format` stay 1.** `gen.dart:68` is a strict `j['format'] != format` — bumping it would make **every generation in every existing hub unreadable.**
- **The emulator recipes are new ids** with nothing in the hub yet, so their blast radius is empty by construction. Which is exactly why the key rule has to be right in their *first published version*: there is no recipe fingerprint anywhere, so nothing can detect or repair a key change after the fact. Changing it later means a new recipe id and hand‑moving data.

Three behaviour changes that do touch existing state:

1. **Old builds refuse schema‑2 recipes.** A build at `supportedSchema = 1` that receives one through `hub.recipes()` or the catalog throws `RecipeTooNew`, shows "needs a newer Retro Toolbox", and never binds, scans, pushes or pulls it. A fleet mid‑upgrade simply has the emulators syncing on updated handhelds and not on the others — no split root, no mixed keying, no silent half‑sync. That is what the bump buys.
2. **A hand‑written user recipe with `*` or `?` in `root`** parses today and is silently dead. After the tightened `_relative` it fails to parse with a visible message. User recipes win over bundled and hub copies (`save_sync_provider.dart:395`), so nothing auto‑repairs it; the fix is adding `"schema": 2` to that file. One line in the release note.
3. **The re‑bind on a dead root** (section 7, slice 2) fires only when a stored binding's directory is no longer a directory. For every current recipe the root is a fixed path that exists whenever the game is installed, so it never fires for them. It fires exactly where it is needed.

---

## 6. Local history as one zip per entry

**Do it only after the pull has succeeded.** The entry is mutable, shell‑written and rollback‑read for the whole duration of a pull; afterwards it is pure archive and nothing in the app ever opens it again.

### What depends on the entry being an open folder

Every reader is in `puller.dart`, and **every one of them runs only while `<entry>/.pull.json` exists**:

- `:86-89` snapshot then hash‑verify via `fs.sha256` over `entry/rel`;
- `:91-99` the journal, written with `dart:io` and rewritten mid‑pull on every `_aside`;
- `:111` rollback `fs.replace(entry/rel, target, had)`;
- `:114-120` each unit file the gen lacks is **`mv`'d into** the entry, over its identical snapshot copy — a move, not a copy, so the mtime survives (asserted in `test/save_sync_puller_test.dart:219-220`);
- `:155-160` `recover` walks `history.root/<recipeId>/*/` and picks directories containing `.pull.json`;
- `:193-230` the recover restore: `fs.exists`, `_holds` hashing, `fs.replace` and `fs.moveTo` out of the entry;
- `:198-205` `expected()` infers "the aside move happened, or a recover already put it back" from **the copy being gone** from the entry.

Plus two things outside the code: `fs.copyOut`/`moveTo`/`replace`/`sha256` are shell `cp`/`mv`/`sha256sum` over real paths and **cannot read a zip member**; and the user is handed the entry path by `PullRolledBack.toString` (`errors.dart:32`) and both stuck messages (`puller.dart:211,241`), surfaced as status notes at `engine.dart:140-146`. `local_history.dart:7-8` states the point: "on shared storage, so a file manager can reach it."

All of that stops at **`puller.dart:135`, `await journal.delete()`**.

### The change

After `puller.dart:135` (and after `:231` for the `before-recover` entry of a successful recover), fold `<entry>/` into `<entry>.zip` and delete the folder:

```dart
// ponytail: streams to disk. Do NOT copy pusher.dart:99 (ZipEncoder().encodeBytes)
// here — it holds the whole archive in RAM, and emulator saves are the large case.
await (ZipFileEncoder()..zipDirectory(Directory(entry), filename: '$entry.zip')).close();
await Directory(entry).delete(recursive: true);
```

`archive: ^4.0.7` is already in `pubspec.yaml`. Then exactly two lines in `local_history.dart`:

- **`:41`** must count files as well as directories, taking `p.basenameWithoutExtension` for the name. **Without this, `trim` silently stops seeing zipped entries and history grows forever on shared storage with no error anywhere** — `entries()` is only called from `trim()` (`:48`), so this is the whole exposure.
- **`:49`** must delete a `File` or a `Directory`.

`puller.dart:155-159` needs no change: it already requires `e is Directory`, so a zipped entry is invisible to `recover` — which is exactly right, because a zipped entry is a finished pull.

**Nothing needs an unpack path**, because no code reads a completed entry. If a user‑facing "restore from history" is ever wanted, that is the one new reader and it is the same shape as `restoreBackup`: extract to `stagingRoot` (already inside the `PathGuard` roots, `engine.dart:110-114`) and reuse `Puller.pull(payload:)`, which already takes a zip.

Keep the stamp first in the name (`<stamp>-<reason>.zip`): `local_history.dart:41-42` sorts by name and reverses, and `gen.dart` parses the stamp at the start of such names.

### What zipping at snapshot time would cost, for the record

`snapshot` would have to copy to staging, hash in Dart and encode; `_aside` and `puller.dart:119` would re‑encode the whole archive per file (the archive package cannot append in place); `_holds`, `asideCopies` and the restore at `:214-230` would each need a decode‑and‑extract step; `recover` would need its own staging directory, which it does not have today; `expected()` would need a journaled put‑back list, because a zip member never disappears; and the user loses the file‑manager escape hatch **exactly in the failure case where the app tells them to go look.** Not worth it.

---

## 7. Build order

Five slices. Each ships on its own.

### Slice 0 — on‑device checks, no code

Nothing below is worth publishing until these are answered. All run on the one handheld that has the emulators.

1. **Copy a `<TITLE-ID>` directory from one install's profile directory into another install's profile directory and launch it.** This validates the entire premise — that the lookup is pure string formatting with no index — which is currently source reading, not measurement. **Gate: no recipe goes from `draft` to `verified` until this passes.**
2. `ls files/nand/user/save/account/` for each of the four packages. If it exists on any install, that fork has migrated to the newer layout and this design does not cover it — stop and write a separate recipe id for it.
3. `ls files/nand/user/save/0000000000000000/00000000000000000000000000000000/` for each. If empty everywhere, skip slice 4 entirely.
4. Grep the real profile id, **and its byte‑reversed form**, across the `.sav` files in one title directory. A hit means some titles will need an in‑game re‑bind after a transfer, which is a sentence in the UI, not a code change.
5. Confirm `files/nand/user/Album`, `files/nand/user/Contents/registered` and `files/temp/` exist where predicted — cheap confirmation that these forks match the source that was read.

### Slice 1 — schema 2 and glob expansion

- `lib/services/save_sync/recipe.dart` — `supportedSchema` 1 → 2 (`:112`); keep the parsed `schema` and pass it into `_relative` (`:162`, `:280-283`); the validation rule from section 3. **~6 lines.**
- `lib/services/save_sync/binding.dart` — one new private method on `RecipeBinder`:

  ```dart
  // ponytail: one globbed segment, expanded here so nothing downstream ever sees a glob.
  // Zero matches keeps the literal root: isDir is false for it, so bind lands on
  // FolderMissing ("open the game once"), and candidates is never empty.
  Future<List<Binding>> _expand(Binding b) async { ... }
  ```

  splits `root`, finds the one segment containing `*` or `?`, calls `fs.listDir` on the literal prefix once, keeps entries where `e.isDir && Glob(seg).matches(e.name)`, and returns one `Binding` per match with a **concrete** root. `candidates` at `:97-100` becomes a flattened fold over `_expand`. Everything below — the single‑candidate fast path at `:103-109`, `withSaves`, `NeedsDiscovery` at `:127`, `NeedsRoot`, `FolderMissing` — is unchanged. Imports `glob.dart`. **~22 lines, no new `GameFs` primitive.**
- `lib/providers/save_sync_provider.dart:366` — merge `mine.tooNew` as well as `load.tooNew`. **1 line.**
- `test/save_sync_binding_test.dart` — using the real‑filesystem harness already in that file: two profile directories where one has files → binds that one; both have files → `NeedsDiscovery`; neither exists → `FolderMissing` and nothing stored. Plus one parse test that a `*` in `root` at schema 1 is rejected. **~35 lines.**
- `test/save_sync_units_test.dart` (or the binding test) — **two regression tests the design must not lose**: that a pushed generation's paths never contain a 32‑hex segment, and that a title present under two profile directories does not produce a single merged unit.

**Unchanged in this slice and every later one:** `units.dart`, `checker.dart`, `hub.dart`, `gen.dart`, `pusher.dart`, `puller.dart`, `sync_state.dart`, `local_history.dart`, `path_guard.dart`, `game_fs.dart`, `hub_report.dart`, `save_sync_screen.dart`, `save_sync_recipe_wizard_screen.dart`.

### Slice 2 — re‑bind on a dead root

`lib/services/save_sync/engine.dart:124-129`: when a binding is stored, reachable, and `!await fs.isDir(stored.dir(paths))`, call `state.clearBinding(r.id)` and fall through to `RecipeBinder.bind`. **~3 lines.**

First caller of `clearBinding` in `lib/`. It is the only path by which a re‑rolled profile id, or a profile directory created later, ever becomes visible — and it fixes the same stale‑root trap for all nine existing recipes, where today the symptom is every unit planning as `missingLocally` and the pull refused at `puller.dart:68` with "open the game once" while the real cause is a dead root.

### Slice 3 — the account recipes

`save_recipes/switch-emu-<fork>.json` × 4. **Add them one at a time**, each after slice 0's checks pass for that package, not all four blind. `save_sync_recipe_bundle_test.dart` already parses everything in that folder.

### Slice 4 — the device recipes

`save_recipes/switch-emu-<fork>-device.json` × 4, schema 1, literal all‑zeros root. **Only if slice 0 check 3 found anything.** No code at all.

### Slice 5 — history as zip

`lib/services/save_sync/puller.dart` (after `:135` and after `:231`) and `lib/services/save_sync/local_history.dart:41,49`. Independent of everything above; ship it whenever. **~12 lines.**

---

## 8. What must NOT be synced from these emulators

The recipe root scopes to `nand/user/save/<16-hex>/<profile>` and nothing above it, which excludes all of this by construction. Listed so nobody later "improves" the root upward.

**Device‑specific — moving it breaks the target handheld:**

| Path | Why |
|---|---|
| `gpu_drivers/`, `files/gpu/vk_file_redirect/`, internal `filesDir/gpu_driver/` | Custom driver packages tied to the exact SoC. A reliable way to produce boot crashes on a different device. |
| `shader/<16-hex>/vulkan.bin`, `vulkan_pipelines.bin` | Compiled against one driver + GPU pair. One fork already wipes this automatically on a driver change. |
| `config/` (`<name>.ini`, `custom/<name>.ini`, `input/`) | Stores the NAND, SD, load, dump, TAS and screenshot **directory paths** plus controller bindings. Syncing it rewrites the target's storage paths and input mapping. |
| `log/`, `crash_dumps/` | Diagnostics. |
| `icons/` | Desktop shortcut icons; dead weight on a handheld. |

**Large and re‑obtainable — and the first one is the real trap:**

| Path | Why |
|---|---|
| `nand/user/Contents/registered`, `nand/user/Contents/placehld` | **Installed games, updates and DLC.** Created by `BISFactory` under `nand/user/` — the *same parent as the saves*. A root scoped to `nand/user` instead of `nand/user/save` drags the whole content library, gigabytes, into every push. |
| `nand/system/Contents/registered`, `/placehld` | Firmware images, hundreds of MB, re‑installable. |
| `shader/`, `cache/` | Grow without bound as you play. |
| `sdmc/` | The emulated SD card. External mod frameworks install here. |
| `load/<TITLE-ID>/<mod>/{exefs,romfs,romfs_ext}` | Mods. Not saves — but worth one UI sentence: a save made with a mod active may misbehave without it. |
| `dump/`, `tas/` | Tooling output. |

**Keys:** `keys/` (`prod.keys`, `title.keys`) — console‑dumped material with nothing to do with saves. Out of a save recipe on both correctness and legal grounds.

**Save‑shaped but not progress** — all three are already excluded by the root, but only because the profile segment is anchored to a name that is not `cache` and the others sit under different parents:

- `nand/user/save/cache/<TITLE-ID>/` — `SaveDataType::Cache`; the FS API has a `DeleteCacheStorage` command for it.
- `nand/temp/0000000000000000/<user>/<TITLE-ID>/` — temporary saves; a different space, no `save/` segment.
- `nand/system/save/bcat/<16-hex>/` — downloaded event/delivery data.

**Inside the save directory, excluded by `deviceLocal`:** `.yuzu_save_size` — written by `WriteSaveDataSize`, emulator bookkeeping, not game state. Carrying it makes two identical saves differ byte‑wise and feeds a false "both sides changed".

**Does not travel, and nothing on screen says so yet** — this is the one gap worth a UI sentence rather than a recipe:

- `play_time/<32-hex>.bin` — a headerless array of `{program_id, seconds}` records flushed every 30s, **one file for all titles** and keyed by the same per‑install UUID. A per‑title unit cannot carry it without merging records. Hours played are unrecoverable.
- `nand/user/Album` — the in‑game screenshot album, created by `BISFactory`. Small, irreplaceable, and almost always forgotten by save‑sync tools. Its internal structure was not established; if it ever matters it is its own recipe with a literal root, which works on schema 1 today.

---

## Appendix — measured on hardware after this document was written

The decisive unknown above was whether the profile id is written *inside* the
save files, which no file-level tool could work around. It is not.

Four title directories were pulled off a real install and every file in them
searched for the install's profile id in six encodings: the 16 raw bytes as the
directory name prints them, those bytes reversed, and the hex as ASCII in upper
and lower case both ways round.

```
files inspected:                28   (4 title directories)
files containing the profile id: 0
```

So only the *directory name* carries the profile. The bytes a game writes do
not, which is what makes re-deriving the profile directory on the receiving
install a sound approach rather than a hopeful one.

Two further measurements from the same install:

- The all-zeros sibling directory **is populated** — it holds a title. Device
  saves are not hypothetical here, and a recipe that only covers the real
  profile would silently leave that progress behind.
- No `.yuzu_save_size` file was present in any of the four title directories,
  so the bookkeeping file the source defines is not always written.

Still not measured: whether an install actually reads a title directory copied
in under a different profile id. That needs the emulator launched, which is a
person's job, not a shell's.

### Slice 0, as answered on hardware

Four of the five checks are done. The one that is left needs the emulator
launched, which a shell cannot do.

| # | Check | Result |
|---|---|---|
| 1 | A title directory copied under another install's profile is read | **not done** — needs the game launched |
| 2 | `save/account/` exists on any fork | **no**, on all four. None has migrated to the newer layout, so this design covers all of them |
| 3 | The all-zeros profile holds titles | **yes**, it holds one. Device saves are real here, so the slice that covers them is not optional |
| 4 | The profile id appears inside the save files | **no** — 28 files across 4 title directories, six encodings, zero hits |
| 5 | The predicted directories exist | `nand/user/Contents/registered`, `sdmc/` and `shader/` exist, so the never-sync list is about real paths on this device. `nand/user/Album` and `temp/` do not exist on this install |

Also measured: exactly one real profile directory beside the all-zeros one, so
the glob resolves to a single match here and the several-profiles path is not
the common case on this hardware.
