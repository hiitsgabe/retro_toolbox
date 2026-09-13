# Slice 4, Addon and Accounts: implementation plan

> **For whoever executes this:** MANDATORY SUB-SKILL: use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute task by task. The steps use checkboxes (`- [ ]`) for tracking.

**Goal:** take every secret out of the file the user shares, and replace today's single catalog source with an ordered list of addons, whose order is the tiebreaker that slice 3 already knows how to consume.

**Architecture:** two halves that meet at the end. The first is the vault: a `SecretVault` interface with two implementations, the system one and the fallback one, with a migration that runs once and empties the secrets out of `shared_preferences`. The second is the addon: an `Addon` with its own id, an ordered list that replaces the single `catalogSourceUrl`, and a `CatalogService` that merges N addons into a `Map<String, Console>` summing URLs per console instead of fighting over id. The two meet because the credential is keyed by `addon:<id>/<console>`, and that is what makes two addons serving the same console not share the same token.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod: ^2.6.1`), `flutter_test` without mockito, constructor injection. **One new dependency:** `flutter_secure_storage`. It is the only one in the whole slice.

**Base commit:** `ef5ee57`. The final Task measures the whole slice against that hash, so it is immutable while the slice is open: no rebase, amend or filter-branch that reaches it.

**Baseline measured at `ef5ee57`:** `flutter test` gives `+340`, zero failures. `flutter analyze` gives `22 issues found`, being 21 `info` and **one `warning`** (`unnecessary_non_null_assertion`, `test/webdav_server_test.dart:69:100`), zero errors. All 22 are pre-existing. **There is no longer "the usual failure":** the `-1` that slices 1, 2 and 3 carried was fixed in `5d21b14`. Any failure, in any Task, is your regression.

---

## Two decisions locked by the user

These two are neither mine nor yours. They were decided on 2026-09-11 and hold for the whole slice.

### First: the scope is security **plus** multi-addon

Item 4 of the decomposition (`docs/stremio-de-jogos-design.md:600`) lists only "accounts screen, token migration to secure storage, fix of section 6.3, and keeping the RTS emitting the extended format". Section 9 of the UI spec describes a lot more: addon list, per-addon detail, coverage, consolidated Accounts, and draggable priority. The locked scope is **the union of the two**. If you think a Task is outside item 4 of the decomposition, it probably is, and it is still yours.

Two paragraphs of section 9 do **not** enter, and it is better to say so now than to discover it in review:

| What section 9 says | Where it lands |
| --- | --- |
| "**Real-Debrid is not an addon, it is an account.** It shows up in Accounts and never in the addon list" | slice 6. What this slice leaves ready is the `SecretRef.debrid(provider)` key, with a test, and nothing more. There is no torrent addon for the debrid to resolve, so a Real-Debrid line in Accounts today would be a form that feeds nobody. |
| "**Coverage**: which consoles it serves **and how many items in each**" | left out with no date. The count costs one listing request per console, and the reason is written in the opening of Group 5 and in Task 22. |

Everything else in section 9 belongs to this slice.

### Second: with no keyring, the vault falls back to plaintext, warning

`flutter_secure_storage` on Linux requires `gnome-keyring` or KWallet alive on the D-Bus. On a server Linux that does not exist, and the read raises. The decision is to **keep today's behavior in that case**, with a warning on the screen, instead of disabling the field or encrypting to a file.

**The consequence of that decision has to be visible in the code and in the tests, otherwise the slice becomes makeup.** Section 6.3 of the spec has two objectives, and only one survives unconditionally:

| Objective of 6.3 | Always holds? | Why |
| --- | --- | --- |
| Take the secret out of the **shareable JSON** (`auth.token`) | **Yes, on every platform** | it is the file the user sends to someone else, and nothing encrypts it |
| Encrypt the secret **at rest** | No, it is best effort | with no keyring, the fallback vault writes in plaintext |

Never write, in a commit, report or comment, that "6.3 is fixed" without separating those two halves. The first is the one that truly closes the leak; the second is defense in depth that sometimes is not there.

---

## Before starting: what already exists, measured

Everything in this section was checked by running `grep` and reading the file at `ef5ee57`, not deduced. The line numbers are hints, not truth: if one does not match, the file moved, and the content is what rules.

### Today's inventory of secrets

Every secret of the app lives in a **single key** of `shared_preferences`, `app_settings`, as plaintext JSON (`lib/services/settings_service.dart:8` and `:33`).

| Secret | Field | Serialized in | Typed in |
| --- | --- | --- | --- |
| Per-console token | `BaseSettings.authToken` | `settings_model.dart:158` | `console_auth_setting.dart` |
| IA S3 access key | `AppSettings.iaAccessKey` | `settings_model.dart:86` | `ia_credentials_setting.dart` |
| IA S3 secret key | `AppSettings.iaSecretKey` | `settings_model.dart:87` | `ia_credentials_setting.dart` |
| IA cookies | `AppSettings.iaCookies` | `settings_model.dart:88` | `ia_credentials_setting.dart` |

There are **four**, not two. The `iaCookies` is easy to forget because the spec does not cite it: it is the "logged-in-user / logged-in-sig" pair that unlocks restricted download, and it is a credential just as much as the others.

### The four sites that read the token from inside the file

Section 6.3 of the spec says that "two changes close the hole". There are four:

| # | File | What it does |
| --- | --- | --- |
| 1 | `lib/utils/network.dart:41` | `final token = tokenOverride ?? auth['token'] as String?;` |
| 2 | `lib/services/task_queue_service.dart:20` | the whole chain, literal as the spec cites it |
| 3 | `lib/screens/tinfoil_server_screen.dart:91` | decides whether the console "has auth" |
| 4 | `lib/screens/setup_wizard_screen.dart:392` | same, same expression |

The last two do **not** build a header: they only decide whether the UI shows the console as authenticated. They go unnoticed by a `grep` for `buildConsoleAuthHeaders`, which finds only four callers and none of them. The `grep` that finds the four is:

```bash
grep -rnE "auth\??\['token'\]" lib/
```

The `-E` is mandatory. Without it the `grep` is BRE, the `\?` becomes a quantifier and the second `?` becomes a literal, and then the pattern starts to require a `?` after `auth`: it finds the three that write `auth?[` and lets through precisely `network.dart:41`, which writes `auth['token']` without `?` and is the site that 6.3 lists. Measured with the four still in place: BRE found three, `-E` found four.

If you fix only the first two, the app keeps saying "this console has auth configured" based on a field that nobody else reads to authenticate. It is not a leak, it is an interface lie, and it is worse to find later.

**And the third sentence of 6.3 is empty today, measured.** The spec says "On install, if the JSON comes with `auth.token` filled, the app moves it to `flutter_secure_storage` and zeroes it in the saved file. **On export, remove it**". The install half is Task 8. The export half has nowhere to live: **the app does not export a catalog**. The only `FilePicker.platform.saveFile` in `lib/` writes the JDKV server's `webdav.json` (`jdkv_server_screen.dart:181`), which is another file and another screen. Do not write a Task for that, and do not report the export as done nor as pending: report that there is no catalog export path at `ef5ee57`, and that whoever creates one later inherits the obligation.

### Today's catalog source is **a single one**

This is the fact that gives the slice its size.

- `CatalogService.setCatalogFromJson` (`catalog_service.dart:109-118`) **overwrites** `config/consoles.json`. Installing a catalog erases the previous one.
- `AppSettings.catalogSourceUrl` (`settings_model.dart:24`) is a `String?`, a URL, not a list.
- `getConsoles` (`catalog_service.dart:20-48`) reads exactly one file, with precedence user config, then embedded asset, then nothing.

There is today **no** notion of an ordered list of sources, priority or drag, anywhere in `lib/`.

### The console id comes from the name, and that is why it collides

`_nameToId` (`catalog_service.dart:61-63`) derives the id from the console's **name**. With a single addon this never mattered. With N, two addons that serve "Nintendo 64" produce the same id `nintendo_64` and one overwrites the other in the `Map<String, Console>`.

**The way out is not to invent an id namespace.** The spec already decided, in `design.md:420-422`: "Someone installs your RTS's URL as an addon and, if it has that console's pack, your local folder shows up as a source in its grid". "In **its** grid" means: the console stays a single one, and the addons are sources of that console. It is the same "one game, many sources" from slice 3, one level up.

This works out well because `Console.urls` **already is** `List<String>` (`console_model.dart:4`), and `Console.url` is just the first (`console_model.dart:51`). Merging two consoles of the same id is concatenating `urls`, not inventing a type.

What **cannot** be merged is the credential, and that is why the vault key is `addon:<id>/<console>` and not `console:<id>`: two addons serving Nintendo 64, each with its own login, keep separate tokens. Section 6.2 of the spec already writes the key in that format.

### The socket that slice 3 left ready

Do not reimplement this, **wire it up**:

- `planFromEntries` (`lib/services/source_pick_service.dart:50-55`) already takes `List<String> sourcePriority = const []`, and `_priorityRank` (`:156-159`) already uses it. **Nobody passes anything today**, so the axis exists and is always empty.
- `MatchedSource.sourceId` and `SourcePick.sourceId` are already fields, not enums (`source_pick_model.dart:35-38`).
- Today the value is always `kBuiltinSourceId`, the constant `'listagem'` (`source_pick_model.dart:17`), filled in a single place: `pack_grid_provider.dart:75`.

The draggable priority of section 9 is exactly what fills `sourcePriority`. The comment in `source_pick_model.dart:35` already says "in this slice it is always `kBuiltinSourceId` and in slice 4...". That slice is this one.

### The RTS is the producer of the same format

`RtsServerService.consoleJson` (`lib/services/rts_server_service.dart:13-20`) builds the console object that the same binary's `Console.fromJson` consumes. Producer and consumer are the same app, so diverging is a bug with a name (`design.md:416-419`). It does **not** emit `auth`, and that is correct: a local server does not ask for a credential. The contract Task exists so that this stays true, not to change it.

### Commands for this repository

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test 2>&1 | tr '\r' '\n' | tail -5
flutter analyze
```

The `tr '\r' '\n'` is not decoration: the `flutter test` output uses carriage returns and vanishes in the pipe without it.

**Never run `dart format`.** The repository is not clean under the current tall-style formatter: 106 of 217 files would change. Running it creates diff noise that buries your change.

**There is not a single `export` in `lib/`.** Check: `grep -rln "^export " lib/` comes back empty. A transitive import never resolves, so every new file imports explicitly everything it uses. This is the most repeated defect of the three previous slices.

### Commit rules

- `git add` always by explicit path. **Never `git add -A`, never `git add .`, never `git commit -a`**: the `pubspec.lock` stays permanently dirty because the local Flutter 3.35.7 resolves older transitive versions.
- Each Task brings **two** messages, `test(<scope>):` and `feat(<scope>):`, with the same descriptive text. Never a single one.
- A commit touches **either** only `lib/` **or** only `test/`. Never both.
- No emoji, no dash, no co-authorship.

---

## File structure

**New** files:

| File | Responsibility | Pure Dart? |
| --- | --- | --- |
| `lib/models/secret_ref.dart` | the vault keys, in a single place | yes |
| `lib/services/secret_vault.dart` | the vault interface, plus the in-memory implementation | yes |
| `lib/services/prefs_vault.dart` | the fallback vault, in `shared_preferences` | no, uses plugin |
| `lib/services/secure_storage_vault.dart` | the system vault, plus the availability probe | no, uses plugin |
| `lib/services/secret_migration.dart` | the one-time move from `app_settings` to the vault | yes |
| `lib/providers/vault_provider.dart` | which vault the app uses, and the warning when it is the fallback | no |
| `lib/models/addon_model.dart` | `Addon` and the ordered list | yes |
| `lib/services/addon_store.dart` | persist, install, remove and reorder addons | no |
| `lib/services/console_merge.dart` | merge N catalogs into a `Map<String, Console>` | yes |
| `lib/providers/addon_provider.dart` | the addons, the derived priority, the merged one, the accounts and the fetcher | no |
| `lib/services/addon_install.dart` | download a url, harvest the tokens and install the addon | no, uses `dart:io` |
| `lib/utils/console_auth.dart` | the auth questions the screens ask, outside them | yes |
| `lib/screens/addons_screen.dart` | the addon list, with drag | no |
| `lib/screens/addon_detail_screen.dart` | one addon: account, coverage, priority, remove | no |
| `lib/widgets/settings/vault_warning.dart` | the warning that this device does not encrypt | no |

Fifteen new files in `lib/`.

**Modified** files in `lib/`, twenty-four:

| File | What changes |
| --- | --- |
| `lib/utils/network.dart` | `buildConsoleAuthHeaders` loses the file term |
| `lib/services/task_queue_service.dart` | the chain loses the middle term |
| `lib/screens/tinfoil_server_screen.dart` | the "has auth" predicate stops reading the file |
| `lib/screens/setup_wizard_screen.dart` | same |
| `lib/services/catalog_service.dart` | installs clearing `auth.token`, reads N addons, and `_parseConsoles` becomes public |
| `lib/services/settings_service.dart` | the key becomes public, and the console token becomes the pair's token |
| `lib/models/settings_model.dart` | the four secrets leave the `toJson` |
| `lib/models/console_model.dart` | `hasTokenAuth` starts to see `requires_token`, and gains `withUrls` |
| `lib/models/game_model.dart` | the game starts to know which addon it came from |
| `lib/models/source_pick_model.dart` | loses the `kBuiltinSourceId`, which was the single source |
| `lib/services/source_pick_service.dart` | the priority starts coming from the addon order |
| `lib/providers/settings_provider.dart` | secret write and read go through the vault |
| `lib/providers/pack_grid_provider.dart` | the source stops being always `kBuiltinSourceId` |
| `lib/providers/catalog_provider.dart` | fetch per source, each with its own auth |
| `lib/providers/download_provider.dart` | the header comes from the (addon, console) pair auth |
| `lib/providers/tinfoil_server_provider.dart` | loses the token parameter that became a vault query |
| `lib/providers/fbi_server_provider.dart` | same |
| `lib/screens/home_screen.dart` | passes the user's priority to the source pick |
| `lib/screens/game_detail_screen.dart` | same, and shows the addon name instead of the id |
| `lib/screens/menu_screen.dart` | the Tools tiles become a top-level function and gain "Addons" |
| `lib/widgets/settings/accounts_setting.dart` | becomes the consolidated view, with one line per (addon, console) pair and the vault warning |
| `lib/widgets/settings/catalog_source_setting.dart` | becomes the door to the addons screen |
| `lib/widgets/settings/console_auth_setting.dart` | the form becomes the (addon, console) pair's, and warns when it writes |
| `lib/widgets/settings/settings_content.dart` | passes the addon to the form |

Outside `lib/`: `pubspec.yaml` gains `flutter_secure_storage`, and `pubspec.lock` changes along with it.

In `test/`, thirty-two files, of which **five are old and only modified**: `test/game_detail_screen_test.dart`, `test/menu_grid_test.dart`, `test/pack_grid_provider_test.dart`, `test/pack_grid_test.dart` and `test/source_pick_service_test.dart`. Two of the new ones do not end in `_test.dart` on purpose, because they are shared help with no `main`: `test/vault_contract.dart` and `test/support/fake_addon_store.dart`.

`lib/services/rts_server_service.dart` does **not** change. It gains a contract test, not an alteration.

---

## Group 1: the vault

Five Tasks. The order exists so that the new plugin arrives as late as possible: Tasks 1, 2 and 5 are pure Dart and testable with no platform at all, Task 3 uses only the `shared_preferences` already in the project, and only Task 4 touches `flutter_secure_storage`.

The vault enters through a four-method interface, with three implementations: memory (tests), `shared_preferences` (the plaintext fallback of the locked decision) and the system keyring. The three pass through the **same contract file**, `test/vault_contract.dart`, because the point of the locked decision is that the fallback behaves the same as the real vault in everything except being encrypted.

### Task 1: `SecretRef`, the vault keys

**Files:**
- Create: `lib/models/secret_ref.dart`
- Test: `test/secret_ref_test.dart`

It looks too small for its own Task, and that is on purpose. The key is the only thing in the slice that **cannot change later**: it ends up in the user's operating system keyring, outside the app's control. A format mistake here becomes an orphan credential on the machine of whoever updates, and there is no migration that fixes it without guessing.

The format comes from section 6.2 of the architecture spec, which already writes it: `addon:<id>/ultranx`, `ia/cookies`, `debrid/realdebrid`.

- [ ] **Step 1: Write the failing test**

Create `test/secret_ref_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';

void main() {
  test('token key carries the addon and the console, in that order', () {
    expect(SecretRef.addonToken('ultranx', 'nintendo_64'), 'addon:ultranx/nintendo_64');
  });

  test('two addons serving the same console do not share the key', () {
    // This is the case that justifies the whole key. The console id comes from
    // its NAME (`catalog_service.dart:_nameToId`), so two addons that serve
    // "Nintendo 64" both produce `nintendo_64`. If the key were console-only,
    // the second's login would silently erase the first's.
    expect(
      SecretRef.addonToken('ultranx', 'nintendo_64'),
      isNot(SecretRef.addonToken('meu_rts', 'nintendo_64')),
    );
  });

  test('the Internet Archive keys are the three from section 6.2', () {
    expect(SecretRef.iaAccessKey, 'ia/accessKey');
    expect(SecretRef.iaSecretKey, 'ia/secretKey');
    expect(SecretRef.iaCookies, 'ia/cookies');
  });

  test('debrid is keyed by provider, because there will be more than one', () {
    expect(SecretRef.debrid('realdebrid'), 'debrid/realdebrid');
  });

  test('addon prefix matches only that addon keys', () {
    final prefix = SecretRef.addonPrefix('ultranx');

    expect(SecretRef.addonToken('ultranx', 'nintendo_64').startsWith(prefix), isTrue);
    expect(SecretRef.addonToken('ultranx', 'snes').startsWith(prefix), isTrue);
    expect(SecretRef.addonToken('ultranx_2', 'snes').startsWith(prefix), isFalse);
    expect(SecretRef.iaAccessKey.startsWith(prefix), isFalse);
  });

  test('an id with slash or colon cannot forge another key', () {
    // Without sanitizing, addon id `a/b` plus console `c` would give
    // `addon:a/b/c`, which is the same thing as addon `a` plus console
    // `b/c`. Today's ids are slugs and this does not happen, but the key is
    // permanent and the id generator is not: sanitizing lives here, on the
    // side that cannot change later.
    expect(
      SecretRef.addonToken('a/b', 'c'),
      isNot(SecretRef.addonToken('a', 'b/c')),
    );
  });

  test('sanitizing does not collapse ids that differ only in punctuation', () {
    expect(SecretRef.addonToken('meu-rts', 'snes'), isNot(SecretRef.addonToken('meu_rts', 'snes')));
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/secret_ref_test.dart
```

Expected: `Error: Couldn't resolve the package 'roms_downloader' ... secret_ref.dart` or `Undefined name 'SecretRef'`. If it passes, you created the file before the test.

- [ ] **Step 3: Implement**

Create `lib/models/secret_ref.dart`:

```dart
/// The vault keys, in a single place.
///
/// They are `String` and not an enum because two of them depend on runtime
/// data: the addon id and the console id. The format is that of section 6.2 of
/// the architecture spec.
///
/// **This file is the hardest to change in the slice.** The key ends up in the
/// user's operating system keyring, out of the app's reach. Changing the
/// format later leaves an orphan credential on the machine of whoever updates,
/// with no way to find it back. That is why sanitizing lives here and not in
/// whoever generates the id.
class SecretRef {
  /// The token of a console served by an addon.
  ///
  /// Carries the **addon**, and not just the console, because the console id
  /// comes from its name: two addons that serve "Nintendo 64" both produce
  /// `nintendo_64`, and have different logins.
  static String addonToken(String addonId, String consoleId) =>
      '${addonPrefix(addonId)}${_sane(consoleId)}';

  /// Everything that belongs to an addon. Used to delete its credentials
  /// when the user removes it.
  ///
  /// Ends in `/` on purpose: without it, the `ultranx` prefix would match
  /// the keys of `ultranx_2`.
  static String addonPrefix(String addonId) => 'addon:${_sane(addonId)}/';

  static const iaAccessKey = 'ia/accessKey';
  static const iaSecretKey = 'ia/secretKey';
  static const iaCookies = 'ia/cookies';

  /// Per provider, because Real-Debrid will not be the only one.
  static String debrid(String provider) => 'debrid/${_sane(provider)}';

  /// Replaces what structures the key with `_`, so that no id can forge
  /// another's key. Only `:` and `/` are structural, so replacing the two is enough.
  ///
  /// The replacement is **not** injective: `a:b`, `a/b` and `a_b` all come out
  /// as `a_b`. Nothing is lost by that, because `_nameToId`
  /// (`catalog_service.dart:61`) already collapses every non-alphanumeric into
  /// `_`, and so the real ids never distinguish those three. Replacing more,
  /// like `[^a-z0-9]`, would then lose: `meu-rts` and `meu_rts` are two addons
  /// and would become the same key.
  ///
  /// An empty part comes out unguarded, on purpose. `_nameToId` returns `''`
  /// for a name that is only punctuation, and then `addonToken('x', '')` equals
  /// `addonPrefix('x')`. It is harmless: the prefix only serves to delete in
  /// bulk and is never a key of anything, and two consoles with empty id are
  /// already **one** console, because `_parseConsoles`
  /// (`catalog_service.dart:91`) writes both into the same map entry. Raising
  /// here would take down the Task 5 migration, which iterates keys already
  /// written, to defend against a collision the catalog collapsed earlier.
  static String _sane(String part) => part.replaceAll(RegExp(r'[:/]'), '_');
}
```

- [ ] **Step 4: Run to see it pass**

```bash
flutter test test/secret_ref_test.dart
```

Expected: `+7`, zero failures.

**Likely pitfall:** the last test, "sanitizing does not collapse ids that differ only in punctuation", fails if you swap the expression for something wider, like `[^a-z0-9]`. Then `meu-rts` and `meu_rts` become the same key and two different addons share a credential, which is exactly what the key exists to prevent. Sanitize **only** what structures the key.

- [ ] **Step 5: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`, the usual ones, none in the new files.

- [ ] **Step 6: Commit**

```bash
git add test/secret_ref_test.dart
git commit -m "test(cofre): chaves do cofre por addon, console e provedor"
git add lib/models/secret_ref.dart
git commit -m "feat(cofre): chaves do cofre por addon, console e provedor"
```

---

### Task 2: `SecretVault`, the interface, and the contract every implementation fulfills

**Files:**
- Create: `lib/services/secret_vault.dart`
- Create: `test/vault_contract.dart`
- Test: `test/secret_vault_test.dart`

This Task delivers two things that are worth more together than apart: the interface with the in-memory implementation, and the **contract file** that the other two implementations will reuse without copying tests.

The contract has a decision inside it that deserves to be read before writing the code: **writing an empty string deletes the key**. The alternative would be to store `''`, and then `read` would return `''` instead of `null`, and every caller would need to remember to treat both as "not set". Today the app already does this right in one place (`settings_provider.dart:125`, `token.isEmpty ? clearAuthToken : ...`) and the vault cannot undo that decision. A vault that returns `''` in one place and `null` in another becomes `if (t != null && t.isNotEmpty)` scattered across four screens.

- [ ] **Step 1: Write the contract**

Create `test/vault_contract.dart`. Note the name: it does **not** end in `_test.dart`, on purpose, because it does not run alone, it is called by three different test files.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// The contract every [SecretVault] implementation must satisfy.
///
/// [build] returns an empty vault on each call; a `Future` because the
/// `shared_preferences` implementation needs `await` to be born.
void runVaultContract(String name, Future<SecretVault> Function() build) {
  group('vault contract: $name', () {
    test('reads back what it wrote', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');

      expect(await vault.read('ia/accessKey'), 'ABCDEF');
    });

    test('a never-written key reads null', () async {
      final vault = await build();

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('writing over replaces', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'old');
      await vault.write('ia/accessKey', 'new');

      expect(await vault.read('ia/accessKey'), 'new');
    });

    test('delete deletes', () async {
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.delete('ia/accessKey');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('writing empty deletes rather than storing empty', () async {
      // Absence has one representation, `null`, so callers do not have to
      // handle both `''` and `null`.
      final vault = await build();
      await vault.write('ia/accessKey', 'ABCDEF');
      await vault.write('ia/accessKey', '');

      expect(await vault.read('ia/accessKey'), isNull);
    });

    test('deleteWithPrefix takes only matching keys', () async {
      final vault = await build();
      await vault.write('addon:ultranx/snes', 'a');
      await vault.write('addon:ultranx/n64', 'b');
      await vault.write('addon:ultranx_2/snes', 'c');
      await vault.write('ia/accessKey', 'd');

      await vault.deleteWithPrefix('addon:ultranx/');

      expect(await vault.read('addon:ultranx/snes'), isNull);
      expect(await vault.read('addon:ultranx/n64'), isNull);
      expect(await vault.read('addon:ultranx_2/snes'), 'c');
      expect(await vault.read('ia/accessKey'), 'd');
    });

    test('deleting a missing key does not throw', () async {
      final vault = await build();

      await vault.delete('addon:never/existed');
      await vault.deleteWithPrefix('addon:never/');

      expect(await vault.read('addon:never/existed'), isNull);
    });
  });
}
```

- [ ] **Step 2: Write the in-memory vault test**

Create `test/secret_vault_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secret_vault.dart';

import 'vault_contract.dart';

void main() {
  runVaultContract('MemoryVault', () async => MemoryVault());

  test('two in-memory vaults do not share state', () {
    // This is the reason `MemoryVault` exists: each test that uses a vault
    // needs its own. A shared `static` here would make one test see the secret
    // written by another, and the suite would start depending on order.
    final a = MemoryVault();
    final b = MemoryVault();

    return expectLater(
      a.write('ia/accessKey', 'ABCDEF').then((_) => b.read('ia/accessKey')),
      completion(isNull),
    );
  });
}
```

- [ ] **Step 3: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/secret_vault_test.dart
```

Expected: a compilation error, `Couldn't resolve the package` or `Undefined name 'MemoryVault'`.

- [ ] **Step 4: Implement**

Create `lib/services/secret_vault.dart`:

```dart
/// Where the app's secrets live: addon tokens, Internet Archive credentials
/// and, in slice 6, debrid keys.
///
/// It is an interface and not a concrete class because the implementation
/// depends on the platform, and in one of them it **fails**: on Linux, the
/// system keyring requires a Secret Service alive on the D-Bus, and on a server
/// Linux that does not exist. The user's choice was to fall back to plaintext
/// warning, instead of disabling the field, so the app needs to be able to swap
/// vaults at runtime.
///
/// **The absence of a secret has a single representation, `null`.** Writing an
/// empty string deletes the key. Without that rule, every caller would need to
/// treat `''` and `null` as the same thing, and one of them would eventually
/// forget.
abstract class SecretVault {
  /// The secret, or `null` if it was never written or has already been deleted.
  Future<String?> read(String key);

  /// Writes. An empty value **deletes**, and does not store empty.
  Future<void> write(String key, String value);

  Future<void> delete(String key);

  /// Deletes everything that starts with [prefix]. Used when the user removes
  /// an addon: its credentials go along, and the app does not know in advance
  /// which consoles of that addon ever got a login.
  Future<void> deleteWithPrefix(String prefix);
}

/// A fake vault, for testing. Persists nothing and does not leave this instance.
class MemoryVault implements SecretVault {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    _values.removeWhere((key, value) => key.startsWith(prefix));
  }
}
```

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/secret_vault_test.dart
```

Expected: `+8`, zero failures. It is the seven from the contract plus the isolation case.

- [ ] **Step 6: Run the whole suite**

```bash
flutter test
```

Expected: `+355`, zero failures. It is 340 from the baseline, plus 7 from Task 1, plus 8 from this one.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`, none in the new files.

**Likely pitfall:** `flutter analyze` complaining about `test/vault_contract.dart` for not having `main()`. It does not complain, because it is an ordinary Dart library; what **cannot** happen is the file being named `vault_contract_test.dart`, then `flutter test` would try to run it alone and fail with `Could not find a file named "main"`.

- [ ] **Step 8: Commit**

```bash
git add test/vault_contract.dart test/secret_vault_test.dart
git commit -m "test(cofre): contrato de cofre reusavel e o cofre em memoria"
git add lib/services/secret_vault.dart
git commit -m "feat(cofre): contrato de cofre reusavel e o cofre em memoria"
```

---

### Task 3: `PrefsVault`, the plaintext fallback

**Files:**
- Create: `lib/services/prefs_vault.dart`
- Test: `test/prefs_vault_test.dart`

This is the uncomfortable half of the locked decision: on a Linux with no keyring, the secret stays in plaintext. What this Task **gains** anyway, and it is not little, is that the secret leaves the `app_settings`, which is the JSON the app serializes whole and **whose read error prints the JSON itself back**. Measured, not deduced: the `jsonDecode` `FormatException` embeds the source excerpt in the message, and the `debugPrint('Error loading settings: $e')` of the error path (`settings_service.dart:21`) sends that to the log with the secret inside. An `app_settings` corrupted for any reason leaks `iaSecretKey` in the log. A separate key is a key that does not leak as a passenger.

The `secret:` prefix exists so that Task 5 can assert that the migration left nothing behind, and so that a future `getKeys()` can list secret only.

- [ ] **Step 1: Write the failing test**

Create `test/prefs_vault_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/prefs_vault.dart';

import 'vault_contract.dart';

Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  runVaultContract('PrefsVault', () async => PrefsVault(await _emptyPrefs()));

  test('the secret does not touch the key that holds the settings', () async {
    // The real gain of this implementation is not encrypting, because it does
    // not encrypt. It is taking the secret out of `app_settings`, whose read
    // error prints the JSON itself back: the `jsonDecode` `FormatException`
    // embeds the source excerpt, and the `debugPrint` of the error path
    // (`settings_service.dart:21`) sends that to the log with the secret inside.
    SharedPreferences.setMockInitialValues({'app_settings': '{"nszDecompressEnabled":true}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);

    await vault.write('ia/accessKey', 'ABCDEF');

    expect(prefs.getString('app_settings'), '{"nszDecompressEnabled":true}');
    expect(prefs.getString('secret:ia/accessKey'), 'ABCDEF');
  });

  test('the secret survives a new instance over the same prefs', () async {
    // `MemoryVault` would pass the whole contract and lose everything on app
    // close. The contract does not distinguish the two, this case does.
    final prefs = await _emptyPrefs();
    await PrefsVault(prefs).write('ia/accessKey', 'ABCDEF');

    expect(await PrefsVault(prefs).read('ia/accessKey'), 'ABCDEF');
  });

  test('deleting a whole addon does not touch what is not a secret', () async {
    // The only property that **only** this implementation has. The shared
    // contract exercises the boundary between two addons, but runs the same
    // for `MemoryVault`, which shares a store with nobody. This vault does
    // share: it sweeps the same `shared_preferences` where `app_settings` lives.
    SharedPreferences.setMockInitialValues({'app_settings': '{"downloadDir":"/home/roms"}'});
    SharedPreferences.resetStatic();
    final prefs = await SharedPreferences.getInstance();
    final vault = PrefsVault(prefs);
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'AAA');
    await vault.write(SecretRef.addonToken('ultranx_2', 'snes'), 'BBB');

    await vault.deleteWithPrefix(SecretRef.addonPrefix('ultranx'));

    expect(prefs.getString('app_settings'), '{"downloadDir":"/home/roms"}');
    expect(await vault.read(SecretRef.addonToken('ultranx_2', 'snes')), 'BBB');
    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
  });

  test('`open()` opens over the real prefs, which is the production path', () async {
    // The other cases build via the constructor, and `vault_provider.dart:39`
    // wires `PrefsVault.open` as the fallback. Without this case, the only path
    // production walks is the only one with no test.
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();

    final vault = await PrefsVault.open();
    await vault.write(SecretRef.iaAccessKey, 'ABCDEF');

    expect(await vault.read(SecretRef.iaAccessKey), 'ABCDEF');
  });
}
```

The last two cases are the reason this file exists beyond the shared contract, and they are worth the paragraph:

The delete one proves the only property that **only** this implementation has. The contract already exercises the boundary between `addon:ultranx/` and `addon:ultranx_2/`, but it runs the same for `MemoryVault`, which has its own store. This vault does not: it sweeps the same `shared_preferences` where `app_settings` lives. The case builds the keys with `SecretRef`, and not with a hand-written string, on purpose, because it is the trailing slash of `addonPrefix` that separates `ultranx` from `ultranx_2`, and a caller that built `'addon:ultranx'` without it would take down the neighboring addon's login.

The `open()` one covers the only path production walks: `vault_provider.dart` wires `PrefsVault.open` as the fallback, and all the other cases build via the constructor. It costs four lines because `setMockInitialValues({})` is already enough, with no provider override and no fake.

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/prefs_vault_test.dart
```

Expected: `Undefined name 'PrefsVault'`.

- [ ] **Step 3: Implement**

Create `lib/services/prefs_vault.dart`:

```dart
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// The fallback vault, in `shared_preferences`, **in plaintext**.
///
/// Used when the system keyring is not available, which in practice is Linux
/// with no `gnome-keyring` nor KWallet on the D-Bus. The user's choice was this
/// instead of disabling the login field, and whoever uses this vault shows up
/// with a warning on the screen (Group 5).
///
/// It does not encrypt, and does not pretend to encrypt. What it delivers
/// relative to what existed before is separation: the secret stops living
/// inside the `app_settings` JSON, which is serialized whole and printed on the
/// error path.
class PrefsVault implements SecretVault {
  /// Prefix of all the keys of this vault. Serves to avoid colliding with
  /// `app_settings` and to be able to sweep secret only.
  static const String keyPrefix = 'secret:';

  final SharedPreferences _prefs;

  PrefsVault(this._prefs);

  static Future<PrefsVault> open() async => PrefsVault(await SharedPreferences.getInstance());

  @override
  Future<String?> read(String key) async => _prefs.getString('$keyPrefix$key');

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    await _prefs.setString('$keyPrefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove('$keyPrefix$key');
  }

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    final target = '$keyPrefix$prefix';
    // `toList()` before removing: `where` is lazy, so it would interleave.
    final keys = _prefs.getKeys().where((key) => key.startsWith(target)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
```

- [ ] **Step 4: Run to see it pass**

```bash
flutter test test/prefs_vault_test.dart
```

Expected: `+11`, zero failures. It is the seven from the contract plus the four from this file.

**Likely pitfall:** the contract failing on "a key never written returns null" from the second case on, because `SharedPreferences.getInstance()` keeps an internal singleton and each `build()` of the contract asks for a new instance.

What zeroes the singleton, measured in `shared_preferences-2.5.3`, is **`setMockInitialValues`**: it itself does `_completer = null` (`lib/src/shared_preferences_legacy.dart:290`, comment "If the singleton instance has been initialized already, it is nullified"). The `resetStatic()` right after is redundant in this version: removing it from `_emptyPrefs` leaves the contract cases passing the same, confirmed. Keep both anyway, because it is cheap defense against `setPrefix` and against a plugin version change, but **do not write anywhere that it is `resetStatic()` that clears the singleton**: if Task 4 believes that when deciding between the two vaults, it will defend the wrong boundary.

- [ ] **Step 5: Run the whole suite**

```bash
flutter test
```

Expected: `+366`, zero failures.

- [ ] **Step 6: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 7: Commit**

```bash
git add test/prefs_vault_test.dart
git commit -m "test(cofre): cofre de reserva em shared_preferences, com chave separada"
git add lib/services/prefs_vault.dart
git commit -m "feat(cofre): cofre de reserva em shared_preferences, com chave separada"
```

---

### Task 4: `SecureStorageVault`, the probe, and the vault choice

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/services/secure_storage_vault.dart`
- Create: `lib/providers/vault_provider.dart`
- Test: `test/secure_storage_vault_test.dart`
- Test: `test/vault_provider_test.dart`

This is the only Task in the slice that brings a new dependency, and the only one that has to decide what to do when the platform does not cooperate.

Three things worth knowing beforehand:

1. **`flutter_secure_storage` is not directly testable.** It talks to the plugin through a platform channel, which does not exist in a `flutter test`. That is why a thin interface enters, `SecureStorageBackend`, with the four methods this app uses. The `SecureStorageVault` talks to the interface, the tests inject a fake, and the real implementation is three lines of delegation that no test covers and does not need to.
2. **The probe writes, reads back and deletes.** "The write did not raise" is **not** proof that the keyring works: there is a backend that accepts the write and does not store it. Only the read-back proves it.
3. **The version is 10.x, and this is not conservatism, it is the only one that resolves.** The 11.x does not enter this `pubspec`, and the attempt cost a stuck Task: `flutter_secure_storage >=11.0.0-beta.1` pulls `flutter_secure_storage_windows ^4.2.2`, which requires `win32 ^6.0.1`, while the `package_info_plus: ^9.0.0` already pinned here (`pubspec.yaml:29`) requires `win32 ^5.5.3`. The two constraints exclude each other and the solver refuses. Literal output:

   ```
   Because package_info_plus >=8.0.3 <10.0.0 depends on win32 ^5.5.3 and flutter_secure_storage_windows >=4.2.0 depends on win32 ^6.0.1, package_info_plus >=8.0.3 <10.0.0 is incompatible with flutter_secure_storage_windows >=4.2.0.
   So, because roms_downloader depends on both package_info_plus ^9.0.0 and flutter_secure_storage ^11.1.0, version solving failed.
   ```

   The way out would be to bump `package_info_plus` to `^10`, and that **is not to be done**: it is used in two production files (`about_screen.dart` and `zerox0_service.dart`), `win32` would jump from 5 to 6 in a dependency this slice has no reason at all to touch, and the risk would land on the About screen and on the user agent. A security slice does not drag someone else's dependency along. If someone "upgrades" this to 11.x later, `pub get` breaks again, and the reason is written here.

   Measured on 10.3.3, and the code of this Task does not change one comma because of it: `read(key:)`, `write(key:, value:)`, `delete(key:)`, `readAll()` and the constructor `const FlutterSecureStorage()` exist the same (`flutter_secure_storage-10.3.3/lib/flutter_secure_storage.dart:35`, `:134`, `:185`, `:249`, `:293`).
4. **The plugin requires minSdk 23 on Android** (`flutter_secure_storage-10.3.3/android/build.gradle:46`). This project uses `minSdk = flutter.minSdkVersion` (`android/app/build.gradle.kts:43`), which on Flutter 3.35 is 24. There is slack, and nothing needs to change. On Linux, it requires `libsecret-1-dev` at compile time, which is already installed on this VM (`pkg-config --modversion libsecret-1` gives `0.21.4`).

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, on the last line of the `dependencies:` list, after `ftp_server: ^2.3.2`:

```yaml
  flutter_secure_storage: ^10.3.3
```

Then:

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter pub get
```

Expected: `Changed 6 dependencies!`, measured. If you get `version solving failed` talking about `win32`, you wrote `^11` instead of `^10.3.3`: read item 3 above. The `pubspec.lock` will change. **Do not add it to the commit**: it already lives dirty in this repository because the local Flutter resolves older transitive versions, and committing it mixes noise with the change.

- [ ] **Step 2: Write the system vault test**

Create `test/secure_storage_vault_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

import 'vault_contract.dart';

/// The real plugin does not exist inside `flutter test`: it talks through a
/// platform channel. This fake is what makes the system vault testable.
class _FakeBackend implements SecureStorageBackend {
  _FakeBackend({this.throwsOnWrite = false, this.swallowsWrite = false});

  /// A Linux without Secret Service: the write throws `PlatformException`.
  final bool throwsOnWrite;

  /// Worse than throwing: accepts the write and stores nothing, which is why
  /// the probe reads back instead of only checking that the write threw.
  final bool swallowsWrite;

  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (throwsOnWrite) throw PlatformException(code: 'Libsecret error');
    if (swallowsWrite) return;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

void main() {
  runVaultContract('SecureStorageVault', () async => SecureStorageVault(_FakeBackend()));

  group('availability probe', () {
    test('passes a keyring that reads back what it wrote', () async {
      expect(await probeSecureStorage(_FakeBackend()), isTrue);
    });

    test('fails a keyring that throws', () async {
      expect(await probeSecureStorage(_FakeBackend(throwsOnWrite: true)), isFalse);
    });

    test('fails a keyring that silently swallows the write', () async {
      expect(await probeSecureStorage(_FakeBackend(swallowsWrite: true)), isFalse);
    });

    test('leaves no canary behind', () async {
      final backend = _FakeBackend();

      await probeSecureStorage(backend);

      expect(backend.values, isEmpty);
    });
  });
}
```

- [ ] **Step 3: Write the choice test**

Create `test/vault_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

class _GoodBackend implements SecureStorageBackend {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
}

class _DeadBackend implements SecureStorageBackend {
  @override
  Future<String?> read(String key) async => throw StateError('no keyring');

  @override
  Future<void> write(String key, String value) async => throw StateError('no keyring');

  @override
  Future<void> delete(String key) async => throw StateError('no keyring');

  @override
  Future<Map<String, String>> readAll() async => throw StateError('no keyring');
}

void main() {
  test('with a live keyring, uses the system one and says it is encrypted', () async {
    final choice = await chooseVault(backend: _GoodBackend(), buildFallback: () async => MemoryVault());

    expect(choice.vault, isA<SecureStorageVault>());
    expect(choice.encryptedAtRest, isTrue);
  });

  test('with no keyring, falls back and says it is NOT encrypted', () async {
    // The two assertions are the whole locked decision. Falling back without
    // carrying the `false` along is what turns the slice into makeup: the
    // screen would announce "stored securely" over plaintext.
    final choice = await chooseVault(backend: _DeadBackend(), buildFallback: () async => MemoryVault());

    expect(choice.vault, isA<MemoryVault>());
    expect(choice.encryptedAtRest, isFalse);
  });

  test('with a live keyring, the fallback is never even built', () async {
    // `PrefsVault.open()` opens the `shared_preferences`. Building the fallback
    // always, only to discard it right after, is wasted boot work on every
    // device that has a keyring, which is the majority.
    var builds = 0;

    await chooseVault(
      backend: _GoodBackend(),
      buildFallback: () async {
        builds++;
        return MemoryVault();
      },
    );

    expect(builds, 0);
  });
}
```

- [ ] **Step 4: Run to see it fail**

```bash
flutter test test/secure_storage_vault_test.dart test/vault_provider_test.dart
```

Expected: a compilation error, `Undefined name 'SecureStorageVault'`.

- [ ] **Step 5: Implement the system vault**

Create `lib/services/secure_storage_vault.dart`:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// The piece of `flutter_secure_storage` that this app uses.
///
/// It exists because the plugin talks through a platform channel, which does
/// not exist inside `flutter test`. Without this interface, the system vault
/// would be the only [SecretVault] implementation with no test at all, exactly
/// the one that holds the real secrets.
abstract class SecureStorageBackend {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<Map<String, String>> readAll();
}

/// The real implementation. Three lines of delegation per method and no
/// decision: everything that is a decision lives in [SecureStorageVault], which
/// is tested.
class PluginSecureStorage implements SecureStorageBackend {
  final FlutterSecureStorage _storage;

  const PluginSecureStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<Map<String, String>> readAll() => _storage.readAll();
}

/// The vault encrypted by the operating system: Keychain on Apple, Keystore on
/// Android, DPAPI on Windows, libsecret on Linux.
class SecureStorageVault implements SecretVault {
  final SecureStorageBackend _backend;

  const SecureStorageVault(this._backend);

  @override
  Future<String?> read(String key) => _backend.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      await delete(key);
      return;
    }
    await _backend.write(key, value);
  }

  @override
  Future<void> delete(String key) => _backend.delete(key);

  @override
  Future<void> deleteWithPrefix(String prefix) async {
    final all = await _backend.readAll();
    // `toList()` before deleting: a backend that returns its live map would
    // throw `ConcurrentModificationError` mid-removal.
    for (final key in all.keys.where((key) => key.startsWith(prefix)).toList()) {
      await _backend.delete(key);
    }
  }
}

/// Writes, reads back and deletes a canary key.
///
/// **Reading back is the point.** On a Linux with no Secret Service the plugin
/// raises, and the `try` catches that; but there is also a backend that accepts
/// the write and stores nothing, and that one only shows up on the read. An app
/// that announces "encrypted at rest" over one of those loses the user's token
/// at every restart without emitting a single error.
Future<bool> probeSecureStorage(SecureStorageBackend backend) async {
  const key = 'probe/canary';
  const value = 'ok';
  try {
    await backend.write(key, value);
    final readBack = await backend.read(key);
    await backend.delete(key);
    return readBack == value;
  } catch (_) {
    // Swallowing is the right behavior here, and only here: the probe exists
    // precisely to turn "raised" into `false`. The caller decides what to do,
    // and what it does is fall back to the fallback.
    return false;
  }
}
```

- [ ] **Step 6: Implement the choice**

Create `lib/providers/vault_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/services/prefs_vault.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/secure_storage_vault.dart';

/// Which vault the app managed to open, and whether it encrypts.
///
/// The two fields travel together on purpose. The accounts screen needs to warn
/// when the secret is in plaintext (locked decision), and a `SecretVault` alone
/// does not tell that story: `PrefsVault` and `SecureStorageVault` fulfill
/// exactly the same contract.
class VaultChoice {
  final SecretVault vault;

  /// `false` means plaintext. In practice, Linux with no `gnome-keyring` nor
  /// KWallet on the D-Bus.
  final bool encryptedAtRest;

  const VaultChoice(this.vault, {required this.encryptedAtRest});
}

/// Tries the system keyring; if it does not respond, falls back to [buildFallback].
///
/// [buildFallback] is a function and not a value so as not to open the
/// `shared_preferences` on every boot of a device that has a keyring, which is
/// the majority.
Future<VaultChoice> chooseVault({
  required SecureStorageBackend backend,
  required Future<SecretVault> Function() buildFallback,
}) async {
  if (await probeSecureStorage(backend)) {
    return VaultChoice(SecureStorageVault(backend), encryptedAtRest: true);
  }
  return VaultChoice(await buildFallback(), encryptedAtRest: false);
}

final vaultProvider = FutureProvider<VaultChoice>((ref) {
  return chooseVault(
    backend: const PluginSecureStorage(),
    buildFallback: PrefsVault.open,
  );
});
```

- [ ] **Step 7: Run to see it pass**

```bash
flutter test test/secure_storage_vault_test.dart test/vault_provider_test.dart
```

Expected: `+14`, zero failures. It is seven from the contract, four from the probe and three from the choice.

**Likely pitfall:** `PrefsVault.open` in the provider's `buildFallback` gives a type error if you declared `open()` returning `Future<PrefsVault>` and the parameter asks for `Future<SecretVault> Function()`. In Dart this **compiles**, because `Future<PrefsVault>` is a subtype of `Future<SecretVault>` and functions are covariant in their return. If you get an error, what is wrong is something else, probably `open()` without `static`.

- [ ] **Step 8: Run the whole suite**

```bash
flutter test
```

Expected: `+380`, zero failures.

- [ ] **Step 9: Analyze and build**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found` and `Built build/linux/x64/debug/bundle/roms_downloader`.

The `build` is not decoration in this Task: it is the only proof available on this VM that the new dependency actually **links**. A plugin with a missing native piece passes the whole `flutter test` and breaks only at compile. If it fails with `libsecret-1.pc not found`, the development package is gone; fix it with `sudo apt-get update -qq && sudo apt-get install -y libsecret-1-dev`.

- [ ] **Step 10: Commit**

```bash
git add test/secure_storage_vault_test.dart test/vault_provider_test.dart
git commit -m "test(cofre): cofre do sistema, sonda de disponibilidade e escolha com reserva"
git add pubspec.yaml lib/services/secure_storage_vault.dart lib/providers/vault_provider.dart
git commit -m "feat(cofre): cofre do sistema, sonda de disponibilidade e escolha com reserva"
git add linux/flutter/generated_plugin_registrant.cc linux/flutter/generated_plugins.cmake \
        macos/Flutter/GeneratedPluginRegistrant.swift \
        windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake
git commit -m "chore(cofre): registra o plugin do cofre nos tres alvos de desktop"
```

The third commit is the only one in the whole slice, because it is the only Task that brings a dependency with native code. Those five files are generated, but they are **versioned** in this repository (`git log -- linux/flutter/generated_plugin_registrant.cc` shows that every plugin bump carries them along), and the `pub get` of Step 1 rewrote them to register `flutter_secure_storage`. Leaving them out breaks no build, because any `pub get` regenerates them, but it leaves five dirty files in the `git status` of all 23 following Tasks, and then a real slip goes unnoticed in the middle of the noise. The `pubspec.lock` stays out, and it does stay dirty to the end: its dirt predates this slice.

---

### Task 5: the migration that empties the `app_settings`

**Files:**
- Create: `lib/services/secret_migration.dart`
- Test: `test/secret_migration_test.dart`

A new vault is worth nothing while the old secret stays in the old place. This Task writes the one-time change that takes the four secrets out of the `app_settings` JSON and puts them in the vault.

It operates on the **raw map**, not on `AppSettings`, and returns the clean map instead of saving. Two reasons:

1. `AppSettings.fromJson` already **discards** an unknown field silently. If the migration ran after deserialization, it would depend on the model still carrying the fields that Group 2 will precisely take out of it, and the order of the two Tasks would become a trap.
2. Returning instead of saving keeps this Task pure Dart, with no `shared_preferences` and no platform `await`. Whoever saves is Group 2.

**There is no "already migrated" flag.** After the first pass the field is no longer in the map, so the second pass is naturally harmless. If the save fails midway, the next opening tries again, and it is for that case that the rule "the already-filled vault wins over the file" exists: the file's copy is the old one, by definition.

The `builtinAddonId` enters via a parameter because the canonical constant (`kBuiltinAddonId`) is only born in Group 3, and this Task cannot depend on it. Whoever fills the parameter is Task 6, with the provisional `SettingsService.builtinAddonId`; whoever replaces the provisional with the canonical one is Task 9.

- [ ] **Step 1: Write the failing test**

Create `test/secret_migration_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Counts writes, to prove a secret-free map never touches the vault.
class _VaultSpy extends MemoryVault {
  int writes = 0;

  @override
  Future<void> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }
}

Map<String, dynamic> _settings({
  String? iaAccessKey,
  String? iaSecretKey,
  String? iaCookies,
  Map<String, dynamic>? consoleSettings,
}) {
  return {
    'consoleSettings': consoleSettings ?? <String, dynamic>{},
    'generalSettings': {'downloadDir': '/home/user/roms', 'autoExtract': true},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
    if (iaCookies != null) 'iaCookies': iaCookies,
    'nszDecompressEnabled': true,
  };
}

void main() {
  test('all three Internet Archive credentials go to the vault', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz'));

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(SecretRef.iaSecretKey), 'SK');
    expect(await vault.read(SecretRef.iaCookies), 'logged-in-sig=xyz');
  });

  test('each console token is keyed by addon, not just by console', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(consoleSettings: {
      'nintendo_64': {'downloadDir': '/roms/n64', 'authToken': 'tok-n64'},
      'snes': {'authToken': 'tok-snes'},
    }));

    expect(await vault.read(SecretRef.addonToken('builtin', 'nintendo_64')), 'tok-n64');
    expect(await vault.read(SecretRef.addonToken('builtin', 'snes')), 'tok-snes');
  });

  test('the returned map keeps none of the four secrets', () async {
    final migration = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final cleaned = await migration.drain(_settings(
      iaAccessKey: 'AK',
      iaSecretKey: 'SK',
      iaCookies: 'logged-in-sig=xyz',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    ));

    expect(cleaned.containsKey('iaAccessKey'), isFalse);
    expect(cleaned.containsKey('iaSecretKey'), isFalse);
    expect(cleaned.containsKey('iaCookies'), isFalse);
    expect((cleaned['consoleSettings'] as Map)['snes'], isNot(contains('authToken')));
  });

  test('non-secret values stay where they were', () async {
    final migration = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');

    final cleaned = await migration.drain(_settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'downloadDir': '/roms/snes', 'authToken': 'tok-snes'},
      },
    ));

    expect(cleaned['nszDecompressEnabled'], isTrue);
    expect((cleaned['generalSettings'] as Map)['downloadDir'], '/home/user/roms');
    expect((cleaned['consoleSettings'] as Map)['snes'], containsPair('downloadDir', '/roms/snes'));
  });

  test('an already-populated vault wins over the file, but plaintext still leaves', () async {
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'new');
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final cleaned = await migration.drain(_settings(iaAccessKey: 'old'));

    expect(await vault.read(SecretRef.iaAccessKey), 'new');
    expect(cleaned.containsKey('iaAccessKey'), isFalse);
  });

  test('an empty value does not become a vault key', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(iaAccessKey: ''));

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
  });

  test('a malformed consoleSettings does not break the migration', () async {
    final vault = MemoryVault();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    final cleaned = await migration.drain({
      'consoleSettings': {
        'snes': 'this should be a map',
        'n64': {'authToken': 'tok-n64'},
      },
      'nszDecompressEnabled': true,
    });

    expect(await vault.read(SecretRef.addonToken('builtin', 'n64')), 'tok-n64');
    expect((cleaned['consoleSettings'] as Map)['snes'], 'this should be a map');
  });

  test('does not mutate the map it received', () async {
    // A shallow `Map.from` is not enough: the nested `consoleSettings` is the
    // same object, so the token would vanish from the caller's map.
    final migration = SecretMigration(vault: MemoryVault(), builtinAddonId: 'builtin');
    final original = _settings(
      iaAccessKey: 'AK',
      consoleSettings: {
        'snes': {'authToken': 'tok-snes'},
      },
    );

    await migration.drain(original);

    expect(original['iaAccessKey'], 'AK');
    expect((original['consoleSettings'] as Map)['snes'], containsPair('authToken', 'tok-snes'));
  });

  test('a secret-free map writes nothing to the vault', () async {
    // Each write is a D-Bus round trip on Linux with a keyring; for a user who
    // never signed in, the right number is zero.
    final vault = _VaultSpy();
    final migration = SecretMigration(vault: vault, builtinAddonId: 'builtin');

    await migration.drain(_settings(consoleSettings: {
      'snes': {'downloadDir': '/roms/snes'},
    }));

    expect(vault.writes, 0);
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/secret_migration_test.dart
```

Expected: `Undefined name 'SecretMigration'`.

- [ ] **Step 3: Implement**

Create `lib/services/secret_migration.dart`:

```dart
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// Takes the four secrets out of the `app_settings` JSON and puts them in the
/// vault.
///
/// Works on the **raw** map, before `AppSettings.fromJson`, because the model
/// discards an unknown field silently: running after deserialization would tie
/// this migration to the fields that Group 2 will take out of the model.
///
/// Returns the clean map instead of saving. Whoever saves is the caller, and
/// that is where `shared_preferences` lives.
///
/// **There is no "already ran" flag.** After the first pass the fields are no
/// longer in the map, so the second is harmless on its own. If the save fails
/// midway, the next opening tries again, and then the rule that the value
/// already in the vault wins over the file value applies.
class SecretMigration {
  final SecretVault vault;

  /// The addon that today's catalog consoles belong to. Enters via a parameter
  /// because the constant is born in Group 3 and this Task cannot depend on it.
  final String builtinAddonId;

  const SecretMigration({required this.vault, required this.builtinAddonId});

  Future<Map<String, dynamic>> drain(Map<String, dynamic> raw) async {
    final cleaned = Map<String, dynamic>.from(raw);

    await _move(cleaned, 'iaAccessKey', SecretRef.iaAccessKey);
    await _move(cleaned, 'iaSecretKey', SecretRef.iaSecretKey);
    await _move(cleaned, 'iaCookies', SecretRef.iaCookies);

    final consoles = cleaned['consoleSettings'];
    if (consoles is Map) {
      final result = <String, dynamic>{};
      for (final entry in consoles.entries) {
        final id = entry.key.toString();
        final value = entry.value;
        if (value is! Map) {
          // Hand-edited file. Let it through intact: the migration runs at app
          // opening, and raising here becomes an app that does not open.
          result[id] = value;
          continue;
        }
        // Own copy, not the caller's nested map: `Map.from` above is shallow.
        final console = Map<String, dynamic>.from(value);
        await _move(console, 'authToken', SecretRef.addonToken(builtinAddonId, id));
        result[id] = console;
      }
      cleaned['consoleSettings'] = result;
    }

    return cleaned;
  }

  /// Removes [field] from [from] always, and writes to the vault only when there
  /// is something to write and the vault has no value yet.
  Future<void> _move(Map<String, dynamic> from, String field, String ref) async {
    final value = from.remove(field);
    if (value is! String || value.isEmpty) return;
    if (await vault.read(ref) != null) return;
    await vault.write(ref, value);
  }
}
```

- [ ] **Step 4: Run to see it pass**

```bash
flutter test test/secret_migration_test.dart
```

Expected: `+11`, zero failures.

**Likely pitfall:** the case "does not mutate the map it received" fails if you write `final cleaned = Map<String, dynamic>.from(raw)` and touch `consoles` directly. `Map.from` is shallow: the copy's `consoleSettings` is **the same object** as the original's. Copying each console map is what closes this, and that is why the loop builds a `result` instead of editing in place.

- [ ] **Step 5: Run the whole suite**

```bash
flutter test
```

Expected: `+389`, zero failures.

- [ ] **Step 6: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 7: Commit**

```bash
git add test/secret_migration_test.dart
git commit -m "test(cofre): migracao unica que esvazia os segredos do app_settings"
git add lib/services/secret_migration.dart
git commit -m "feat(cofre): migracao unica que esvazia os segredos do app_settings"
```

**End of Group 1.** The vault exists, knows which implementation to use, knows how to say whether it encrypts, and knows how to empty the old place. None of that is wired to the app yet: `flutter run` at this point behaves exactly as before. Whoever wires it is Group 2.

| Task | New | Cumulative |
| --- | --- | --- |
| baseline | 0 | 340 |
| 1, `SecretRef` | 7 | 347 |
| 2, `SecretVault` and contract | 8 | 355 |
| 3, `PrefsVault` | 11 | 366 |
| 4, `SecureStorageVault` and choice | 14 | 380 |
| 5, migration | 9 | 389 |

---

## Group 2: the 6.3 fix

Three Tasks. Group 1 built the vault without wiring a single wire; here the wires are connected, and it is here that section 6.3 of the spec is fulfilled.

The order matters and is not negotiable: **the secret only leaves the file after it is already in the vault**. That is why Task 6 does both halves in the same commit, instead of "first stop writing, then start storing". Between those two commits there would be a window in which the user's token would not be anywhere.

### Task 6: the secrets start living in the vault

**Files:**
- Modify: `lib/models/settings_model.dart:82-96` and `:151-160`
- Modify: `lib/services/settings_service.dart`
- Modify: `lib/providers/settings_provider.dart`
- Test: `test/settings_model_secrets_test.dart`
- Test: `test/settings_service_test.dart`

An asymmetry on purpose, which is the only subtle thing about this Task: **`toJson` stops writing the secrets, and `fromJson` keeps knowing how to read them.** It is not carelessness. The file of the user who has not migrated yet has the fields there, and whoever takes them out is the Task 5 migration, which runs on the raw map. Taking out the read along with it would gain nothing and would turn any path that skips the migration into a silent loss.

The other decision that deserves to be read before coding: **saving never deletes a secret.** `saveSettings` writes what exists and ignores what is `null`. Deleting is an explicit operation, with its own method. The reason is a real race: `SettingsNotifier` already saves from user actions while `_loadSettings` is still in flight, and a `saveSettings` that deleted everything that is `null` would turn a hasty click at boot into loss of all credentials. Nobody would notice until the next download failed.

- [ ] **Step 1: Write the model test**

Create `test/settings_model_secrets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';

void main() {
  test('the saved JSON does not carry the three Internet Archive credentials', () {
    const settings = AppSettings(iaAccessKey: 'AK', iaSecretKey: 'SK', iaCookies: 'logged-in-sig=xyz');

    final json = settings.toJson();

    expect(json.containsKey('iaAccessKey'), isFalse);
    expect(json.containsKey('iaSecretKey'), isFalse);
    expect(json.containsKey('iaCookies'), isFalse);
  });

  test('the saved JSON does not carry the console token', () {
    const console = BaseSettings(downloadDir: '/roms/snes', authToken: 'tok-snes');

    final json = console.toJson();

    expect(json.containsKey('authToken'), isFalse);
    expect(json['downloadDir'], '/roms/snes');
  });

  test('reading the legacy format still works', () {
    // Deliberate asymmetry: writes without, reads with. The file of whoever has
    // not migrated yet has the fields there, and whoever takes them out is the
    // Task 5 migration, which runs on the raw map. Taking out the read along
    // with it would close no hole and would make any path that skips the
    // migration lose the token silently.
    final settings = AppSettings.fromJson({
      'iaAccessKey': 'AK',
      'consoleSettings': {
        'snes': {'authToken': 'tok-snes'},
      },
    });

    expect(settings.iaAccessKey, 'AK');
    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
  });

  test('what is not a secret keeps being saved', () {
    const settings = AppSettings(nszDecompressEnabled: false, catalogSourceUrl: 'https://example/consoles.json');

    final json = settings.toJson();

    expect(json['nszDecompressEnabled'], isFalse);
    expect(json['catalogSourceUrl'], 'https://example/consoles.json');
  });
}
```

- [ ] **Step 2: Write the service test**

Create `test/settings_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

Future<SharedPreferences> _prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  SharedPreferences.resetStatic();
  return SharedPreferences.getInstance();
}

String _appSettings({String? iaAccessKey, String? authTokenSnes}) {
  return jsonEncode({
    'consoleSettings': {
      'snes': {
        'downloadDir': '/roms/snes',
        if (authTokenSnes != null) 'authToken': authTokenSnes,
      },
    },
    'generalSettings': {'downloadDir': '/home/user/roms'},
    if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
    'nszDecompressEnabled': true,
  });
}

String _snesKey() => SecretRef.addonToken(SettingsService.builtinAddonId, 'snes');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loading takes the secret out of the file and puts it in the vault', () async {
    await _prefsWith({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});
    final vault = MemoryVault();

    await SettingsService().loadSettings(vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_snesKey()), 'tok-snes');
  });

  test('loading returns the settings with the secret, read from the vault', () async {
    // The whole app reads `settings.consoleSettings[id].authToken`. If the load
    // drained without rehydrating, the migration would erase everyone's login on
    // the first opening after the update.
    await _prefsWith({'app_settings': _appSettings(authTokenSnes: 'tok-snes')});

    final settings = await SettingsService().loadSettings(MemoryVault());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('loading rewrites app_settings without the secret', () async {
    final prefs = await _prefsWith({'app_settings': _appSettings(iaAccessKey: 'AK', authTokenSnes: 'tok-snes')});

    await SettingsService().loadSettings(MemoryVault());

    final saved = prefs.getString('app_settings')!;
    expect(saved, isNot(contains('AK')));
    expect(saved, isNot(contains('tok-snes')));
    expect(saved, contains('/roms/snes'));
  });

  test('loading does not rewrite app_settings when there was no secret', () async {
    // The load runs on every opening. Rewriting always is a disk write for
    // nothing, and it erases the clue of when the migration actually happened.
    final withoutSecret = _appSettings();
    final prefs = await _prefsWith({'app_settings': withoutSecret});

    await SettingsService().loadSettings(MemoryVault());

    expect(prefs.getString('app_settings'), withoutSecret);
  });

  test('saving writes the secret to the vault', () async {
    await _prefsWith({'app_settings': _appSettings()});
    final vault = MemoryVault();
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_snesKey()), 'tok-snes');
  });

  test('saving does not write a secret inside app_settings', () async {
    final prefs = await _prefsWith({'app_settings': _appSettings()});
    const settings = AppSettings(
      iaAccessKey: 'AK',
      consoleSettings: {'snes': BaseSettings(authToken: 'tok-snes')},
    );

    await SettingsService().saveSettings(settings, MemoryVault());

    expect(prefs.getString('app_settings'), isNot(contains('AK')));
    expect(prefs.getString('app_settings'), isNot(contains('tok-snes')));
  });

  test('saving does NOT delete from the vault what is null in the settings', () async {
    // The real race: `SettingsNotifier` saves from a user action while the load
    // is still in flight, and at that instant the state is `const AppSettings()`,
    // all null. If saving deleted what is null, a hasty click at boot would take
    // all the credentials along, with no error on the screen. Deleting is an
    // explicit operation, and has its own method.
    await _prefsWith({'app_settings': _appSettings()});
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(_snesKey(), 'tok-snes');

    await SettingsService().saveSettings(const AppSettings(), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
    expect(await vault.read(_snesKey()), 'tok-snes');
  });

  test('clearing the IA credentials takes all three', () async {
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');
    await vault.write(SecretRef.iaSecretKey, 'SK');
    await vault.write(SecretRef.iaCookies, 'logged-in-sig=xyz');

    await SettingsService().clearIaSecrets(vault);

    expect(await vault.read(SecretRef.iaAccessKey), isNull);
    expect(await vault.read(SecretRef.iaSecretKey), isNull);
    expect(await vault.read(SecretRef.iaCookies), isNull);
  });

  test('clearing one console token does not take the neighbor', () async {
    final vault = MemoryVault();
    await vault.write(_snesKey(), 'tok-snes');
    await vault.write(SecretRef.addonToken(SettingsService.builtinAddonId, 'n64'), 'tok-n64');

    await SettingsService().clearConsoleToken('snes', vault);

    expect(await vault.read(_snesKey()), isNull);
    expect(await vault.read(SecretRef.addonToken(SettingsService.builtinAddonId, 'n64')), 'tok-n64');
  });
}
```

- [ ] **Step 3: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/settings_model_secrets_test.dart test/settings_service_test.dart
```

Expected: the model ones fail on an assertion (`Expected: false, Actual: true`, because today the `toJson` does write them), and the service ones fail at compile (`loadSettings` does not accept an argument).

- [ ] **Step 4: Take the secrets out of `toJson`**

In `lib/models/settings_model.dart`, in `AppSettings.toJson` (lines 82-96), **delete** the three lines:

```dart
      if (iaAccessKey != null) 'iaAccessKey': iaAccessKey,
      if (iaSecretKey != null) 'iaSecretKey': iaSecretKey,
      if (iaCookies != null) 'iaCookies': iaCookies,
```

and, in `BaseSettings.toJson` (lines 151-160), **delete**:

```dart
      if (authToken != null) 'authToken': authToken,
```

**Do not touch the `fromJson`.** The asymmetry is the point.

- [ ] **Step 5: Wire the vault into `SettingsService`**

Rewrite `lib/services/settings_service.dart`:

```dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/services/secret_migration.dart';
import 'package:roms_downloader/services/secret_vault.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';

  /// The addon that today's catalog consoles belong to.
  ///
  /// While there is a single source, this id is constant. When there are N
  /// addons, this mirror stays the builtin's only, and the token of the others
  /// starts being read on demand from the vault (Task 19). It lives here, and
  /// not in [SecretRef], because it is a fact about the installation and not
  /// about the key format.
  static const String builtinAddonId = 'builtin';

  final DirectoryService _directoryService = DirectoryService();

  Future<AppSettings> loadSettings(SecretVault vault) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);

      if (settingsJson != null) {
        final raw = jsonDecode(settingsJson) as Map<String, dynamic>;
        final cleaned = await SecretMigration(vault: vault, builtinAddonId: builtinAddonId).drain(raw);

        // Only rewrites if the migration actually took something out. The load
        // runs on every app opening; rewriting always is a disk write for
        // nothing. The comparison is safe because `drain` does not touch the map
        // it received.
        final cleanedJson = jsonEncode(cleaned);
        if (cleanedJson != jsonEncode(raw)) {
          await prefs.setString(_settingsKey, cleanedJson);
        }

        return _hydrate(AppSettings.fromJson(cleaned), vault);
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }

    final defaultDownloadDir = await _directoryService.getDownloadDir();
    return AppSettings(
      generalSettings: BaseSettings(downloadDir: defaultDownloadDir, autoExtract: true),
    );
  }

  /// Returns the settings with the secrets put back, coming from the vault.
  ///
  /// Without this, the migration would be data loss: the whole app reads
  /// `settings.consoleSettings[id].authToken`, and it just left the file.
  Future<AppSettings> _hydrate(AppSettings settings, SecretVault vault) async {
    final consoles = <String, BaseSettings>{};
    for (final entry in settings.consoleSettings.entries) {
      final token = await vault.read(SecretRef.addonToken(builtinAddonId, entry.key));
      consoles[entry.key] = token == null ? entry.value : entry.value.copyWith(authToken: token);
    }

    return settings.copyWith(
      consoleSettings: consoles,
      iaAccessKey: await vault.read(SecretRef.iaAccessKey),
      iaSecretKey: await vault.read(SecretRef.iaSecretKey),
      iaCookies: await vault.read(SecretRef.iaCookies),
    );
  }

  Future<void> saveSettings(AppSettings settings, SecretVault vault) async {
    try {
      await _writeSecrets(settings, vault);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  /// Writes what exists and **does not delete what is `null`**.
  ///
  /// Deleting here would be tempting and is wrong: `SettingsNotifier` saves from
  /// a user action while the load is still in flight, and at that instant the
  /// state is `const AppSettings()`, all `null`. Saving by deleting would turn a
  /// hasty click at boot into loss of all credentials, with no error on the
  /// screen. Whoever deletes is [clearIaSecrets] and [clearConsoleToken], called
  /// on purpose.
  Future<void> _writeSecrets(AppSettings settings, SecretVault vault) async {
    await _writeIfPresent(vault, SecretRef.iaAccessKey, settings.iaAccessKey);
    await _writeIfPresent(vault, SecretRef.iaSecretKey, settings.iaSecretKey);
    await _writeIfPresent(vault, SecretRef.iaCookies, settings.iaCookies);
    for (final entry in settings.consoleSettings.entries) {
      await _writeIfPresent(vault, SecretRef.addonToken(builtinAddonId, entry.key), entry.value.authToken);
    }
  }

  Future<void> _writeIfPresent(SecretVault vault, String key, String? value) async {
    if (value == null || value.isEmpty) return;
    await vault.write(key, value);
  }

  Future<void> clearIaSecrets(SecretVault vault) async {
    await vault.delete(SecretRef.iaAccessKey);
    await vault.delete(SecretRef.iaSecretKey);
    await vault.delete(SecretRef.iaCookies);
  }

  Future<void> clearConsoleToken(String consoleId, SecretVault vault) async {
    await vault.delete(SecretRef.addonToken(builtinAddonId, consoleId));
  }

  T? getGeneralSetting<T>(AppSettings settings, String key) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    return settings.generalSettings.getSetting<T>(key);
  }

  T? getConsoleSetting<T>(AppSettings settings, String consoleId, String key) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    return settings.consoleSettings[consoleId]?.getSetting<T>(key);
  }

  T? getSetting<T>(AppSettings settings, String key, [String? consoleId]) {
    assert(AppSettings.settingsSchema.containsKey(key), 'Invalid setting key: $key');
    if (consoleId != null) {
      final consoleValue = getConsoleSetting<T>(settings, consoleId, key);
      if (consoleValue != null) return consoleValue;
    }
    return getGeneralSetting<T>(settings, key);
  }

  Future<String?> selectDownloadDirectory() async {
    return await _directoryService.selectDownloadDirectory();
  }
}
```

- [ ] **Step 6: Pass the vault through the provider**

In `lib/providers/settings_provider.dart`, the provider gains the vault:

```dart
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(ref.watch(vaultProvider.future).then((choice) => choice.vault));
});
```

with the new imports:

```dart
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
```

In `SettingsNotifier`, the top of the class:

```dart
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _settingsService = SettingsService();
  final Future<SecretVault> _vault;

  SettingsNotifier(this._vault) : super(const AppSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsService.loadSettings(await _vault);
    state = settings;
  }

  /// Swaps the state and saves.
  Future<void> _persist(AppSettings next) async {
    state = next;
    await _settingsService.saveSettings(next, await _vault);
  }
```

Now swap, in the **eleven** sites, the pair

```dart
    state = newState;
    await _settingsService.saveSettings(newState);
```

for

```dart
    await _persist(newState);
```

Check that zero remain:

```bash
grep -c "saveSettings(newState)" lib/providers/settings_provider.dart
```

Expected: `0`.

Finally, the two methods that clear a credential start clearing for real:

```dart
  Future<void> setConsoleAuthToken(String consoleId, String token) async {
    final current = state.consoleSettings[consoleId] ?? const BaseSettings();
    final updated = token.isEmpty
        ? current.copyWith(clearAuthToken: true)
        : current.copyWith(authToken: token);
    if (token.isEmpty) {
      // `saveSettings` on purpose does not delete what is null. Logging out has
      // to delete, and it is here that this is said.
      await _settingsService.clearConsoleToken(consoleId, await _vault);
    }
    await _persist(state.copyWith(
      consoleSettings: {...state.consoleSettings, consoleId: updated},
    ));
  }

  Future<void> clearIaCredentials() async {
    await _settingsService.clearIaSecrets(await _vault);
    await _persist(state.copyWith(clearIaCredentials: true));
  }
```

- [ ] **Step 7: Run to see it pass**

```bash
flutter test test/settings_model_secrets_test.dart test/settings_service_test.dart
```

Expected: `+13`, zero failures.

**Likely pitfall:** the case "loading does not rewrite app_settings when there was no secret" fails on a formatting difference, and not a content one, if the test's `_appSettings()` was written by hand instead of by `jsonEncode`. The comparison is between two `jsonEncode` outputs over the same map, which are identical character by character; hand-typed text with a space after the colon is not.

- [ ] **Step 8: Run the whole suite**

```bash
flutter test
```

Expected: `+402`, zero failures.

If some **old** test breaks here, read before fixing: it may be a test that asserted the token went into the JSON, and then it was right yesterday and is wrong today. Fix the test saying why in the commit. If it is a test that does not talk about a secret, it is your regression.

- [ ] **Step 9: Analyze and build**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found` and build ok.

- [ ] **Step 10: Commit**

```bash
git add test/settings_model_secrets_test.dart test/settings_service_test.dart
git commit -m "test(cofre): segredo sai do app_settings e passa a morar no cofre"
git add lib/models/settings_model.dart lib/services/settings_service.dart lib/providers/settings_provider.dart
git commit -m "feat(cofre): segredo sai do app_settings e passa a morar no cofre"
```

---

### Task 7: the token stops coming from the file, in the four sites

**Files:**
- Create: `lib/utils/console_auth.dart`
- Modify: `lib/utils/network.dart:41`
- Modify: `lib/services/task_queue_service.dart:20`
- Modify: `lib/screens/tinfoil_server_screen.dart:91`
- Modify: `lib/screens/setup_wizard_screen.dart:392`
- Test: `test/console_auth_test.dart`

This is the Task that truly closes the leak, and it is the half of 6.3 that holds on every platform, with a keyring or without.

The spec lists two sites. There are **four**. The two it does not list do not build a header: they decide whether the screen shows the console as connected, with the same expression copied in both files. If they stay, the app starts saying "this console has auth configured" based on a field that nobody else reads to authenticate. It is not a leak, it is an interface lie, and it drops off the radar of any `grep` for `buildConsoleAuthHeaders`.

The two become a single function, in a new file, because a duplicated expression in two screens was exactly what made the spec count two instead of four.

- [ ] **Step 1: Write the failing test**

Create `test/console_auth_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/utils/console_auth.dart';
import 'package:roms_downloader/utils/network.dart';

void main() {
  group('buildConsoleAuthHeaders', () {
    test('the token in the catalog is ignored', () {
      // The section 6.3 flaw, literal. The catalog is the file the user sends to
      // someone else; nothing encrypts it and nothing warns it has a secret
      // inside. After this Task it may even contain the field, which
      // authenticates nobody.
      final headers = buildConsoleAuthHeaders({'token': 'tok-from-file'});

      expect(headers, isEmpty);
    });

    test('the caller token builds a Bearer', () {
      final headers = buildConsoleAuthHeaders({}, tokenOverride: 'tok-from-vault');

      expect(headers, {'Authorization': 'Bearer tok-from-vault'});
    });

    test('with cookies, builds Cookie with the catalog name', () {
      final headers = buildConsoleAuthHeaders(
        {'cookies': true, 'cookie_name': 'ultranx_session'},
        tokenOverride: 'tok-from-vault',
      );

      expect(headers, {'Cookie': 'ultranx_session=tok-from-vault'});
    });

    test('with no cookie_name, the default name is auth_token', () {
      final headers = buildConsoleAuthHeaders({'cookies': true}, tokenOverride: 'tok-from-vault');

      expect(headers, {'Cookie': 'auth_token=tok-from-vault'});
    });

    test('ia_s3 builds no header even with a caller token', () {
      // The Internet Archive signs another way, and a Bearer here would break
      // the download instead of authenticating.
      final headers = buildConsoleAuthHeaders({'type': 'ia_s3'}, tokenOverride: 'tok-from-vault');

      expect(headers, isEmpty);
    });

    test('a console with no auth builds no header', () {
      expect(buildConsoleAuthHeaders(null, tokenOverride: 'tok-from-vault'), isEmpty);
    });
  });

  group('consoleHasToken', () {
    test('the catalog token does not count as connected', () {
      // This is the case the spec does not list. Without it, the Tinfoil screen
      // and the wizard show "connected" reading a field that the whole Task just
      // took out of the authentication path.
      const settings = AppSettings();

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });

    test('the settings token counts', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: 'tok-from-vault')});

      expect(consoleHasToken(settings, 'ultranx'), isTrue);
    });

    test('an empty token does not count', () {
      const settings = AppSettings(consoleSettings: {'ultranx': BaseSettings(authToken: '')});

      expect(consoleHasToken(settings, 'ultranx'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/console_auth_test.dart
```

Expected: a compilation error in `console_auth.dart`. After creating the file, the first `buildConsoleAuthHeaders` case fails with `Expected: empty, Actual: {'Authorization': 'Bearer tok-from-file'}`, which is 6.3 in one line.

- [ ] **Step 3: Cut the file term in `network.dart`**

In `lib/utils/network.dart`, line 41, swap

```dart
  final token = tokenOverride ?? auth['token'] as String?;
```

for

```dart
  // Only from the caller, who read it from the vault. Before there was
  // `?? auth['token']`, that is, the catalog, which is the file the user shares
  // with someone else (section 6.3 of the spec). The field may keep existing in
  // a third party's JSON: it simply authenticates nobody anymore.
  final token = tokenOverride;
```

- [ ] **Step 4: Cut the middle term in `task_queue_service.dart`**

Line 20, swap

```dart
      final token = settings.consoleSettings[console.id]?.authToken ?? console.auth?['token'] as String? ?? '';
```

for

```dart
      final token = settings.consoleSettings[console.id]?.authToken ?? '';
```

- [ ] **Step 5: Create the shared predicate**

Create `lib/utils/console_auth.dart`:

```dart
import 'package:roms_downloader/models/settings_model.dart';

/// Whether the app has a token for this console.
///
/// Serves for the UI to decide whether to show the console as connected. Reads
/// **only** the settings, which since Task 6 come from the vault.
///
/// It exists as a function instead of an inline expression because the
/// expression was copied in two screens, and it was that duplication that made
/// section 6.3 of the spec count two sites when there are four: a `grep` for
/// `buildConsoleAuthHeaders` finds neither of the two.
bool consoleHasToken(AppSettings settings, String consoleId) => settings.consoleSettings[consoleId]?.authToken?.isNotEmpty ?? false;
```

- [ ] **Step 6: Swap the two screens**

In `lib/screens/tinfoil_server_screen.dart`, line 91, delete the whole `bool authed(Console c) => ...` and swap the uses of `authed(c)` for `consoleHasToken(settings, c.id)`. Same thing in `lib/screens/setup_wizard_screen.dart`, line 392. The two files gain:

```dart
import 'package:roms_downloader/utils/console_auth.dart';
```

Check that none of the four remain:

```bash
grep -rnE "auth\??\['token'\]" lib/
```

Expected: **exactly one line**, the comment Step 3 just wrote in `lib/utils/network.dart:41`, which cites `` `?? auth['token']` `` between backticks to record what was there. It is text, not a read. Check by looking at the line, not just by counting. Any second line is a live site that remained.

If any shows up in `console_model.dart`, read before fixing. The model's `toJson`/`fromJson` keeps knowing how to load the field, and that is right. But `Console.hasTokenAuth` (`console_model.dart:55-59`) also reads `auth!.containsKey('token')`, and that is **not** a site of this Task: it does not ask "what is the token", it asks "does this console accept a token", which is a capability declared by the catalog and not a secret. Whoever touches it is Task 8, which swaps the question for `requires_token`. Do not anticipate it here.

**The `-E` is mandatory, it is not style.** Without it the `grep` is BRE, and then `\?` becomes a quantifier over the `h` of `auth` while the second `?` becomes a literal: the pattern starts to require a `?` after `auth`, and **the only three sites that match are the ones with `auth?[`**. The fourth, `network.dart:41`, writes `auth['token']` without `?` and escapes. Measured before the Task ran, with the four still in place: BRE found three, `-E` found four. It means the BRE check would give "no lines" even for someone who forgot Step 3, which is precisely the site that section 6.3 lists.

- [ ] **Step 7: Run to see it pass**

```bash
flutter test test/console_auth_test.dart
```

Expected: `+9`, zero failures. It is the six `buildConsoleAuthHeaders` cases plus the three `consoleHasToken`, which is what the Step 1 block has. This number was once written as `+11` and was wrong: whoever closes the count is Step 8, and `402 + 9 = 411` matches, while `402 + 11` would give 413. Fixed after measuring `+9: All tests passed!` in the isolated file.

**Likely pitfall:** `flutter analyze` flagging `unused_local_variable` for the `settings` of `setup_wizard_screen.dart`, if the two screens used `settings` only inside `authed`. If it happens, `consoleHasToken(settings, c.id)` still needs it, so the warning means you swapped for something else.

- [ ] **Step 8: Run the whole suite**

```bash
flutter test
```

Expected: `+411`, zero failures.

- [ ] **Step 9: Analyze and build**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found`, build ok.

- [ ] **Step 10: Commit**

```bash
git add test/console_auth_test.dart
git commit -m "test(seguranca): token de autenticacao para de vir do catalogo compartilhado"
git add lib/utils/console_auth.dart lib/utils/network.dart lib/services/task_queue_service.dart lib/screens/tinfoil_server_screen.dart lib/screens/setup_wizard_screen.dart
git commit -m "feat(seguranca): token de autenticacao para de vir do catalogo compartilhado"
```

---

### Task 8: installing a catalog harvests the token and cleans the file

**Files:**
- Modify: `lib/services/catalog_service.dart:109-135`
- Modify: `lib/models/console_model.dart:55-59`
- Modify: `lib/screens/setup_wizard_screen.dart:94` and `:108`
- Modify: `lib/widgets/settings/catalog_source_setting.dart:74` and `:82`
- Test: `test/catalog_auth_token_test.dart`

Task 7 made the file token stop authenticating. This one makes it stop **existing** in the saved file. The spec writes both halves: "On install, if the JSON comes with `auth.token` filled, the app moves it to `flutter_secure_storage` and zeroes it in the saved file. On export, remove it."

Three scope notes, measured:

- **There is no catalog export today.** `grep -rni "export" lib/ --include=*.dart` only finds the favorites, which are another thing. The "on export, remove" half has no site in this slice. Group 6 closes that from another angle, with the RTS contract test, which is the only producer of this format in the app.
- **`addConsole` cannot carry a token today.** It passes the `Console.toJson()` forward, and the screen that builds that console (`add_catalog_source_screen.dart`) has no `auth` field: `grep -n "auth" lib/screens/add_catalog_source_screen.dart` returns nothing. If it ever does, the harvest has to pass through there too.
- **Removing the `token` key erases the login screen, and that is why the harvest leaves a mark in its place.** This is not a detail: it is the side effect that would turn this Task into a silent regression. `Console.hasTokenAuth` (`console_model.dart:55-59`) answers `auth!.containsKey('token') || auth!.containsKey('auth_message')`, and that getter has three readers (`grep -rn "hasTokenAuth" lib/`): it decides whether the "Authentication" section shows up in the settings (`settings_content.dart:152`), whether `task_queue_service` blocks a download with no token (`task_queue_service.dart:18`) and which consoles the Tinfoil screen lists as needing a login (`tinfoil_server_screen.dart:86`). A private catalog whose auth block is only `{'token': 'x'}`, which is the exact case slice 4 exists for, would end up after the harvest with an empty `auth`: gone was the screen where the user types the token, and gone was the block that warns a token is missing. The user would lose the auth and the app would say nothing. That is why the harvest writes `requires_token: true` whenever it removes the key, and the getter starts accepting that mark. The mark **is not a secret**: it says the console asks for a token, not what it is. It can go to the shared file freely, and it is precisely where it needs to be, because it is the file that describes the console.

- [ ] **Step 1: Write the failing test**

Create `test/catalog_auth_token_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

void main() {
  test('the token leaves the saved catalog', () async {
    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'url': 'https://ultranx.example/',
          'auth': {'token': 'tok-secret', 'cookies': true},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    expect(cleaned, isNot(contains('tok-secret')));
  });

  test('the harvested token goes to the vault, keyed by addon and console', () async {
    final vault = MemoryVault();

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secret'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-secret');
  });

  test('the rest of auth survives', () async {
    // Cleaning too much here breaks the login: `cookies`, `cookie_name`, `signin`
    // and `message` are catalog configuration, not a secret.
    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {
            'token': 'tok-secret',
            'cookies': true,
            'cookie_name': 'ultranx_session',
            'message': 'Sign in to download',
          },
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(cleaned) as List).first['auth'] as Map;
    expect(auth['cookies'], isTrue);
    expect(auth['cookie_name'], 'ultranx_session');
    expect(auth['message'], 'Sign in to download');
    expect(auth.containsKey('token'), isFalse);
    expect(auth['requires_token'], isTrue);
  });

  test('the cleaned console still declares it asks for a token', () async {
    // The case that makes this Task a fix and not a regression. Without the
    // mark, a console whose auth block was only the token ends up with an empty
    // `auth`, `hasTokenAuth` becomes false, and the user loses at once the
    // screen where they would type the token and the warning that a token is
    // missing. They would see a private source failing silently.
    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secret'},
        },
      ]),
      vault: MemoryVault(),
      addonId: 'ultranx',
    );

    final auth = (jsonDecode(cleaned) as List).first['auth'] as Map<String, dynamic>;
    final console = Console(id: 'ultranx', name: 'UltraNX', urls: const [], auth: auth);

    expect(console.hasTokenAuth, isTrue);
  });

  test('a console with no auth passes through intact', () async {
    final original = jsonEncode([
      {'name': 'Nintendo 64', 'url': 'https://example/n64/'},
    ]);

    final cleaned = await CatalogService.harvestAuthTokens(original, vault: MemoryVault(), addonId: 'x');

    expect(jsonDecode(cleaned), jsonDecode(original));
  });

  test('the legacy map format is also cleaned', () async {
    // The app accepts both forms (`catalog_service.dart:79-100`). Cleaning only
    // the array one would leave the hole open for whoever uses the old one,
    // which is exactly who has an older catalog.
    final vault = MemoryVault();

    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode({
        'ultranx': {
          'name': 'UltraNX',
          'auth': {'token': 'tok-secret'},
        },
      }),
      vault: vault,
      addonId: 'meu_addon',
    );

    expect(cleaned, isNot(contains('tok-secret')));
    expect(await vault.read(SecretRef.addonToken('meu_addon', 'ultranx')), 'tok-secret');
  });

  test('empty token does not create a vault key but leaves the requires_token mark', () async {
    // `{'token': ''}` means "needs a token, mine is not included": nothing to
    // store, but the mark must stay or the login screen never appears.
    final vault = MemoryVault();

    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': '', 'cookies': true},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), isNull);
    expect((jsonDecode(cleaned) as List).first['auth']['requires_token'], isTrue);
  });

  test('discovery entry also loses its token', () async {
    // `list_systems: true` entries do not become consoles, but the shared file
    // is the same object and the token leaks just the same. It is stored under
    // the name-derived id so it is not lost if the app ever uses these entries.
    final vault = MemoryVault();

    final cleaned = await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'Discovery',
          'list_systems': true,
          'auth': {'token': 'tok-discovery'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(cleaned, isNot(contains('tok-discovery')));
    expect(await vault.read(SecretRef.addonToken('ultranx', 'discovery')), 'tok-discovery');
  });

  test('vault already filled beats the file', () async {
    // Same rule as migration: reinstalling an old catalog must not replace a
    // token the user already updated.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'ultranx'), 'tok-new');

    await CatalogService.harvestAuthTokens(
      jsonEncode([
        {
          'name': 'UltraNX',
          'auth': {'token': 'tok-old'},
        },
      ]),
      vault: vault,
      addonId: 'ultranx',
    );

    expect(await vault.read(SecretRef.addonToken('ultranx', 'ultranx')), 'tok-new');
  });

  test('unknown JSON format is returned as-is', () async {
    // Format validation belongs to `setCatalogFromJson`, with its own error
    // message. The harvest must not throw first and replace that message with a
    // stack trace.
    const raw = '"this is not a catalog"';

    expect(await CatalogService.harvestAuthTokens(raw, vault: MemoryVault(), addonId: 'x'), raw);
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/catalog_auth_token_test.dart
```

Expected: `Undefined name 'harvestAuthTokens'`.

- [ ] **Step 3: Implement the harvest**

In `lib/services/catalog_service.dart`, add the imports

```dart
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/secret_vault.dart';
```

and the static method, right above `setCatalogFromJson`:

```dart
  /// Takes `auth.token` out of the whole catalog and stores what it found in
  /// the vault.
  ///
  /// The catalog is the file the user shares with someone else. The format
  /// allows a token inside, and section 6.3 of the spec orders it moved to the
  /// vault on install. This is the half of the fix that holds on every
  /// platform: taking it out of the file does not depend on there being a
  /// keyring.
  ///
  /// Where there was a `token`, it leaves `requires_token: true`. The mark is
  /// not a secret: it says the console asks for a token, not what it is, and the
  /// file that describes the console is exactly its place. Without the mark,
  /// [Console.hasTokenAuth] would become false and the user would lose the
  /// screen where they would type the token.
  ///
  /// Returns the clean JSON. Does not validate the format: whoever validates is
  /// [setCatalogFromJson], which has its own error message, and raising here
  /// would swap that message for a stack trace.
  static Future<String> harvestAuthTokens(String jsonStr, {required SecretVault vault, required String addonId}) async {
    final decoded = jsonDecode(jsonStr);

    Future<void> harvest(String id, Map<dynamic, dynamic> item) async {
      final auth = item['auth'];
      if (auth is! Map) return;
      if (!auth.containsKey('token')) return;
      final token = auth.remove('token');
      // The marker replaces `containsKey`, not the value, so it stays even when
      // the token is empty.
      auth['requires_token'] = true;
      if (token is! String || token.isEmpty) return;
      final key = SecretRef.addonToken(addonId, id);
      // What is already in the vault is the newest: reinstalling an old catalog
      // must not restore a token the user has since rotated.
      if (await vault.read(key) != null) return;
      await vault.write(key, token);
    }

    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map) continue;
        final name = item['name'] as String? ?? '';
        if (name.isEmpty) continue;
        // Discovery entries (`list_systems`) still pass through here: a token
        // inside one leaks just the same.
        await harvest(_nameToId(name), item);
      }
    } else if (decoded is Map) {
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        await harvest(entry.key.toString(), value);
      }
    } else {
      return jsonStr;
    }

    return jsonEncode(decoded);
  }
```

- [ ] **Step 4: The model starts to see the mark**

In `lib/models/console_model.dart`, line 58, swap

```dart
    return auth!.containsKey('token') || auth!.containsKey('auth_message');
```

for

```dart
    // `requires_token` is what the install harvest leaves in place of the token
    // it took out (`CatalogService.harvestAuthTokens`). Without it, a private
    // catalog whose auth block was only the token would end up with no mark at
    // all after installed, and this getter would start answering "does not ask
    // for a token" for the console that asks most.
    return auth!['requires_token'] == true || auth!.containsKey('token') || auth!.containsKey('auth_message');
```

The `containsKey('token')` stays. It still answers for two live cases: the embedded catalog that never went through the harvest, and the file the user opened by hand. Swapping instead of adding would break both.

Note that the `ia_s3` guard, two lines above, keeps exiting first: an Internet Archive console with a token inside is harvested the same, and even so `hasTokenAuth` stays false for it, because its signature is another. That behavior does not change.

- [ ] **Step 5: Wire it into the install**

Still in `catalog_service.dart`, the two install doors start requiring the vault:

```dart
  Future<void> setCatalogFromJson(String jsonStr, {required SecretVault vault, required String addonId}) async {
    final cleaned = await harvestAuthTokens(jsonStr, vault: vault, addonId: addonId);
    final consoles = _parseConsoles(cleaned);
    if (consoles.isEmpty) {
      throw const FormatException('No consoles found in the provided catalog.');
    }
    final file = await _userConsolesFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(cleaned);
    _consolesCache.clear();
  }
```

and `setCatalogFromUrl` forwards:

```dart
  Future<void> setCatalogFromUrl(String url, {required SecretVault vault, required String addonId}) async {
```

with the internal call becoming `await setCatalogFromJson(body, vault: vault, addonId: addonId);`.

Note the order: **harvest before validating**. If it validated first, an invalid catalog with a token inside would let the token pass through the app's hands without going anywhere, and the user would reinstall the corrected version already without it.

- [ ] **Step 6: Adjust the five callers**

There are five, all in a widget with `ref` at hand. In `lib/screens/setup_wizard_screen.dart:94`, `:101` and `:108`, and in `lib/widgets/settings/catalog_source_setting.dart:74` and `:82`, each call gains the vault. The `:101` is the wizard's `setCatalogFromUrl`: Step 5 swaps its signature, so that site does not compile without the vault, it is not optional. An earlier version of this text said "four" and omitted it.

```dart
final vault = (await ref.read(vaultProvider.future)).vault;
await _installCatalog(() => _catalogService.setCatalogFromJson(
      File(path).readAsStringSync(),
      vault: vault,
      addonId: SettingsService.builtinAddonId,
    ));
```

The two files gain:

```dart
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/settings_service.dart';
```

The `addonId` is `builtinAddonId` because, until Group 3, there is a single source. And **these two sites stay the builtin after it too**: installing a catalog from the Tools screen is installing the embedded addon's catalog, today and at the end of the slice. Whoever passes a real addon id to `harvestAuthTokens` is Task 21, through URL install, and it is there that two addons serving the same console stop sharing a token.

- [ ] **Step 7: Run to see it pass**

```bash
flutter test test/catalog_auth_token_test.dart
```

Expected: `+10`, zero failures.

- [ ] **Step 8: Run the whole suite**

```bash
flutter test
```

Expected: `+421`, zero failures. `test/add_catalog_source_screen_test.dart` and `test/catalog_add_console_test.dart` touch this path: if they break because of the new signature, the fix is to pass a `MemoryVault()`, not to loosen the signature.

**Likely pitfall:** an old `Console` test that asserts equality of the whole `auth` map after an install starts seeing the extra `requires_token` key. Check with `grep -rn "requires_token\|'auth'" test/ | grep -v catalog_auth_token`. If it shows up, the fix is to add the key to the expectation, not to stop writing it: without it the console loses the login screen.

- [ ] **Step 9: Analyze and build**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found`, build ok.

- [ ] **Step 10: Commit**

```bash
git add test/catalog_auth_token_test.dart
git commit -m "test(seguranca): instalar catalogo colhe o token para o cofre e limpa o arquivo"
git add lib/services/catalog_service.dart lib/models/console_model.dart lib/screens/setup_wizard_screen.dart lib/widgets/settings/catalog_source_setting.dart
git commit -m "feat(seguranca): instalar catalogo colhe o token para o cofre e limpa o arquivo"
```

**End of Group 2.** Section 6.3 is fulfilled, **with the caveat that the locked decision forces us to repeat**: the token left the shareable file on every platform, and encryption at rest is best effort, which on a Linux with no keyring does not happen. Whoever reports only the first half is reporting makeup.

| Task | New | Cumulative |
| --- | --- | --- |
| 6, secret in the vault | 13 | 402 |
| 7, four sites | 9 | 411 |
| 8, harvest on install | 10 | 421 |

---

## Group 3: the addon model

Six Tasks, plus 11b, which the Task 9 review forced us to add and which only writes a test. Here the app stops having **one** catalog and starts having **N**, in an ordered list the user controls. It is the big part of the slice, and the order of the Tasks follows the same rule as Group 1: first what is pure Dart (9, 10, 12), then what touches disk and `shared_preferences` (11, 13, 14). The 11b sits between 11 and 12 because it closes two coverage holes in `addon_model.dart`, and Task 14 is the first to lean the draggable priority on those two functions.

The central problem of this group is not storing a list. It is this: **`Console.auth` is a single map, and `_fetchCatalog` passes a single `authToken` to all the urls of the console** (`catalog_service.dart:304-316` and `:344`). If two addons declare the same console, merging the two into a `Console` makes the second's urls be fetched with the first's token, and the user sees "HTTP 401" on a source they configured right. That is why the merge does not return only `Map<String, Console>`: it also returns, per console, the list of `ConsoleSource`, which is where auth starts living.

A scope decision that saves a lot of churn: **the embedded addon's catalog file stays `config/consoles.json`**. Only the new addons gain a file in `config/addons/<id>.json`. With that `setCatalogFromJson`, `addConsole`, `resetCatalog` and `hasUserCatalog` (`catalog_service.dart:170`, `:229`, `:249`, `:255`) keep pointing to the same file as always, and the Task 11 migration does not move a single byte on disk: it only writes a one-item list into `shared_preferences`. A migration that does not touch a file is a migration that has no way to lose the user's catalog.

### Task 8b: hydration stops inventing configuration

**Files:**
- Modify: `lib/models/settings_model.dart:129-146`
- Modify: `lib/services/settings_service.dart:63`
- Modify: `test/settings_service_test.dart:68-77` (comment only)
- Test: `test/settings_hydrate_test.dart`

This Task was not in the plan. It exists because the quality review of Task 6 found, through mutation, a behavior defect that Task 6 introduced and that no test caught.

**The defect.** `BaseSettings.copyWith` (`settings_model.dart:140-142`) is not an innocent `copyWith`:

```dart
      autoExtract: autoExtract ?? this.autoExtract ?? true,
      maxParallelDownloads: maxParallelDownloads ?? this.maxParallelDownloads ?? 5,
      maxParallelExtractions: maxParallelExtractions ?? this.maxParallelExtractions ?? 2,
```

It **materializes a default into a field that was `null`**. Task 6 put a call to it in `_hydrate` (`settings_service.dart:63`), which runs at every app opening, for every console that has a token in the vault. Result: the console gains an explicit override of `autoExtract: true`, `maxParallelDownloads: 5` and `maxParallelExtractions: 2` that the user never asked for, and that goes to disk on the next save, becoming permanent.

**Why it is not cosmetic.** `autoExtract` changes behavior. `download_provider.dart:230` calls `getAutoExtract(game.consoleId)`, and `getSetting` (`settings_service.dart`) consults the console **before** the general. So the user turns off auto extraction in the general, and the only effect of having a login on a console is that that console goes back to extracting on its own, silently, at every opening.

**What is new and what is not, precisely.** The mechanism is old: `setConsoleAuthToken` already did `copyWith(authToken: token)` before Task 6, checked in `git show 058cef5~1:lib/providers/settings_provider.dart`. But there it fires **on a user action**, once, on the screen where they are touching configuration. What Task 6 added is the firing **on every load**. And Task 8 makes it worse: with the harvest, the token reaches the vault without the user ever having opened the login screen, so hydration starts inventing configuration for a console the user never touched. Do not touch the `copyWith` to fix this: the form path wants the materialized default. What is wrong is the new caller.

- [ ] **Step 1: Write the failing test**

Create `test/settings_hydrate_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// File of someone who configured the general and did **not** configure the
/// console.
///
/// `autoExtract: false` in the general is what makes the defect visible: if
/// hydration invents `autoExtract: true` on the console, the console starts to
/// win over the general, because `getSetting` consults the console first.
String _file() => jsonEncode({
      'consoleSettings': {
        'snes': {'downloadDir': '/roms/snes'},
      },
      'generalSettings': {'downloadDir': '/home/user/roms', 'autoExtract': false, 'maxParallelDownloads': 10},
    });

Future<void> _prefsWith(String appSettings) async {
  SharedPreferences.setMockInitialValues({'app_settings': appSettings});
  SharedPreferences.resetStatic();
}

Future<SecretVault> _vaultWithSnesToken() async {
  final vault = MemoryVault();
  await vault.write(SecretRef.addonToken(SettingsService.builtinAddonId, 'snes'), 'tok-snes');
  return vault;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the console with a token in the vault does not gain an unrequested `autoExtract`', () async {
    await _prefsWith(_file());

    final settings = await SettingsService().loadSettings(await _vaultWithSnesToken());

    expect(settings.consoleSettings['snes']?.autoExtract, isNull);
    expect(SettingsService().getSetting<bool>(settings, AppSettings.autoExtract, 'snes'), isFalse);
  });

  test('the console with a token in the vault does not gain the two parallelism limits', () async {
    await _prefsWith(_file());

    final settings = await SettingsService().loadSettings(await _vaultWithSnesToken());

    expect(settings.consoleSettings['snes']?.maxParallelDownloads, isNull);
    expect(settings.consoleSettings['snes']?.maxParallelExtractions, isNull);
    expect(SettingsService().getSetting<int>(settings, AppSettings.maxParallelDownloads, 'snes'), 10);
  });

  test('hydration still delivers the token and what the user configured', () async {
    // The control. Without it, deleting the whole hydration would make the two
    // cases above pass, and they are assertions about absence.
    await _prefsWith(_file());

    final settings = await SettingsService().loadSettings(await _vaultWithSnesToken());

    expect(settings.consoleSettings['snes']?.authToken, 'tok-snes');
    expect(settings.consoleSettings['snes']?.downloadDir, '/roms/snes');
  });

  test('saving with an empty secret does not delete what is in the vault', () async {
    // The `value.isEmpty` guard of `_writeIfPresent`. Without it, `vault.write`
    // with an empty string becomes `delete` (`secret_vault.dart:38-41`), and a
    // common save would delete the credential.
    await _prefsWith(_file());
    final vault = MemoryVault();
    await vault.write(SecretRef.iaAccessKey, 'AK');

    await SettingsService().saveSettings(const AppSettings(iaAccessKey: ''), vault);

    expect(await vault.read(SecretRef.iaAccessKey), 'AK');
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/settings_hydrate_test.dart
```

Expected: the first two cases fail with `Expected: null, Actual: <true>` and `Expected: null, Actual: <5>`. The third and fourth already pass: they lock what is already right, so that the fix does not break them.

- [ ] **Step 3: Give `BaseSettings` a copy that invents nothing**

In `lib/models/settings_model.dart`, right after `copyWith`, add:

```dart
  /// Returns a copy with the token swapped and **nothing else**.
  ///
  /// It exists because [copyWith] materializes a default into a `null` field
  /// (`autoExtract ?? this.autoExtract ?? true`, and the two limits right
  /// below). In the form that is the desired behavior: the user is touching
  /// configuration and seeing the effective value is useful. In the vault
  /// hydration it is not: it runs at every app opening, and after Task 8 it runs
  /// also for a console the user never opened, so it would write an override
  /// nobody asked for. `autoExtract` even changes behavior, because `getSetting`
  /// consults the console before the general (`download_provider.dart:230`).
  BaseSettings withAuthToken(String token) => BaseSettings(
        downloadDir: downloadDir,
        autoExtract: autoExtract,
        maxParallelDownloads: maxParallelDownloads,
        maxParallelExtractions: maxParallelExtractions,
        extractToFolder: extractToFolder,
        authToken: token,
      );
```

- [ ] **Step 4: Swap the caller**

In `lib/services/settings_service.dart`, line 63, swap

```dart
      consoles[entry.key] = token == null ? entry.value : entry.value.copyWith(authToken: token);
```

for

```dart
      consoles[entry.key] = token == null ? entry.value : entry.value.withAuthToken(token);
```

- [ ] **Step 5: Fix the comment that promises too much**

In `test/settings_service_test.dart`, the case "loading does not rewrite app_settings when there was no secret" (lines 68-77) compares **content**, and when there is no secret `jsonEncode(cleaned)` is identical to `jsonEncode(raw)`. That is: it does not distinguish "did not write" from "wrote the same", and removing the `if` of `settings_service.dart:38` leaves it green. Measured through mutation. Swap its comment for:

```dart
    // The load runs on every opening. Rewriting always is a disk write for
    // nothing. ATTENTION to what this case locks and what it does not lock: it
    // compares content, and when there is no secret the clean JSON is identical
    // to the raw one, so it stays green both for "did not rewrite" and for
    // "rewrote the same". Measured through mutation: removing the `if` of
    // `settings_service.dart:38` does not take it down. Locking the act of
    // writing would require injecting `SharedPreferences` into `SettingsService`,
    // which today calls it directly; it is noted for slice 5.
```

- [ ] **Step 6: Run to see it pass**

```bash
flutter test test/settings_hydrate_test.dart test/settings_service_test.dart
```

Expected: `+13`, zero failures. It is the 4 from this file plus the 9 that `test/settings_service_test.dart` already has. This number was once written as `+17`, summing the 13 of the whole Task 6; wrong, because 4 of those 13 are in `test/settings_model_secrets_test.dart` (`git show --stat e7829f4`), which this command does not run. Fixed after measuring `+13: All tests passed!`.

- [ ] **Step 7: Run the whole suite**

```bash
flutter test
```

Expected: `+425`, zero failures.

- [ ] **Step 8: Analyze and build**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found`, build ok.

- [ ] **Step 9: Commit**

```bash
git add test/settings_hydrate_test.dart test/settings_service_test.dart
git commit -m "test(cofre): hidratar o token nao pode inventar configuracao de console"
git add lib/models/settings_model.dart lib/services/settings_service.dart
git commit -m "feat(cofre): hidratar o token nao pode inventar configuracao de console"
```

---

### Task 9: `Addon`, the model and the ordered list

**Files:**
- Create: `lib/models/addon_model.dart`
- Modify: `lib/services/settings_service.dart` (loses the duplicated constant), `lib/screens/setup_wizard_screen.dart`, `lib/widgets/settings/catalog_source_setting.dart`
- Test: `test/addon_model_test.dart`, and an adjustment in `test/settings_service_test.dart` and `test/settings_hydrate_test.dart`

The addon is deliberately thin: id, name and the origin url. No "enabled", because section 9 of the UI spec does not specify any toggle (`docs/stremio-de-jogos-ui.md:220-263` lists icon, name, coverage, account chip, drag handle and arrow, and nothing more), and no install date, because there is no screen that shows it and it would only serve to get in the way of testing.

The delicate point is the **id**. It is the key under which the addon's token was stored in the vault, in `SecretRef.addonToken(addonId, consoleId)` (Task 1). An id that changes between two installs of the same source leaves the token orphan in the vault and makes the user type again a secret they had already given. That is why `Addon.idFromUrl` normalizes scheme, `www.`, case, query, fragment and trailing slash.

- [ ] **Step 1: Write the failing test**

Create `test/addon_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';

void main() {
  group('Addon.idFromUrl', () {
    test('http and https of the same catalog share an id, and surrounding space is ignored', () {
      const cleaned = 'https://example.com/catalog.json';
      expect(Addon.idFromUrl('http://example.com/catalog.json'), Addon.idFromUrl(cleaned));
      // The `trim` matters: without it `Uri.tryParse` finds no host in a
      // space-padded url and the id becomes `https_example_com_catalog_json`.
      expect(Addon.idFromUrl('  $cleaned  '), Addon.idFromUrl(cleaned));
      // The literal pins the format; comparing id to id survives any slug change.
      expect(Addon.idFromUrl(cleaned), 'example_com_catalog_json');
    });

    test('trailing slash, query and fragment do not change the id', () {
      final base = Addon.idFromUrl('https://example.com/catalog/');
      expect(Addon.idFromUrl('https://example.com/catalog'), base);
      expect(Addon.idFromUrl('https://example.com/catalog?v=2'), base);
      expect(Addon.idFromUrl('https://example.com/catalog#top'), base);
    });

    test('www. and uppercase do not change the id', () {
      expect(Addon.idFromUrl('https://WWW.Example.COM/Catalog'), Addon.idFromUrl('https://example.com/catalog'));
    });

    test('two catalogs on the same host get different ids, and the port is part of the host', () {
      expect(Addon.idFromUrl('https://example.com/snes.json'), isNot(Addon.idFromUrl('https://example.com/nes.json')));
      // Two LAN servers on the same IP but different ports are two addons. With
      // the port out of the id they would share a vault key and the second
      // install's token would erase the first's.
      expect(Addon.idFromUrl('http://192.168.0.10:8080/f/0/'), isNot(Addon.idFromUrl('http://192.168.0.10:8081/f/0/')));
      expect(Addon.idFromUrl('https://example.com:8080/c.json'), isNot(Addon.idFromUrl('https://example.com/c.json')));
    });

    test('the built-in id: no url maps to it, and only it answers isBuiltin', () {
      expect(Addon.idFromUrl('https://builtin/'), isNot(kBuiltinAddonId));
      expect(const Addon(id: kBuiltinAddonId, name: 'Listing').isBuiltin, isTrue);
      expect(const Addon(id: 'ultranx', name: 'UltraNX').isBuiltin, isFalse);
    });

    test('a hostless url falls back to a text-derived id, not empty', () {
      expect(Addon.idFromUrl('    '), isNotEmpty);
    });
  });

  group('Addon json', () {
    test('round trip preserves id, name and url', () {
      const addon = Addon(id: 'ultranx', name: 'UltraNX', url: 'https://ultranx.example/catalog.json');
      final back = Addon.fromJson(addon.toJson());
      expect(back.id, addon.id);
      expect(back.name, addon.name);
      expect(back.url, addon.url);
    });

    test('with no name in the json, the name becomes the id', () {
      expect(Addon.fromJson({'id': 'ultranx'}).name, 'ultranx');
    });
  });

  group('ordered list', () {
    const a = Addon(id: 'a', name: 'A');
    const b = Addon(id: 'b', name: 'B');
    const c = Addon(id: 'c', name: 'C');

    test('upsertAddon appends at the end when the id is new', () {
      expect(upsertAddon([a, b], c).map((x) => x.id), ['a', 'b', 'c']);
    });

    test('upsertAddon replaces WITHOUT changing position', () {
      final out = upsertAddon([a, b, c], const Addon(id: 'b', name: 'B new'));
      expect(out.map((x) => x.id), ['a', 'b', 'c']);
      expect(out[1].name, 'B new');
    });

    test('removeAddon drops the requested one and keeps the rest in order', () {
      expect(removeAddon([a, b, c], 'b').map((x) => x.id), ['a', 'c']);
    });

    test('removeAddon with an unknown id leaves the list unchanged', () {
      expect(removeAddon([a, b], 'z').map((x) => x.id), ['a', 'b']);
    });

    test('reorderAddons moving down applies the ReorderableListView discount', () {
      // Dragging "a" to the end: the widget passes newIndex = 3, counting the
      // slot "a" itself will vacate.
      expect(reorderAddons([a, b, c], 0, 3).map((x) => x.id), ['b', 'c', 'a']);
    });

    test('reorderAddons moving up applies no discount', () {
      expect(reorderAddons([a, b, c], 2, 0).map((x) => x.id), ['c', 'a', 'b']);
    });

    test('reorderAddons with an out-of-range source index returns the same list', () {
      expect(reorderAddons([a, b], 5, 0).map((x) => x.id), ['a', 'b']);
    });
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/addon_model_test.dart
```

Expected: a compilation error, `Target of URI doesn't exist: 'package:roms_downloader/models/addon_model.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/models/addon_model.dart`:

```dart
import 'package:flutter/foundation.dart';

/// The id of the addon that represents the `consoles.json` the app already had.
///
/// It is not special in anything the user sees: it shows up in the list, can be
/// dragged and can be removed. The constant exists for a single reason, and it
/// is a security one: the token that Task 8 harvested was stored under
/// `SecretRef.addonToken('builtin', consoleId)`, so changing this value leaves
/// the user's secret orphan inside the vault.
const kBuiltinAddonId = 'builtin';

/// An installed catalog source, in the position the user put it.
///
/// The position in the list **is** the priority: it feeds the `sourcePriority`
/// of `planFromEntries` (`source_pick_service.dart:54`), which is the last
/// tiebreaker of section 6 of the UI spec. That is why the list is a `List` and
/// not a `Set` nor a map.
@immutable
class Addon {
  final String id;
  final String name;

  /// Where the catalog came from, when it came from a URL. It is `null` in the
  /// builtin and in a catalog imported from a file; in those cases the detail
  /// screen shows the origin in full instead of an address.
  final String? url;

  const Addon({required this.id, required this.name, this.url});

  bool get isBuiltin => id == kBuiltinAddonId;

  Addon copyWith({String? name, String? url}) => Addon(id: id, name: name ?? this.name, url: url ?? this.url);

  /// A stable id for the URL a catalog came from: scheme, `www.`, query and
  /// trailing slash all collapse to the same id, so reinstalling the same
  /// source finds the token already in the vault.
  ///
  /// Warning: the port is part of the id on purpose, via `hasPort` not `port`,
  /// so scheme-default ports stay collapsed while distinct ports stay distinct.
  static String idFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final raw = (uri == null || uri.host.isEmpty)
        ? url
        : '${uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    final slug = _slug(raw);
    return slug == kBuiltinAddonId ? '${slug}_1' : slug;
  }

  factory Addon.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return Addon(id: id, name: json['name'] as String? ?? id, url: json['url'] as String?);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, if (url != null) 'url': url};
}

String _slug(String text) {
  final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'addon' : cleaned;
}

/// Inserts [incoming]. If an addon with the same id exists, it is replaced in
/// place: reinstalling a source to fix its url must not demote its priority.
List<Addon> upsertAddon(List<Addon> list, Addon incoming) {
  final i = list.indexWhere((a) => a.id == incoming.id);
  if (i < 0) return [...list, incoming];
  final result = [...list];
  result[i] = incoming;
  return result;
}

List<Addon> removeAddon(List<Addon> list, String id) => [
      for (final a in list)
        if (a.id != id) a,
    ];

/// Moves an item with `ReorderableListView` semantics: a downward move's
/// `newIndex` already counts the vacated slot, so the real target is one less.
List<Addon> reorderAddons(List<Addon> list, int from, int to) {
  if (from < 0 || from >= list.length) return list;
  final result = [...list];
  final item = result.removeAt(from);
  final target = to > from ? to - 1 : to;
  result.insert(target.clamp(0, result.length), item);
  return result;
}
```

**Likely pitfall:** the `-1` of `ReorderableListView`. It is easy to write `result.insert(to, item)` and see the "going up" tests pass, because going up the discount does not exist. Only the going-down case catches it, and it is the case the user does first, because the new source is born at the end of the list and they want to promote it. The test "going down applies the discount" was written for this and does **not** do it, and this sentence already claimed it did. It moves to the end of the list, and then the `clamp` equalizes `to - 1` and `to`, so the assertion passes with the discount and without. What catches it is a **middle** destination, and it only enters in Task 11b. I leave the mistake written here instead of deleting the sentence, because a "Likely pitfall" that points at the wrong test is worse than none: it convinces the reader that the line is guarded.

- [ ] **Step 4: Take out the duplicated constant that Task 6 created**

Task 6 needed `'builtin'` before this Task existed and put it in `SettingsService.builtinAddonId`. Now there are two names for the same value, and two names for the same value is a bug waiting for someone to change only one. The canonical one is the `kBuiltinAddonId` of this file, because it lives with the concept.

In `lib/services/settings_service.dart`, delete the constant **with its doc**, which is eight lines:

```dart
  /// The addon that today's catalog consoles belong to.
  ///
  /// While there is a single source, this id is constant. When there are N
  /// addons, this mirror stays the builtin's only, and the token of the others
  /// starts being read on demand from the vault (Task 19). It lives here, and
  /// not in [SecretRef], because it is a fact about the installation and not
  /// about the key format.
  static const String builtinAddonId = 'builtin';
```

Deleting only the constant line leaves the doc hanging on the next member, and a doc that describes something else is worse than no doc.

add to the top

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

and swap the four internal uses of `builtinAddonId` for `kBuiltinAddonId`, on lines 31, 62, 97 and 113. There are four uses, and not five: the `grep` returns five lines in this file, but the first is the declaration you just deleted. On line 31 note that `builtinAddonId: builtinAddonId` has the name twice, and only the second is a use: the first is the label of `SecretMigration`'s parameter and does not change. Check with:

```bash
grep -rn "builtinAddonId" lib/ test/
```

Only occurrences of `kBuiltinAddonId` should remain, plus the `builtinAddonId` parameter of `SecretMigration` (`lib/services/secret_migration.dart`), which is a parameter name and not a constant, and keeps entering by injection.

The other four files that cite the constant swap along. **This list was remeasured after Task 8b entered**, and it changed: `test/catalog_auth_token_test.dart` was here by mistake and left, because it passes `addonId: 'ultranx'` as a literal and never cited the constant; `test/settings_hydrate_test.dart`, which Task 8b created after this text was written, entered, because it cites it on line 29. Check yourself with the `grep` above before editing, instead of trusting the table: Task 8b is recent and another Task may have touched it again.

| File | Measured occurrences | Swap |
| --- | --- | --- |
| `lib/screens/setup_wizard_screen.dart` | 3 | `SettingsService.builtinAddonId` becomes `kBuiltinAddonId` |
| `lib/widgets/settings/catalog_source_setting.dart` | 2 | same |
| `test/settings_service_test.dart` | 3 | same |
| `test/settings_hydrate_test.dart` | 1 | same |

**In the two test files the `settings_service.dart` import stays; in the two `lib/` ones it leaves.** The two test ones instantiate `SettingsService()` for real (`settings_service_test.dart:39` and nine others, `settings_hydrate_test.dart:39, 48, 60, 74`), so there the `addon_model.dart` import **adds** to what is already there. In the two `lib/` ones it does not: `SettingsService` appears in them **only** as `SettingsService.builtinAddonId`, three times in the wizard and twice in the widget, and nothing more. After the swap the import is dead and `flutter analyze` rises from 22 to 24, with two `unused_import`, which are warnings. Check instead of trusting this sentence: after the swap, `grep -n "SettingsService" lib/screens/setup_wizard_screen.dart lib/widgets/settings/catalog_source_setting.dart` has to return zero. Two versions of this text got it wrong here, in opposite directions: the first ordered swapping the import in the test files, which would leave the four not compiling; the second said that in none of the four the import left and claimed that had been measured, when only the two test ones had been measured and the two `lib/` ones were supposed. Measured in all four by the Task 9 implementer, and checked against `git show 824434e:` afterward.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addon_model_test.dart
```

Expected: `+15`, zero failures.

- [ ] **Step 6: Run the whole suite**

```bash
flutter test
```

Expected: `+440`, zero failures. If `test/settings_service_test.dart` or `test/settings_hydrate_test.dart` go red, it is Step 4 half done: the constant swap has to be made in the five files, not only in the `lib/` ones.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`, none in `lib/models/addon_model.dart` nor in `test/addon_model_test.dart`. An `unused_import` here means the `settings_service.dart` import remained in one of the two `lib/` files that used it only for the constant, and not in a test file: the test ones keep needing it.

- [ ] **Step 8: Commit**

```bash
git add test/addon_model_test.dart test/settings_service_test.dart test/settings_hydrate_test.dart
git commit -m "test(addon): modelo de addon, id estavel por url e as operacoes da lista ordenada"
git add lib/models/addon_model.dart lib/services/settings_service.dart lib/screens/setup_wizard_screen.dart lib/widgets/settings/catalog_source_setting.dart
git commit -m "feat(addon): modelo de addon, id estavel por url e as operacoes da lista ordenada"
```

### Task 10: `console_merge.dart`, merging N catalogs without losing the auth

**Files:**
- Create: `lib/services/console_merge.dart`
- Modify: `lib/models/console_model.dart` (gains `withUrls`)
- Test: `test/console_merge_test.dart`

This is the Task that solves the central problem of the group. The merge returns two things: the `Map<String, Console>` that the whole app already consumes, and a `Map<String, List<ConsoleSource>>` that says, per console, which addon and with what auth each url came from.

The invariant that ties the two, and that Task 13 uses without checking at runtime: **for every id, `sources[id]!.map((s) => s.url)` equals `consoles[id]!.urls`, in the same order.** A test locks this.

- [ ] **Step 1: Write the failing test**

Create `test/console_merge_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {String? regex, Map<String, dynamic>? auth, String? name}) =>
    Console(id: id, name: name ?? id, urls: urls, regex: regex, auth: auth);

void main() {
  test('empty list yields empty catalog', () {
    final merged = mergeCatalogs(const []);
    expect(merged.consoles, isEmpty);
    expect(merged.sources, isEmpty);
    expect(merged.isEmpty, isTrue);
  });

  test('single addon: consoles pass through and each source carries the addon id', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
    expect(merged.sources['snes']!.single.addonId, 'one');
    expect(merged.sources['snes']!.single.url, 'https://a/');
  });

  test('console declared only by the second addon is included', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'])}),
      (addonId: 'two', consoles: {'nes': _console('nes', ['https://b/'])}),
    ]);
    expect(merged.consoles.keys, containsAll(['snes', 'nes']));
    expect(merged.sources['nes']!.single.addonId, 'two');
  });

  test('same console in both addons: metadata comes from the FIRST addon', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'], name: 'Super Nintendo', regex: 'FROM ONE')}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'], name: 'SNES', regex: 'FROM TWO')}),
    ]);
    expect(merged.consoles['snes']!.name, 'Super Nintendo');
    expect(merged.consoles['snes']!.regex, 'FROM ONE');
  });

  test('same console in both addons: urls concatenate in addon order', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/', 'https://a2/'])}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/', 'https://a2/', 'https://b/']);
  });

  test('duplicate url across addons enters once, from the first', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://same/'])}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://same/', 'https://other/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://same/', 'https://other/']);
    expect(merged.sources['snes']!.map((f) => f.addonId), ['one', 'two']);
  });

  test('duplicate url within the same addon enters once', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/', 'https://a/'])}),
    ]);
    expect(merged.consoles['snes']!.urls, ['https://a/']);
  });

  test('each source auth comes from the addon that declared that url', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'], auth: {'token': 'unused', 'cookies': true})}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'], auth: {'type': 'ia_s3'})}),
    ]);
    final sources = merged.sources['snes']!;
    expect(sources[0].auth!['cookies'], true);
    expect(sources[1].auth!['type'], 'ia_s3');
  });

  test('invariant: console urls match source urls in the same order', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/']), 'nes': _console('nes', ['https://n1/', 'https://n2/'])}),
      (addonId: 'two', consoles: {'snes': _console('snes', ['https://b/'])}),
    ]);
    for (final id in merged.consoles.keys) {
      expect(merged.sources[id]!.map((f) => f.url).toList(), merged.consoles[id]!.urls, reason: 'console $id');
    }
  });

  test('console with no urls enters with an empty source list', () {
    final merged = mergeCatalogs([
      (addonId: 'one', consoles: {'snes': _console('snes', const [])}),
    ]);
    expect(merged.consoles.containsKey('snes'), isTrue);
    expect(merged.sources['snes'], isEmpty);
  });

  test('addon with no consoles does not affect others', () {
    final merged = mergeCatalogs([
      (addonId: 'empty', consoles: const {}),
      (addonId: 'one', consoles: {'snes': _console('snes', ['https://a/'])}),
    ]);
    expect(merged.consoles.keys, ['snes']);
    expect(merged.sources['snes']!.single.addonId, 'one');
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/console_merge_test.dart
```

Expected: a compilation error, `Target of URI doesn't exist: 'package:roms_downloader/services/console_merge.dart'`.

- [ ] **Step 3: Give `Console` the copy with other urls**

In `lib/models/console_model.dart`, right after the `url` getter (line 51), add:

```dart
  /// A copy with another list of urls, and nothing else different.
  ///
  /// It exists only for `mergeCatalogs` (`console_merge.dart`), which appends
  /// the urls of another addon to the console without touching any other field.
  /// It is a single-field `copyWith` on purpose: a full `copyWith` of twenty-one
  /// fields would be twenty parameters nobody passes and one more place to
  /// forget to update when the `Console` grows.
  Console withUrls(List<String> next) => Console(
        id: id,
        name: name,
        urls: next,
        regex: regex,
        boxarts: boxarts,
        fileFormat: fileFormat,
        romsFolder: romsFolder,
        shouldUnzip: shouldUnzip,
        extractContents: extractContents,
        shouldFilterUsa: shouldFilterUsa,
        usaRegex: usaRegex,
        shouldDecompressNsz: shouldDecompressNsz,
        ignoreExtensionFiltering: ignoreExtensionFiltering,
        downloadUrl: downloadUrl,
        auth: auth,
        listUrl: listUrl,
        listJsonFileLocation: listJsonFileLocation,
        listItemId: listItemId,
        listSystems: listSystems,
        added: added,
        convert3dsToCia: convert3dsToCia,
      );
```

- [ ] **Step 4: Write the merge**

Create `lib/services/console_merge.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:roms_downloader/models/console_model.dart';

/// A catalog url, with which addon it came from and with what auth it talks.
///
/// It exists because `Console.auth` is a single map and `_fetchCatalog` passed
/// a single `authToken` to all the urls of the console (`catalog_service.dart:304`
/// and `:344`). With two addons serving the same console, that would send the
/// first's token to the second's server. The auth does not belong to the
/// console: it belongs to the url.
@immutable
class ConsoleSource {
  final String addonId;
  final String url;
  final Map<String, dynamic>? auth;

  const ConsoleSource({required this.addonId, required this.url, this.auth});
}

/// The app's catalog: the consoles the screen draws and, per console, where
/// each url came from.
///
/// **Invariant**, which the tests lock and which `_fetchCatalog` uses without
/// checking: for every id, `sources[id]!.map((s) => s.url)` equals
/// `consoles[id]!.urls`, in the same order. It is what allows iterating over the
/// sources instead of the urls without a translation table in between.
@immutable
class MergedCatalog {
  final Map<String, Console> consoles;
  final Map<String, List<ConsoleSource>> sources;

  const MergedCatalog({this.consoles = const {}, this.sources = const {}});

  bool get isEmpty => consoles.isEmpty;
}

/// An addon's catalog, already parsed.
typedef AddonCatalog = ({String addonId, Map<String, Console> consoles});

/// Merges the catalogs in the order they come, which is the priority order the
/// user dragged on the addons screen.
///
/// Three rules, all deriving from the order:
/// - the console metadata (name, regex, boxarts, formats) is from the **first**
///   addon that declared it. The second appends a url, it does not rewrite the
///   console. Without this, installing a new source would silently change how
///   the files of an old source are parsed.
/// - the urls concatenate in the addon order.
/// - a repeated url enters only once, from the first time it appeared. Two
///   addons pointing to the same server do not make the app fetch twice nor show
///   the game duplicated in the grid.
MergedCatalog mergeCatalogs(List<AddonCatalog> catalogs) {
  final consoles = <String, Console>{};
  final sources = <String, List<ConsoleSource>>{};

  for (final catalog in catalogs) {
    for (final entry in catalog.consoles.entries) {
      final id = entry.key;
      final console = entry.value;
      final existing = sources.putIfAbsent(id, () => <ConsoleSource>[]);
      final seenUrls = existing.map((f) => f.url).toSet();
      for (final url in console.urls) {
        if (!seenUrls.add(url)) continue;
        existing.add(ConsoleSource(addonId: catalog.addonId, url: url, auth: console.auth));
      }
      consoles[id] = (consoles[id] ?? console).withUrls([for (final f in existing) f.url]);
    }
  }

  return MergedCatalog(consoles: consoles, sources: sources);
}
```

**Likely pitfall:** deduplicating a url with a global `Set` instead of one per console. Two equal urls in different consoles are legitimate (a server that lists everything in the same directory), and a global `Set` would eat the second silently. The `jaTem` is recomputed inside each console's loop, from that console's sources, and that is why.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/console_merge_test.dart
```

Expected: `+11`, zero failures.

- [ ] **Step 6: Run the whole suite**

```bash
flutter test
```

Expected: `+451`, zero failures.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/console_merge_test.dart
git commit -m "test(addon): fusao de N catalogos preservando a auth por url"
git add lib/services/console_merge.dart lib/models/console_model.dart
git commit -m "feat(addon): fusao de N catalogos preservando a auth por url"
```

### Task 11: `AddonStore`, where the list and the catalogs live

**Files:**
- Create: `lib/services/addon_store.dart`
- Modify: `lib/services/settings_service.dart` (`_settingsKey` becomes `settingsKey`)
- Test: `test/addon_store_test.dart`

Two things to persist: the **ordered list**, which goes to a new `shared_preferences` key, and the **catalog of each addon**, which goes to disk.

The disk root enters via the constructor. This is not a taste for injection: `getApplicationSupportDirectory()` is `path_provider`, which in a test with no platform throws `MissingPluginException`. With the root injected, the tests use `Directory.systemTemp.createTemp()` and exercise real IO, which is what matters here, instead of simulating disk.

And the scope decision the group intro already announced: **the builtin stays in `config/consoles.json`**. `catalogFile` is the only function that knows this, and that is why it exists instead of a path concatenation scattered around.

- [ ] **Step 1: Write the failing test**

Create `test/addon_store_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('addon_store_test');
  addTearDown(() => root.delete(recursive: true));
  return AddonStore(await SharedPreferences.getInstance(), root);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migration', () {
    test('with no key, the list is just the built-in', () async {
      final store = await _store();
      final list = store.load();
      expect(list.map((a) => a.id), [kBuiltinAddonId]);
      expect(list.single.name, isNotEmpty);
    });

    test('reading does NOT write: the key stays absent after load', () async {
      final store = await _store();
      store.load();
      expect((await SharedPreferences.getInstance()).getString(AddonStore.prefsKey), isNull);
    });

    test('the built-in inherits the url saved in catalogSourceUrl', () async {
      final store = await _store({
        'app_settings': jsonEncode({'catalogSourceUrl': 'https://example.com/catalog.json'}),
      });
      expect(store.load().single.url, 'https://example.com/catalog.json');
    });

    test('unreadable app_settings does not break the migration', () async {
      final store = await _store({'app_settings': 'this is not json'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
      expect(store.load().single.url, isNull);
    });

    test('app_settings without catalogSourceUrl gives a built-in with no url', () async {
      final store = await _store({'app_settings': jsonEncode({'downloadDir': '/tmp'})});
      expect(store.load().single.url, isNull);
    });

    test('a corrupt list falls into migration instead of throwing', () async {
      final store = await _store({AddonStore.prefsKey: '{not a list}'});
      expect(store.load().map((a) => a.id), [kBuiltinAddonId]);
    });

    test('an item with no id is dropped and the rest of the list enters', () async {
      final store = await _store({
        AddonStore.prefsKey: jsonEncode([
          {'name': 'no id'},
          {'id': 'ultranx', 'name': 'UltraNX'},
        ]),
      });
      expect(store.load().map((a) => a.id), ['ultranx']);
    });
  });

  group('list', () {
    test('save and load close the cycle preserving order', () async {
      final store = await _store();
      await store.save(const [
        Addon(id: 'b', name: 'B'),
        Addon(id: kBuiltinAddonId, name: 'Built-in'),
        Addon(id: 'a', name: 'A', url: 'https://a/'),
      ]);
      final back = store.load();
      expect(back.map((x) => x.id), ['b', kBuiltinAddonId, 'a']);
      expect(back.last.url, 'https://a/');
    });

    test('saving an empty list is legitimate and does not return to migration', () async {
      final store = await _store();
      await store.save(const []);
      expect(store.load(), isEmpty);
    });
  });

  group('catalog on disk', () {
    test('the built-in lives in the usual consoles.json', () async {
      final store = await _store();
      expect(store.catalogFile(kBuiltinAddonId).path, endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}consoles.json'));
    });

    test('an installed addon lives in config/addons/<id>.json', () async {
      final store = await _store();
      expect(store.catalogFile('ultranx').path,
          endsWith('${Platform.pathSeparator}config${Platform.pathSeparator}addons${Platform.pathSeparator}ultranx.json'));
    });

    test('writeCatalog creates the directory and readCatalog reads it back', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[{"name":"SNES"}]');
      expect(await store.readCatalog('ultranx'), '[{"name":"SNES"}]');
    });

    test('readCatalog of an addon with no file returns null', () async {
      final store = await _store();
      expect(await store.readCatalog('ultranx'), isNull);
    });

    test('deleteCatalog deletes, and deleting what does not exist does not raise', () async {
      final store = await _store();
      await store.writeCatalog('ultranx', '[]');
      await store.deleteCatalog('ultranx');
      expect(await store.readCatalog('ultranx'), isNull);
      await store.deleteCatalog('ultranx');
    });
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/addon_store_test.dart
```

Expected: a compilation error, `Target of URI doesn't exist: 'package:roms_downloader/services/addon_store.dart'`.

- [ ] **Step 3: Open the settings key**

In `lib/services/settings_service.dart`, swap

```dart
  static const String _settingsKey = 'app_settings';
```

for

```dart
  /// The single key where the app stores the settings. Public because the addon
  /// migration (`addon_store.dart`) needs to read the pre-slice-4
  /// `catalogSourceUrl`, and a literal string repeated in the two files would be
  /// worse.
  static const String settingsKey = 'app_settings';
```

and swap the three internal uses of `_settingsKey` for `settingsKey`. Check:

```bash
grep -rn "_settingsKey" lib/
```

Expected: nothing.

- [ ] **Step 4: Write the store**

Create `lib/services/addon_store.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/settings_service.dart';

/// Where the addon list and each addon's catalog live.
class AddonStore {
  /// The `shared_preferences` key holding the serialized ordered list.
  static const String prefsKey = 'addons';

  final SharedPreferences _prefs;
  final Directory _root;

  AddonStore(this._prefs, this._root);

  static Future<AddonStore> open() async => AddonStore(
        await SharedPreferences.getInstance(),
        await getApplicationSupportDirectory(),
      );

  /// The installed list, in priority order.
  ///
  /// A missing key returns the migration list (the built-in alone) without
  /// writing: reading must not have a side effect. A saved empty list is a
  /// legitimate state, distinct from a missing key.
  List<Addon> load() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null) return [_migratedBuiltin()];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [_migratedBuiltin()];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic> && item['id'] is String) Addon.fromJson(item),
      ];
    } catch (e) {
      debugPrint('Unreadable addon list, falling back to migration: $e');
      return [_migratedBuiltin()];
    }
  }

  Future<void> save(List<Addon> list) async {
    await _prefs.setString(prefsKey, jsonEncode([for (final addon in list) addon.toJson()]));
  }

  /// The addon representing the pre-slice-4 `consoles.json`.
  Addon _migratedBuiltin() {
    String? url;
    try {
      final raw = _prefs.getString(SettingsService.settingsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        final value = decoded is Map ? decoded['catalogSourceUrl'] : null;
        if (value is String && value.isNotEmpty) url = value;
      }
    } catch (e) {
      debugPrint('Unreadable catalogSourceUrl during addon migration: $e');
    }
    return Addon(id: kBuiltinAddonId, name: 'Built-in catalog', url: url);
  }

  /// Where each addon's catalog lives.
  File catalogFile(String addonId) => addonId == kBuiltinAddonId
      ? File(path.join(_root.path, 'config', 'consoles.json'))
      : File(path.join(_root.path, 'config', 'addons', '$addonId.json'));

  Future<String?> readCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  Future<void> writeCatalog(String addonId, String jsonStr) async {
    final file = catalogFile(addonId);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonStr);
  }

  Future<void> deleteCatalog(String addonId) async {
    final file = catalogFile(addonId);
    if (await file.exists()) await file.delete();
  }
}
```

**Likely pitfall:** treating an absent key and an empty list as the same thing. If `load()` returned the builtin whenever the list came out empty, the user who removed all the addons on purpose would see the builtin resurrect on the next boot, and would have no way to prevent it. The test "saving an empty list is legitimate" locks exactly that difference, and it passes for free on the wrong implementation only if you test by the key and not by the size.

**Second pitfall:** `deleteCatalog(kBuiltinAddonId)` deletes `config/consoles.json`, which is the same file `resetCatalog` deletes. It is the correct behavior (removing the builtin addon is removing its catalog), but whoever calls it by accident loses the user's imported catalog. Task 14 only calls `deleteCatalog` on the explicit removal path.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addon_store_test.dart
```

Expected: `+14`, zero failures. It is 7 migration cases, 2 list ones and 5 disk ones. This number was once written as `+13`, and was wrong: I counted the `test(` of the Step 1 block and there are 14.

- [ ] **Step 6: Run the whole suite**

```bash
flutter test
```

Expected: `+465`, zero failures.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_store_test.dart
git commit -m "test(addon): persistencia da lista de addons e do catalogo de cada um"
git add lib/services/addon_store.dart lib/services/settings_service.dart
git commit -m "feat(addon): persistencia da lista de addons e do catalogo de cada um"
```

### Task 11b: the two cases the ordered list did not have

**Files:**
- Test: `test/addon_model_test.dart` (two new cases, nothing more)

This Task was born from the Task 9 review and does **not change a single line of production**. `upsertAddon` and `reorderAddons` are right; what is not is their coverage. That is why it has a single commit, `test(...)`, and no `feat(...)`: the rule of never mixing `lib/` and `test/` in a commit still holds, and here there simply is no `lib/` to commit.

The two holes were found through mutation, not through reading, and each is a mutant that survives the whole suite:

**First: `to - 1` can become `to` and nothing goes red.** The case that exists today is named `'reorderAddons going down applies the ReorderableListView discount'` and does `reorderAddons([a, b, c], 0, 3)`. It does not test the discount. Moving to the **end** erases the difference: with the source item removed two remain, and both `to - 1 = 2` and `to = 3` pass through the `clamp(0, 2)` and give 2. The case name promises one thing and the assertion locks another, which is the worst kind of test, because it looks like it covers. The discount only appears when the destination is a **middle** slot: in `[a, b, c, d]`, moving 0 to 2 gives `['b', 'a', 'c', 'd']` with the discount and `['b', 'c', 'a', 'd']` without. The plan claimed the opposite in a "Likely pitfall" of Task 9; the claim was wrong.

**Second: `i < 0` can become `i <= 0` and nothing goes red.** The case `'upsertAddon replaces WITHOUT changing the position'` replaces the addon at position 1. With `i = 1` the two operators agree. At position 0 they diverge, and position 0 is exactly the builtin's: under the mutant, reinstalling the addon in first place would not replace it, it would add a second copy at the end. That is a state the addons screen would show as two lines with the same id.

- [ ] **Step 1: Write the two cases**

In `test/addon_model_test.dart`, inside the same `group` where the `upsertAddon` and `reorderAddons` cases already are, add:

```dart
    test('upsertAddon replaces at position 0, the built-in slot', () {
      final out = upsertAddon([a, b, c], const Addon(id: 'a', name: 'A new'));
      expect(out.map((x) => x.id), ['a', 'b', 'c']);
      expect(out.first.name, 'A new');
    });

    test('reorderAddons moving down into the middle discounts the vacated slot', () {
      const d = Addon(id: 'd', name: 'D');
      expect(reorderAddons([a, b, c, d], 0, 2).map((x) => x.id), ['b', 'a', 'c', 'd']);
    });
```

The `const d` is local to the case on purpose: `a`, `b` and `c` already exist in the file and a fourth at the top would only serve this case.

- [ ] **Step 2: Prove each one catches its mutant**

This is not optional, and it is the reason the Task exists. A case that passes proves nothing; what proves is the case going red when the line it covers changes.

```bash
sed -i 's/final target = to > from ? to - 1 : to;/final target = to;/' lib/models/addon_model.dart
flutter test test/addon_model_test.dart 2>&1 | tr '\r' '\n' | tail -3
git checkout -- lib/models/addon_model.dart

sed -i 's/if (i < 0) return \[...list, incoming\];/if (i <= 0) return [...list, incoming];/' lib/models/addon_model.dart
flutter test test/addon_model_test.dart 2>&1 | tr '\r' '\n' | tail -3
git checkout -- lib/models/addon_model.dart
```

Expected: each of the two rounds fails, and fails **in the corresponding new case**, not in another. If any passes, the case is not catching what it says it catches and there is no point going on.

After the two, check that the restore was real before measuring anything:

```bash
git status --short lib/models/addon_model.dart
```

Expected: no line. An `M` here means a `git checkout --` did not run, and every number in the following Steps would be the mutant's.

- [ ] **Step 3: Run the file**

```bash
flutter test test/addon_model_test.dart
```

Expected: `+17`, zero failures. It is the 15 from Task 9 plus these 2.

- [ ] **Step 4: Run the whole suite**

```bash
flutter test
```

Expected: `+467`, zero failures.

- [ ] **Step 5: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 6: Commit**

```bash
git add test/addon_model_test.dart
git commit -m "test(addon): a substituicao na posicao 0 e o desconto de descida para o meio"
```

### Task 12: `Game.sourceId`, the game knows which addon it came from

**Files:**
- Modify: `lib/models/game_model.dart`
- Test: `test/game_source_id_test.dart`

Today's `Game` does not know where it came from (`game_model.dart:4-19`: title, url, size, console, metadata, details). With a single addon this was never missed. With N, it is the field that makes the draggable priority mean anything: without it, `planFromEntries` receives a `sourcePriority` that matches no source and the tiebreaker becomes decoration.

Two details that decide the shape of the field:

**It is non-nullable, with a default value.** The `Game` goes and comes back from disk: `_fetchCatalog` writes `jsonEncode(catalog.map((g) => g.toJson()))` to the cache file (`catalog_service.dart:327`) and `loadCatalog` reads from there (`:271-273`). Every cache written before this slice exists and does not have the field. If the field were nullable, every consumer would have to remember the `?? something`, and the first that forgot would produce a game with no source in the middle of the grid. Non-nullable with a default resolves the degradation **in a single place**, inside `fromJson`.

**The default is `kBuiltinAddonId` and not `kBuiltinSourceId`.** The `sourceId` is now an addon id, and it is compared against the list of ids the user dragged. A game marked `'listagem'` would never match any addon in the list. The `kBuiltinSourceId` of slice 3 was explicitly provisional (`source_pick_model.dart:4-17`: "In slice 4 it becomes the id of the addon that served the file") and Task 15 removes it.

- [ ] **Step 1: Write the failing test**

Create `test/game_source_id_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';

void main() {
  const game = Game(title: 'Crystal Vanguard (USA).zip', url: 'https://a/ct.zip', size: 1024, consoleId: 'snes');

  test('no source declared means the game belongs to the built-in addon', () {
    expect(game.sourceId, kBuiltinAddonId);
  });

  test('sourceId survives a round-trip through the cache json', () {
    final tagged = game.copyWith(sourceId: 'ultranx');
    final restored = Game.fromJson(jsonDecode(jsonEncode(tagged.toJson())) as Map<String, dynamic>);
    expect(restored.sourceId, 'ultranx');
    expect(restored.title, game.title);
    expect(restored.url, game.url);
    expect(restored.consoleId, game.consoleId);
  });

  test('toJson emits the field', () {
    expect(game.copyWith(sourceId: 'ultranx').toJson()['sourceId'], 'ultranx');
  });

  test('old cache written without the field degrades to the built-in addon', () {
    final old = {'title': 'a.zip', 'url': 'https://a/a.zip', 'size': 1, 'consoleId': 'snes'};
    expect(Game.fromJson(old).sourceId, kBuiltinAddonId);
  });

  test('copyWith replaces the source without touching other fields', () {
    final tagged = game.copyWith(sourceId: 'ultranx');
    expect(tagged.sourceId, 'ultranx');
    expect(tagged.title, game.title);
    expect(tagged.size, game.size);
  });

  test('copyWith without sourceId preserves the existing source', () {
    final tagged = game.copyWith(sourceId: 'ultranx');
    expect(tagged.copyWith(size: 2048).sourceId, 'ultranx');
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/game_source_id_test.dart
```

Expected: a compilation error, `No named parameter with the name 'sourceId'`.

- [ ] **Step 3: Write the implementation**

In `lib/models/game_model.dart`, add the import

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

the field, after `consoleId` (line 8):

```dart
  /// The id of the addon that served this file.
  ///
  /// Non-nullable on purpose. The `Game` goes and comes back from disk through
  /// the catalog cache (`catalog_service.dart:327` writes, `:271` reads), and
  /// every cache written before slice 4 does not have the field. With a default,
  /// the degradation happens once, in `fromJson`; with `null`, it would become a
  /// `??` in every consumer and the first forgotten one puts a game with no
  /// source in the grid.
  final String sourceId;
```

the parameter, in the constructor:

```dart
    this.sourceId = kBuiltinAddonId,
```

the parameter and the forwarding in `copyWith`:

```dart
    String? sourceId,
```
```dart
      sourceId: sourceId ?? this.sourceId,
```

the read in `fromJson`:

```dart
      sourceId: json['sourceId'] as String? ?? kBuiltinAddonId,
```

and the write in `toJson`:

```dart
      'sourceId': sourceId,
```

**Likely pitfall:** reading `json['sourceId']` without the `as String?`. The map comes from `jsonDecode` and is `Map<String, dynamic>`, so a `json['sourceId'] ?? kBuiltinAddonId` compiles and delivers `dynamic` to a `String` field, which only blows up at runtime, and only with a cache that has the field with another type. The other fields of `fromJson` suffer from the same (`title: json['title']`, line 41), but that is prior debt and it is not this slice's job to fix.

- [ ] **Step 4: Run to see it pass**

```bash
flutter test test/game_source_id_test.dart
```

Expected: `+6`, zero failures.

- [ ] **Step 5: Run the whole suite**

```bash
flutter test
```

Expected: `+473`, zero failures. No existing test should change: the field has a default, and the default is the behavior from before.

- [ ] **Step 6: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 7: Commit**

```bash
git add test/game_source_id_test.dart
git commit -m "test(addon): o Game carrega o id do addon que o serviu"
git add lib/models/game_model.dart
git commit -m "feat(addon): o Game carrega o id do addon que o serviu"
```

### Task 12b: the port the id discards and the seventeen fields `withUrls` can forget

**Files:**
- Modify: `lib/models/addon_model.dart` (`idFromUrl` starts to distinguish the port)
- Test: `test/addon_model_test.dart`, `test/console_merge_test.dart`

This Task was not in the original plan. It comes out of the mutation review of Tasks 9 and 10, after Task 11b had already closed the two mutants of the ordered list. There are two subjects, and only one is a production defect.

**The defect: `Addon.idFromUrl` throws the port away.** `Uri.host` does not include the port, and the id is built with `uri.host + uri.path`. Measured, with today's logic inlined in a script:

```
example_com_catalog_json      <https://example.com/catalog.json>
example_com_catalog_json      <https://example.com:8080/catalog.json>
example_com_catalog_json      <http://example.com:9000/catalog.json>
```

The three are the same addon in the app's eyes. This matters because the id is a vault key (`SecretRef.addonToken(addonId, consoleId)`) and becomes a disk file key in Task 13: two addons that collide on the id do not coexist, `upsertAddon` replaces one with the other in the list and the second's token overwrites the first's. The method's own doc enumerates what it normalizes on purpose, "scheme, `www.`, case, query, fragment, trailing slash", and the port is not in the list. It was not a decision, it was an oversight. And this app serves LAN on a port: `RtsServerService.consoleJson` builds `http://$hostPort/f/$index/`, so two servers on the same host on different ports is the realistic case, not the exotic one.

**The test gap: `Console.withUrls` copies twenty-one fields by hand and only one is locked.** The review deleted each field line of the copy (`console_model.dart:64-81`) and ran the suite: seventeen delete silently, with everything green. Only `regex` is caught, by the metadata precedence test. The method's comment says it chose the manual copy over a full `copyWith`, and the written reason is "one more place to forget to update when the `Console` grows". A defensible choice; what is missing is the test that proves it did not forget. The risk is low today, because `withUrls` has a single consumer, and it rises in Task 13, when `mergeCatalogs` enters the `CatalogService`.

**Why this costs the chain only one case.** Three of the four holes in `addon_model.dart` (the port, the `trim`, and `isBuiltin`) fit as an extra `expect` inside cases that already exist and already talk about that subject, so they create no `test(`. Only `withUrls` needs a new case, because there is no existing case about field copying. Reinforcing an existing case is worth as much as creating one, and it does not move the totals chain of sixteen Tasks.

- [ ] **Step 1: Reinforce three cases that already exist**

In `test/addon_model_test.dart`, swap the whole case `'http and https of the same catalog share an id, and surrounding space is ignored'` for:

```dart
    test('http and https of the same catalog share an id, and surrounding space is ignored', () {
      const cleaned = 'https://example.com/catalog.json';
      expect(Addon.idFromUrl('http://example.com/catalog.json'), Addon.idFromUrl(cleaned));
      // The `trim` matters: without it `Uri.tryParse` finds no host in a
      // space-padded url and the id becomes `https_example_com_catalog_json`.
      expect(Addon.idFromUrl('  $cleaned  '), Addon.idFromUrl(cleaned));
      // The literal pins the format; comparing id to id survives any slug change.
      expect(Addon.idFromUrl(cleaned), 'example_com_catalog_json');
    });
```

the whole case `'two catalogs on the same host get different ids, and the port is part of the host'` for:

```dart
    test('two catalogs on the same host get different ids, and the port is part of the host', () {
      expect(Addon.idFromUrl('https://example.com/snes.json'), isNot(Addon.idFromUrl('https://example.com/nes.json')));
      // Two LAN servers on the same IP but different ports are two addons. With
      // the port out of the id they would share a vault key and the second
      // install's token would erase the first's.
      expect(Addon.idFromUrl('http://192.168.0.10:8080/f/0/'), isNot(Addon.idFromUrl('http://192.168.0.10:8081/f/0/')));
      expect(Addon.idFromUrl('https://example.com:8080/c.json'), isNot(Addon.idFromUrl('https://example.com/c.json')));
    });
```

and the whole case `'the built-in id: no url maps to it, and only it answers isBuiltin'` for:

```dart
    test('the built-in id: no url maps to it, and only it answers isBuiltin', () {
      expect(Addon.idFromUrl('https://builtin/'), isNot(kBuiltinAddonId));
      expect(const Addon(id: kBuiltinAddonId, name: 'Listing').isBuiltin, isTrue);
      expect(const Addon(id: 'ultranx', name: 'UltraNX').isBuiltin, isFalse);
    });
```

The name of the three cases changes together with the body, on purpose: a case that asserts more than the name says is a case nobody will reread when it breaks.

- [ ] **Step 2: Write the new `withUrls` case**

Still without touching `lib/`. In `test/console_merge_test.dart`, add before the `}` that closes `main`:

```dart
  test('withUrls replaces urls without losing any other field', () {
    // Every field is the OPPOSITE of its constructor default, so a dropped
    // `withUrls` line cannot be masked by the constructor restoring the default.
    const full = Console(
      id: 'snes',
      name: 'Super Nintendo',
      urls: ['https://a/'],
      regex: r'\.sfc$',
      boxarts: {'url': 'https://box/'},
      fileFormat: ['sfc', 'smc'],
      romsFolder: 'roms/snes',
      shouldUnzip: true,
      extractContents: false,
      shouldFilterUsa: false,
      usaRegex: r'\(USA\)',
      shouldDecompressNsz: true,
      ignoreExtensionFiltering: true,
      downloadUrl: 'https://download/',
      auth: {'type': 'cookies'},
      listUrl: 'https://list/',
      listJsonFileLocation: 'items',
      listItemId: 'title',
      listSystems: true,
      added: true,
      convert3dsToCia: true,
    );

    final copy = full.withUrls(['https://b/', 'https://c/']);

    expect(copy.urls, ['https://b/', 'https://c/']);
    expect(copy.id, full.id);
    expect(copy.name, full.name);
    expect(copy.regex, full.regex);
    expect(copy.boxarts, full.boxarts);
    expect(copy.fileFormat, full.fileFormat);
    expect(copy.romsFolder, full.romsFolder);
    expect(copy.shouldUnzip, full.shouldUnzip);
    expect(copy.extractContents, full.extractContents);
    expect(copy.shouldFilterUsa, full.shouldFilterUsa);
    expect(copy.usaRegex, full.usaRegex);
    expect(copy.shouldDecompressNsz, full.shouldDecompressNsz);
    expect(copy.ignoreExtensionFiltering, full.ignoreExtensionFiltering);
    expect(copy.downloadUrl, full.downloadUrl);
    expect(copy.auth, full.auth);
    expect(copy.listUrl, full.listUrl);
    expect(copy.listJsonFileLocation, full.listJsonFileLocation);
    expect(copy.listItemId, full.listItemId);
    expect(copy.listSystems, full.listSystems);
    expect(copy.added, full.added);
    expect(copy.convert3dsToCia, full.convert3dsToCia);
  });
```

**Likely pitfall:** putting a field at the default value to shorten. `shouldUnzip` is already `false` and `extractContents` is already `true` in the constructor, so writing those two values makes the case pass even with the line deleted from `withUrls`. What locks the field is not it being in the `expect`, it is it being worth something the default does not put back.

- [ ] **Step 3: Run to see it fail**

```bash
flutter test test/addon_model_test.dart test/console_merge_test.dart 2>&1 | tr '\r' '\n' | tail -20
```

Expected: **one failure only**, and it is the port one, in the case `'two catalogs on the same host have different ids, and the port is part of the host'`. The other additions (the `trim`, the id literal, the `isBuiltin`, and the twenty-one fields of `withUrls`) describe behavior that is already right today, so they pass on the first try. That is what is expected, it is not a cause for suspicion: they exist to lock what works, not to fix.

- [ ] **Step 4: Put the port in the id**

In `lib/models/addon_model.dart`, in the doc of `idFromUrl`, swap the normalization sentence:

```dart
  /// Stable on purpose: `http` and `https`, with `www.` or without, with a query
  /// or without, with a trailing slash or without, all fall into the same id.
  /// Reinstalling the same source has to re-find the token already in the vault,
  /// and the token is stored under the id.
```

for:

```dart
  /// Stable on purpose: `http` and `https`, with `www.` or without, with a query
  /// or without, with a trailing slash or without, all fall into the same id.
  /// Reinstalling the same source has to re-find the token already in the vault,
  /// and the token is stored under the id.
  ///
  /// **The port enters the id, and it is not forgotten normalization.** `Uri.host`
  /// discards it, so without this `192.168.0.10:8080/f/0/` and `192.168.0.10:8081/f/0/`
  /// would be the same addon, sharing a vault key and a catalog file. Two LAN
  /// servers on the same device is the common case here, not the exotic one.
  /// I use `hasPort` and not `port` because `port` resolves the scheme default:
  /// with it, `http://e.com/c` would give 80 and `https://e.com/c` would give 443,
  /// and the stability across schemes, which is this method's first promise, would
  /// be gone. The price is that a url that writes `:80` for nothing becomes a
  /// different id from the one that does not write it. That mistake creates a
  /// duplicated addon, which is seen in the list; the opposite mistake would erase
  /// a token silently.
```

and swap the `raw` line:

```dart
    final raw = (uri == null || uri.host.isEmpty) ? url : '${uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')}${uri.path}';
```

for:

```dart
    final raw = (uri == null || uri.host.isEmpty)
        ? url
        : '${uri.host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
```

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addon_model_test.dart test/console_merge_test.dart 2>&1 | tr '\r' '\n' | tail -3
```

Expected: `+29`, zero failures. It is the `+17` of `addon_model_test.dart`, which does **not** change, because Step 1 only added `expect` inside existing cases, plus the `+12` of `console_merge_test.dart`, which was `+11`. If the first number turns into `+18` or more, one of the three blocks of Step 1 became a new case instead of replacing the old one, and then the totals chain of this plan is wrong from here on.

- [ ] **Step 6: Prove the `withUrls` case catches what it says it catches**

A case that passes proves nothing. Pick two fields, a `bool` with a default and a nullable one, delete the line of each in `withUrls` and watch the case go red:

```bash
sed -i '/^        auth: auth,$/d' lib/models/console_model.dart
flutter test test/console_merge_test.dart 2>&1 | tr '\r' '\n' | tail -3
git checkout -- lib/models/console_model.dart

sed -i '/^        shouldFilterUsa: shouldFilterUsa,$/d' lib/models/console_model.dart
flutter test test/console_merge_test.dart 2>&1 | tr '\r' '\n' | tail -3
git checkout -- lib/models/console_model.dart
```

Each round has to fail in the case `'withUrls swaps the urls and loses none of the other fields'`. After the two, check the restore before measuring anything else:

```bash
git status --short lib/models/console_model.dart
```

Expected: **no line**. If ` M` shows up, the `git checkout` did not run and every number from here on is from a mutated tree.

- [ ] **Step 7: Run the whole suite**

```bash
flutter test
```

Expected: `+474`, zero failures.

- [ ] **Step 8: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/addon_model_test.dart test/console_merge_test.dart
git commit -m "test(addon): a porta no id, o trim, o isBuiltin e os vinte e um campos do withUrls"
git add lib/models/addon_model.dart
git commit -m "feat(addon): a porta passa a fazer parte do id do addon"
```

---

### Task 13: the `CatalogService` reads N addons and fetches each source with its own auth

**Files:**
- Modify: `lib/services/catalog_service.dart`, `lib/providers/catalog_provider.dart`
- Modify: `lib/providers/tinfoil_server_provider.dart:69` and `lib/providers/fbi_server_provider.dart:95` (both pass the parameter this Task deletes)
- Test: `test/catalog_addons_test.dart`

This is the Task that wires up everything that came before. Two halves:

**Read half.** `getConsoles` stops reading one file and starts reading the addon list, merging the catalogs with `mergeCatalogs`. The static cache stops being a map per file path and becomes a single `MergedCatalog`.

**Fetch half.** `_fetchCatalog` stops iterating `console.urls` and starts iterating `sources`, sending to each url the auth of the addon that declared it and that addon's token. Each game that comes back is marked with the source's `sourceId`.

Two test seams, because the whole path goes through `path_provider` (`getApplicationSupportDirectory` in the store, `getApplicationCacheDirectory` in the catalog cache) and in a test with no platform that throws `MissingPluginException`:

- `buildCatalog(AddonStore store)`, which receives the ready store, with a temporary disk root.
- `fetchSources(client, console, sources, ...)`, which is the network core with no cache and no boxart.

They are public methods with a doc saying what they are for, without `@visibleForTesting`. The repository does not use the annotation anywhere (`grep -rn "visibleForTesting" lib/` finds nothing), and introducing the first one in this Task adds risk of `flutter analyze` changing from 22 over a detail that is not the subject of the slice.

**The network test serves JSON, not HTML.** `_fetchFromUrl` sends HTML to `compute(_parseHtmlIsolate, ...)`, which spins up a real isolate; the JSON branch (`_parseJsonListing`, `catalog_service.dart:479`) is synchronous and in the same isolate. A body that starts with `[` falls into the JSON branch (`:354-356`), and that is what the test uses.

- [ ] **Step 1: Write the failing test**

Create `test/catalog_addons_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';

typedef _Spy = ({String url, List<Map<String, String?>> seen});

/// A local server that records the headers it received and answers [body].
Future<_Spy> _server(String body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  final seen = <Map<String, String?>>[];
  server.listen((req) async {
    seen.add({
      'authorization': req.headers.value('authorization'),
      'cookie': req.headers.value('cookie'),
    });
    req.response.statusCode = status;
    req.response.write(body);
    await req.response.close();
  });
  return (url: 'http://${server.address.address}:${server.port}/', seen: seen);
}

String _listing(List<String> names) => jsonEncode([
      for (final name in names) {'name': name, 'size': 1024},
    ]);

Future<AddonStore> _store(List<Addon> addons, Map<String, String> catalogs) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('catalog_addons_test');
  addTearDown(() => root.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), root);
  await store.save(addons);
  for (final entry in catalogs.entries) {
    await store.writeCatalog(entry.key, entry.value);
  }
  return store;
}

String _catalog(String consoleName, String url, {Map<String, dynamic>? auth}) => jsonEncode([
      {'name': consoleName, 'url': url, 'file_format': ['.zip'], if (auth != null) 'auth': auth},
    ]);

void main() {
  // No `TestWidgetsFlutterBinding.ensureInitialized()` on purpose: the binding
  // installs an `HttpOverrides` that returns 400 for every request, and
  // `fetchSources` talks to a real loopback `HttpServer`.

  group('buildCatalog', () {
    test('two addons with a file both enter, in list order', () async {
      final store = await _store(
        const [Addon(id: 'one', name: 'One'), Addon(id: 'two', name: 'Two')],
        {
          'one': _catalog('SNES', 'https://one/'),
          'two': _catalog('SNES', 'https://two/'),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles['snes']!.urls, ['https://one/', 'https://two/']);
      expect(merged.sources['snes']!.map((f) => f.addonId), ['one', 'two']);
    });

    test('addon with no catalog file is skipped without affecting others', () async {
      final store = await _store(
        const [Addon(id: 'ghost', name: 'Ghost'), Addon(id: 'one', name: 'One')],
        {'one': _catalog('SNES', 'https://one/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']!.single.addonId, 'one');
    });

    test('unreadable catalog from one addon does not affect others', () async {
      final store = await _store(
        const [Addon(id: 'broken', name: 'Broken'), Addon(id: 'one', name: 'One')],
        {'broken': 'this is not json', 'one': _catalog('SNES', 'https://one/')},
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.consoles.keys, ['snes']);
      expect(merged.sources['snes']!.single.addonId, 'one');
    });

    test('each source auth comes from the addon that declared the console', () async {
      final store = await _store(
        const [Addon(id: 'one', name: 'One'), Addon(id: 'two', name: 'Two')],
        {
          'one': _catalog('SNES', 'https://one/', auth: {'auth_message': 'paste the token'}),
          'two': _catalog('SNES', 'https://two/', auth: {'cookies': true}),
        },
      );
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.sources['snes']![0].auth!['auth_message'], 'paste the token');
      expect(merged.sources['snes']![1].auth!['cookies'], true);
    });

    test('empty addon list yields empty catalog', () async {
      final store = await _store(const [], const {});
      final merged = await CatalogService().buildCatalog(store);
      expect(merged.isEmpty, isTrue);
    });
  });

  group('fetchSources', () {
    const console = Console(id: 'snes', name: 'SNES', urls: [], fileFormat: ['.zip']);

    test('each source is fetched with its own addon auth', () async {
      final a = await _server(_listing(['A (USA).zip']));
      final b = await _server(_listing(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(
        client,
        console,
        [
          ConsoleSource(addonId: 'one', url: a.url, auth: const {'auth_message': 'paste'}),
          ConsoleSource(addonId: 'two', url: b.url, auth: const {'cookies': true, 'cookie_name': 'session'}),
        ],
        tokens: const {'one': 'tok-one', 'two': 'tok-two'},
      );

      expect(a.seen.single['authorization'], 'Bearer tok-one');
      expect(a.seen.single['cookie'], isNull);
      expect(b.seen.single['cookie'], 'session=tok-two');
      expect(b.seen.single['authorization'], isNull);
    });

    test('games are tagged with the addon that served them', () async {
      final a = await _server(_listing(['A (USA).zip']));
      final b = await _server(_listing(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final games = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'one', url: a.url),
        ConsoleSource(addonId: 'two', url: b.url),
      ]);

      final byTitle = {for (final game in games) game.title: game.sourceId};
      expect(byTitle, {'A (USA).zip': 'one', 'B (USA).zip': 'two'});
    });

    test('no token for the addon means no auth header is sent', () async {
      final a = await _server(_listing(['A (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'one', url: a.url, auth: const {'auth_message': 'paste'}),
      ]);

      expect(a.seen.single['authorization'], isNull);
    });

    test('one failing source does not prevent the other from delivering', () async {
      final bad = await _server('error', status: 500);
      final good = await _server(_listing(['B (USA).zip']));
      final client = HttpClient();
      addTearDown(client.close);

      final games = await CatalogService().fetchSources(client, console, [
        ConsoleSource(addonId: 'bad', url: bad.url),
        ConsoleSource(addonId: 'good', url: good.url),
      ]);

      expect(games.map((j) => j.title), ['B (USA).zip']);
      expect(games.single.sourceId, 'good');
    });

    test('all sources failing propagates the error', () async {
      final bad = await _server('error', status: 500);
      final client = HttpClient();
      addTearDown(client.close);

      expect(
        () => CatalogService().fetchSources(client, console, [ConsoleSource(addonId: 'bad', url: bad.url)]),
        throwsA(isA<Exception>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/catalog_addons_test.dart
```

Expected: a compilation error, `The method 'buildCatalog' isn't defined for the type 'CatalogService'`.

- [ ] **Step 3: Swap the cache and the catalog read**

In `lib/services/catalog_service.dart`, add to the imports:

```dart
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/console_merge.dart';
```

Swap the static field on line 17

```dart
  static final Map<String, Map<String, Console>> _consolesCache = {};
```

for

```dart
  /// The merged catalog of all installed addons. A single one, because the
  /// addon list is a single one. Invalidated by `clearCache`, which every
  /// catalog write calls.
  static MergedCatalog? _merged;
```

and replace `getConsoles` (lines 20-48) with:

```dart
  /// The consoles of all installed addons, merged.
  ///
  /// The `consolesFilePath` parameter this method had was never used with a
  /// value different from the default by the nine callers, and would not survive
  /// the addon list, where there is no "the file".
  Future<Map<String, Console>> getConsoles() async => (await mergedCatalog()).consoles;

  /// Where each url of a console comes from, in the same order as `console.urls`.
  Future<List<ConsoleSource>> sourcesFor(String consoleId) async => (await mergedCatalog()).sources[consoleId] ?? const [];

  Future<MergedCatalog> mergedCatalog() async {
    final cache = _merged;
    if (cache != null && !cache.isEmpty) return cache;
    try {
      return buildCatalog(await AddonStore.open());
    } catch (e) {
      debugPrint('No catalog source configured yet: $e');
      return const MergedCatalog();
    }
  }

  /// Reads and merges the catalogs of the addons of [store].
  ///
  /// Public because `AddonStore.open()` goes through `path_provider`, which in a
  /// test with no platform throws `MissingPluginException`. With the store
  /// entering via a parameter, the test builds a root in `Directory.systemTemp`
  /// and exercises real disk.
  Future<MergedCatalog> buildCatalog(AddonStore store) async {
    final catalogs = <AddonCatalog>[];
    for (final addon in store.load()) {
      final raw = await store.readCatalog(addon.id) ?? await _bundledCatalog(addon.id);
      if (raw == null) continue;
      try {
        catalogs.add((addonId: addon.id, consoles: parseConsoles(raw)));
      } catch (e) {
        // One addon's broken JSON must not take the others down.
        debugPrint('Unreadable catalog for addon ${addon.id}: $e');
      }
    }
    final merged = mergeCatalogs(catalogs);
    if (!merged.isEmpty) _merged = merged;
    return merged;
  }

  /// The example catalog bundled in the app (`assets/catalog/`, git-ignored).
  ///
  /// Only the builtin has one, and it is its third and last precedence: user
  /// file, asset, nothing. It is the same precedence as before slice 4.
  static Future<String?> _bundledCatalog(String addonId) async {
    if (addonId != kBuiltinAddonId) return null;
    try {
      return await rootBundle.loadString('assets/catalog/consoles.json');
    } catch (_) {
      return null;
    }
  }

  /// Forgets the merged catalog. Every catalog write calls it.
  static void clearCache() => _merged = null;
```

Swap `consoleByIdSync` (lines 52-59) for:

```dart
  static Console? consoleByIdSync(String? id) {
    if (id == null) return null;
    return _merged?.consoles[id];
  }
```

And swap the three `_consolesCache.clear()` calls (`setCatalogFromJson`, `addConsole`, `resetCatalog`) for `clearCache()`.

Scope note: `setCatalogFromJson`, `addConsole` and `resetCatalog` keep writing to `config/consoles.json` via `_userConsolesFile()`, which does not change. That is exactly the embedded addon's file (`AddonStore.catalogFile`), so installing a catalog from the Tools screen keeps updating the builtin. Installing as a **new** addon is Task 21.

- [ ] **Step 4: Swap the fetch to iterate over sources**

Still in `lib/services/catalog_service.dart`, replace `loadCatalog` (lines 195-228) and `_fetchCatalog` (230-274) with:

```dart
  Future<List<Game>> loadCatalog(String consoleId,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final merged = await mergedCatalog();
    final console = merged.consoles[consoleId];

    if (console == null) {
      debugPrint("Console with id '$consoleId' not found");
      return [];
    }

    final cacheFile = await _getCacheFile(console.cacheFile);
    if (await cacheFile.exists()) {
      try {
        final jsonStr = await cacheFile.readAsString();
        final List<Map<String, dynamic>> jsonList = await compute(_decodeGamesIsolate, jsonStr);
        final cachedResult = jsonList.map((json) => Game.fromJson(json)).toList();
        if (cachedResult.isNotEmpty && cachedResult.first.metadata != null) {
          final hasBoxarts = cachedResult.any((game) => game.details?.boxart != null);
          if (!hasBoxarts && console.boxarts != null) {
            final enrichedResult = await _boxartService.mutateGamesWithBoxarts(cachedResult, console);
            await cacheFile.writeAsString(jsonEncode(enrichedResult.map((g) => g.toJson()).toList()));
            return enrichedResult;
          }
          return cachedResult;
        }
      } catch (e) {
        debugPrint('Error reading cache: $e');
        await cacheFile.delete();
      }
    }

    return _fetchCatalog(console, merged.sources[consoleId] ?? const [],
        iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, tokens: tokens, onProgress: onProgress);
  }

  Future<List<Game>> _fetchCatalog(Console console, List<ConsoleSource> sources,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    List<Game> catalog = [];

    try {
      catalog = await fetchSources(client, console, sources,
          iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, tokens: tokens, onProgress: onProgress);
      catalog = await _boxartService.mutateGamesWithBoxarts(catalog, console);
      final cacheFile = await _getCacheFile(console.cacheFile);
      await cacheFile.writeAsString(jsonEncode(catalog.map((g) => g.toJson()).toList()));
    } catch (e) {
      debugPrint('Error fetching catalog: $e');
      rethrow;
    } finally {
      client.close();
    }

    return catalog;
  }

  /// Fetches all [sources] in parallel and returns all their games, each tagged
  /// with the addon that served it, sorted by title.
  ///
  /// Each source speaks with the auth and token of the addon that declared it
  /// (`tokens[addonId]`), so one addon's token never reaches another's server.
  Future<List<Game>> fetchSources(HttpClient client, Console console, List<ConsoleSource> sources,
      {String? iaAccessKey,
      String? iaSecretKey,
      Map<String, String> tokens = const {},
      void Function(int done, int total)? onProgress}) async {
    final total = sources.length;
    var done = 0;
    Object? firstError;
    onProgress?.call(0, total);
    final results = await Future.wait(
      sources.map((source) => _fetchFromUrl(client, source, console,
                  iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey, authToken: tokens[source.addonId])
              .then((games) {
            onProgress?.call(++done, total);
            return games;
          }).catchError((Object e) {
            // Keep the partial result when only some pages fail; the error
            // rises only when none delivered anything.
            firstError ??= e;
            onProgress?.call(++done, total);
            return <Game>[];
          })),
    );
    if (firstError != null && results.every((r) => r.isEmpty)) {
      throw firstError!;
    }

    return results.expand((games) => games).toList()..sort((a, b) => a.title.compareTo(b.title));
  }
```

Replace `_fetchFromUrl` and `_fetchFromUrlIA` (lines 276-321) so they receive the source instead of the bare url:

```dart
  Future<List<Game>> _fetchFromUrl(HttpClient client, ConsoleSource source, Console console,
      {String? iaAccessKey, String? iaSecretKey, String? authToken}) async {
    final url = source.url;
    if (_isArchiveOrgUrl(url)) {
      return _fetchFromUrlIA(client, source, console, iaAccessKey: iaAccessKey, iaSecretKey: iaSecretKey);
    }

    final request = await client.getUrl(Uri.parse(url));
    // `source.auth`, not `console.auth`: auth belongs to the url, since two
    // addons can serve the same console.
    final headers = buildDownloadHeaders(url, buildConsoleAuthHeaders(source.auth, tokenOverride: authToken));
    headers.forEach(request.headers.set);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: Failed to fetch catalog from $url');
    }

    final body = await response.transform(utf8.decoder).join();
    // Auto-detect: a JSON listing (e.g. from Retro Tools Server) vs HTML.
    final trimmed = body.trimLeft();
    final parsed = (trimmed.startsWith('[') || trimmed.startsWith('{'))
        ? _parseJsonListing(body, console, url)
        : await compute(_parseHtmlIsolate, [body, console.toJson(), url]);
    return parsed.map((entry) => Game.fromJson(entry).copyWith(sourceId: source.addonId)).toList();
  }

  Future<List<Game>> _fetchFromUrlIA(HttpClient client, ConsoleSource source, Console console,
      {String? iaAccessKey, String? iaSecretKey}) async {
    final itemId = _extractIAItemId(source.url);
    if (itemId == null) return [];

    final request = await client.getUrl(Uri.parse('$_iaMetadataBase$itemId'));

    // User-saved credentials take precedence over per-system auth config.
    final resolvedKey = iaAccessKey ?? (source.auth?['type'] == 'ia_s3' ? source.auth!['access_key'] as String? : null);
    final resolvedSecret = iaSecretKey ?? (source.auth?['type'] == 'ia_s3' ? source.auth!['secret_key'] as String? : null);
    if (resolvedKey != null && resolvedKey.isNotEmpty && resolvedSecret != null && resolvedSecret.isNotEmpty) {
      request.headers.set('Authorization', 'LOW $resolvedKey:$resolvedSecret');
    }

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: IA metadata fetch failed for $itemId');
    }

    final body = await response.transform(utf8.decoder).join();
    final parsed = await compute(_parseIAMetadataIsolate, [body, console.toJson(), itemId]);
    debugPrint('IA $itemId: body=${body.length}b parsed=${parsed.length} shouldUnzip=${console.shouldUnzip} fmts=${console.fileFormat}');
    return parsed.map((entry) => Game.fromJson(entry).copyWith(sourceId: source.addonId)).toList();
  }
```

**Likely pitfall:** leaving `console.auth` in `_fetchFromUrlIA` when only `_fetchFromUrl` is swapped. IA S3 auth is read through a different path (`auth['type'] == 'ia_s3'`, `catalog_service.dart:368-369`), and a grep for `buildConsoleAuthHeaders` misses that section. The criterion: **inside `_fetchFromUrl` and `_fetchFromUrlIA`, no remaining reads of `console.auth`.** Verify:

```bash
grep -n "console.auth" lib/services/catalog_service.dart
```

Expected: nothing.

- [ ] **Step 5: Fix the two callers that passed `authToken`**

`loadCatalog` lost the `authToken` parameter and gained `tokens`, and **two files still pass the old one**: `lib/providers/tinfoil_server_provider.dart:69` and `lib/providers/fbi_server_provider.dart:95`, both with the same line

```dart
          authToken: settings.consoleSettings[console.id]?.authToken,
```

This is a compilation error, not a warning: without this Step the `flutter test` of Step 7 does not even get to run. In both files, replace the line with

```dart
          tokens: _builtinTokens(settings, console.id),
```

and add the following imports to both files

```dart
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
```

The `settings_model.dart` import is mandatory and easy to forget: neither file imports it today; they reach `settings.consoleSettings` through the inferred type of `_ref.read(settingsProvider)`, and **there is not a single `export` in `lib/`**, so writing `AppSettings` in the signature without the import is a compilation error.

Then, the private method. It goes in **both** files, but the middle paragraph of the doc **is not the same in both**, because the mechanism is not the same. Verified: `TinfoilServerService.start` receives `authHeaders` as `Map<String, String> Function(Console)` (`tinfoil_server_service.dart:80`) and the provider passes it at `:121`; `FbiServerService.start` receives no `authHeaders` at all, taking only `port` and `cacheDir` (`fbi_server_service.dart:72`). Copying the Tinfoil paragraph to the FBI file puts a false claim about a signature, the kind of doc that nobody questions later. In `lib/providers/tinfoil_server_provider.dart`:

```dart
  /// The builtin addon's token for this console, in the shape `loadCatalog`
  /// expects.
  ///
  /// The LAN servers only serve the builtin addon's credential, so a console
  /// served by a third-party addon with auth lists here but fails to download.
  Map<String, String> _builtinTokens(AppSettings settings, String consoleId) {
    final token = settings.consoleSettings[consoleId]?.authToken ?? '';
    return token.isEmpty ? const {} : {kBuiltinAddonId: token};
  }
```

**Do not break the `Map<String, String> Function(Console)` line.** It fits on one line on purpose: split across two, the backtick span is left open at the end of the first line and `unintended_html_in_doc_comment` flags `<String,` as HTML. Measured: with the break only in Tinfoil, analyze returned **23**. The lint is one `info` per occurrence, so the broken block pasted into both providers gives 24; that 24 was not run, it is arithmetic. It is the only reason the `tinfoil_server_service.dart:80` citation appears inside the doc comment rather than in prose.

And in `lib/providers/fbi_server_provider.dart`, the same method with the middle paragraph replaced:

```dart
  /// The builtin addon's token for this console, in the shape `loadCatalog`
  /// expects.
  ///
  /// The LAN servers only serve the builtin addon's credential, so a console
  /// served by a third-party addon with auth lists here but fails to download.
  Map<String, String> _builtinTokens(AppSettings settings, String consoleId) {
    final token = settings.consoleSettings[consoleId]?.authToken ?? '';
    return token.isEmpty ? const {} : {kBuiltinAddonId: token};
  }
```

`settings.consoleSettings[...].authToken` mirrors the builtin, and is exactly what these two lines read before. Today's behavior stays identical; what changes is that it stops leaking to other addons.

**Do not look for the other two callers in this Step.** `lib/providers/jdkv_server_provider.dart:96` and `lib/services/sports_rom_lookup.dart:41` also call `loadCatalog`, but pass only the id: they never passed `authToken`, so they do not break on the signature change. A console with auth already failed there before this slice and continues failing the same way. That is prior debt, documented in the `_builtinTokens` doc so it does not disappear, and it is not this Task to fix.

- [ ] **Step 6: Wire the provider to the vault**

In `lib/providers/catalog_provider.dart`, add to the imports:

```dart
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
```

and replace the block at lines 57-68 with:

```dart
      final settings = _ref.read(settingsProvider);
      final vault = (await _ref.read(vaultProvider.future)).vault;
      final tokens = <String, String>{};
      for (final addonId in {for (final source in await catalogService.sourcesFor(console.id)) source.addonId}) {
        final token = await vault.read(SecretRef.addonToken(addonId, console.id));
        if (token != null && token.isNotEmpty) tokens[addonId] = token;
      }

      final games = await catalogService.loadCatalog(
        console.id,
        iaAccessKey: settings.iaAccessKey,
        iaSecretKey: settings.iaSecretKey,
        tokens: tokens,
        onProgress: (done, total) {
          if (mounted && gen == _loadGeneration && total > 1) {
            state = state.copyWith(loadingStatus: 'Reading page $done of $total');
          }
        },
      );
```

- [ ] **Step 7: Run to see it pass**

```bash
flutter test test/catalog_addons_test.dart
```

Expected: `+10`, zero failures.

- [ ] **Step 8: Run the full suite**

```bash
flutter test
```

Expected: `+484`, zero failures. `test/catalog_selection_test.dart`, `test/add_catalog_source_screen_test.dart`, and `test/catalog_add_console_test.dart` touch `CatalogService`: if any break on the signature, the fix is to follow the new signature, never to reintroduce the `authToken` parameter.

- [ ] **Step 9: Analyze and compile**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found`, build ok.

- [ ] **Step 10: Commit**

```bash
git add test/catalog_addons_test.dart
git commit -m "test(addon): catalogo lido de N addons, cada fonte com a auth e o token do seu"
git add lib/services/catalog_service.dart lib/providers/catalog_provider.dart lib/providers/tinfoil_server_provider.dart lib/providers/fbi_server_provider.dart
git commit -m "feat(addon): catalogo lido de N addons, cada fonte com a auth e o token do seu"
```

### Task 14: `addonProvider` and the derived priority

**Files:**
- Create: `lib/providers/addon_provider.dart`
- Modify: `lib/services/catalog_service.dart` (gains `invalidateForAddonChange`)
- Test: `test/addon_provider_test.dart`

The provider is thin by design: it holds the list, persists every change, and derives the priority. The list rules are already pure functions from Task 9, and the disk is already the store from Task 11.

The one non-obvious thing is **the invalidation order**. When the list changes, two things go stale: the per-console game cache files (`catalog_<id>.json`) and the in-memory catalog merge. `clearCatalogCache()` sweeps the game caches by iterating `getConsoles()`, meaning it **needs the old catalog** to know which files to delete. If the merge is cleared first, the sweep runs with the new list and leaves behind the cache for a console that only the removed addon served, and that cache would keep feeding the grid.

- [ ] **Step 1: Write the failing test**

Create `test/addon_provider_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('addon_provider_test');
  addTearDown(() => root.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), root);
  await store.save(addons);
  return store;
}

/// Returns the container with the initial list loaded, plus the store and the
/// invalidation counter. At the top of the file, not inside `main`, to satisfy
/// `no_leading_underscores_for_local_identifiers`.
Future<({ProviderContainer container, AddonStore store, List<int> invalidations})> _build(List<Addon> initial) async {
  final store = await _store(initial);
  final invalidations = <int>[];
  final container = ProviderContainer(overrides: [
    addonProvider.overrideWith((ref) => AddonNotifier(
          Future.value(store),
          invalidateCache: () async => invalidations.add(1),
        )),
  ]);
  addTearDown(container.dispose);
  await container.read(addonProvider.notifier).ready;
  return (container: container, store: store, invalidations: invalidations);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the store list on boot', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
  });

  test('install appends at the end and persists', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'b', name: 'B'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.store.load().map((x) => x.id), ['a', 'b']);
  });

  test('install of the same id replaces without changing position', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A fixed'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.container.read(addonProvider).first.name, 'A fixed');
  });

  test('install writes the catalog to the addon file', () async {
    final m = await _build(const []);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A'), '[{"name":"SNES"}]');
    expect(await m.store.readCatalog('a'), '[{"name":"SNES"}]');
  });

  test('remove drops from the list and persists', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).remove('a');
    expect(m.container.read(addonProvider).map((x) => x.id), ['b']);
    expect(m.store.load().map((x) => x.id), ['b']);
  });

  test('remove deletes the addon\'s catalog file', () async {
    final m = await _build(const []);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'a', name: 'A'), '[]');
    await notifier.remove('a');
    expect(await m.store.readCatalog('a'), isNull);
  });

  test('reorder applies ReorderableListView semantics and persists', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B'), Addon(id: 'c', name: 'C')]);
    await m.container.read(addonProvider.notifier).reorder(0, 3);
    expect(m.container.read(addonProvider).map((x) => x.id), ['b', 'c', 'a']);
    expect(m.store.load().map((x) => x.id), ['b', 'c', 'a']);
  });

  test('install and remove invalidate the cache, and so does reorder', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'c', name: 'C'), '[]');
    await notifier.remove('a');
    await notifier.reorder(0, 2);
    expect(m.invalidations.length, 3);
  });

  test('sourcePriority returns the ids in list order', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(sourcePriorityProvider), ['a', 'b']);
  });

  test('sourcePriority follows the drag', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).reorder(1, 0);
    expect(m.container.read(sourcePriorityProvider), ['b', 'a']);
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/addon_provider_test.dart
```

Expected: compilation failure, `Target of URI doesn't exist: 'package:roms_downloader/providers/addon_provider.dart'`.

- [ ] **Step 3: Give `CatalogService` the invalidation in the right order**

In `lib/services/catalog_service.dart`, right after `clearCatalogCache` (which closes the class), add:

```dart
  /// Forgets everything that depended on the addon list: the per-console game
  /// cache files **and then** the in-memory catalog merge.
  ///
  /// The order is not style. `clearCatalogCache` discovers which files to
  /// delete by iterating `getConsoles()`, so it needs the **old** catalog.
  /// Reversed, the sweep would run with the new list and leave behind the
  /// cache of a console only the removed addon served, and that file would
  /// keep feeding the grid after the removal.
  Future<void> invalidateForAddonChange() async {
    await clearCatalogCache();
    clearCache();
  }
```

- [ ] **Step 4: Write the provider**

Create `lib/providers/addon_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';

final addonProvider = StateNotifierProvider<AddonNotifier, List<Addon>>((ref) {
  return AddonNotifier(AddonStore.open());
});

/// Source priority order, derived from the list order.
final sourcePriorityProvider = Provider<List<String>>((ref) => [for (final addon in ref.watch(addonProvider)) addon.id]);

class AddonNotifier extends StateNotifier<List<Addon>> {
  final Future<AddonStore> _store;

  final Future<void> Function() _invalidateCache;

  /// Resolves once the initial list has loaded from disk.
  late final Future<void> ready;

  AddonNotifier(this._store, {Future<void> Function()? invalidateCache})
      : _invalidateCache = invalidateCache ?? CatalogService().invalidateForAddonChange,
        super(const []) {
    ready = _load();
  }

  Future<void> _load() async {
    final store = await _store;
    if (!mounted) return;
    state = store.load();
  }

  /// Installs, or reinstalls, an addon with the already-fetched catalog.
  /// Reinstalling keeps the position (`upsertAddon`).
  Future<void> install(Addon addon, String catalogJson) async {
    final store = await _store;
    await store.writeCatalog(addon.id, catalogJson);
    final next = upsertAddon(state, addon);
    await store.save(next);
    await _invalidateCache();
    if (mounted) state = next;
  }

  /// Removes the addon from the list and deletes its catalog from disk.
  /// Does not delete the vault secret: reinstalling the same source must find
  /// the token again, which is why `Addon.idFromUrl` is stable.
  Future<void> remove(String id) async {
    final store = await _store;
    await store.deleteCatalog(id);
    final next = removeAddon(state, id);
    await store.save(next);
    await _invalidateCache();
    if (mounted) state = next;
  }

  Future<void> reorder(int from, int to) async {
    final next = reorderAddons(state, from, to);
    final store = await _store;
    await store.save(next);
    await _invalidateCache();
    if (mounted) state = next;
  }
}
```

**Likely pitfall:** `remove` also deleting the vault secret, "for cleanliness." That looks like hygiene and is data loss: a user who removes an addon to reinstall it with a corrected URL would have to rediscover the token. The choice is written in the method doc so it does not get "fixed" in a review.

**Second pitfall, with no test to catch it:** the order inside `invalidateForAddonChange`. It is not covered by the suite because both halves go through `path_provider`: `clearCatalogCache` calls `getApplicationCacheDirectory` and `getConsoles` calls `getApplicationSupportDirectory`, and in a platform-less test both become silent no-ops instead of failing. What exists is the comment in the method, and it is honest to say that line is verified by reading, not by the suite.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addon_provider_test.dart
```

Expected: `+10`, zero failures.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```

Expected: `+494`, zero failures.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_provider_test.dart
git commit -m "test(addon): provider da lista de addons e a prioridade derivada da ordem"
git add lib/providers/addon_provider.dart lib/services/catalog_service.dart
git commit -m "feat(addon): provider da lista de addons e a prioridade derivada da ordem"
```

**End of Group 3.** The app has N catalogs, each with its own identity, auth, and token, and an order the user will be able to drag in Group 5. What still does not happen: the grid continues to report that every source is `kBuiltinSourceId`, and the batch still receives no priority. That is Group 4.

| Task | New | Cumulative |
| --- | --- | --- |
| 8b, hydration without inventing config | 4 | 425 |
| 9, addon model | 15 | 440 |
| 10, catalog merge | 11 | 451 |
| 11, persistence | 14 | 465 |
| 11b, the two ordered list cases | 2 | 467 |
| 12, `Game.sourceId` | 6 | 473 |
| 12b, the forgotten field and the discarded port | 1 | 474 |
| 13, catalog from N addons | 10 | 484 |
| 14, provider and priority | 10 | 494 |

---

## Group 4: the source with identity

Group 3 gave the catalog its identity: each `Console` knows which addons serve it, each `Game` coming from the network already carries the `sourceId` of its server, and `sourcePriorityProvider` already returns the list order. None of that has reached the grid or the screens yet.

Three things are missing, and each is a Task:

1. **The stamp is not read.** `pack_grid_provider.dart:75` and `source_pick_service.dart:27` write `kBuiltinSourceId` by hand, a slice 3 constant whose own doc already announced its expiry: *"In slice 4 it becomes the id of the addon that served the file"* (`source_pick_model.dart:4-9`). Task 15 reads `game.sourceId` in both places and deletes the constant.
2. **The priority never reaches the picker.** `planFromEntries` has accepted `sourcePriority` since slice 3 (`source_pick_service.dart:54`) and both callers, `home_screen.dart:43` and `game_detail_screen.dart:74`, pass nothing. The parameter has a default, so this compiles today and would keep compiling forever. Task 16 wires the two together.
3. **The screen shows the id, and the user did not choose an id.** UI spec section 7 asks for "4.0 MB, Myrient". After Task 15 the field becomes `myrient_org_files`, which is a vault and disk key, not screen text. Task 17 resolves the id to the addon name in the two places where it is drawn.

**One rule for the `kBuiltinSourceId` replacements in the tests, because it decides four files.** The constant dies in Task 15. Eleven lines name it, and **seven of them are in test**, spread across four files: `game_detail_screen_test.dart:46`, `pack_grid_provider_test.dart:108`, `:126` and `:141`, `source_pick_service_test.dart:50`, and `pack_grid_test.dart:24` and `:39`. The other four are in production (`source_pick_service.dart:27`, `pack_grid_provider.dart:75`, and the declaration plus field doc in `source_pick_model.dart:17` and `:35`), and Task 15 handles those with no special rule. The seven in test are not all the same thing:

- Where the test **asserts what production computed**, the replacement is `kBuiltinAddonId`. That is one site only: `test/pack_grid_provider_test.dart:108`, which reads the `sourceId` that `sourceIndexProvider` built from a `Game`.
- Where the id is **fixture data invented by the test**, the replacement is the literal `'listagem'`, which is what eight other lines in the suite already use (`source_verification_provider_test.dart:18`, `source_pick_model_test.dart:17`, `pack_grid_filter_test.dart:10`, `batch_confirm_sheet_test.dart:12`, `source_pick_service_test.dart:20`, `source_index_test.dart:25` and `:67`, `grid_entry_model_test.dart:9`). In those sites the id is opaque: any non-empty string works, and no assertion depends on which one it is.

**Do not `sed` the literal `'listagem'` to `'builtin'`.** That looks like the obvious cleanup and costs a lot for nothing: in `test/game_detail_screen_test.dart` the source's `sourceId` is drawn on screen, and nine expectations in the file carry that string (`'4.0 MB, listagem'` on line 121, and eight more between lines 269 and 462). Replacing the literal would require rewriting all nine, in a commit that is about deleting a constant. The literal stays. Line 206 also says "listagem", but in prose (`'the source left the listing before the queue started'`): that is not a `sourceId` and does not count.

### Task 15: the addon id reaches the grid and the batch

**Files:**
- Modify: `lib/providers/pack_grid_provider.dart:75` (plus the import at line 5, which becomes orphaned)
- Modify: `lib/services/source_pick_service.dart:27`
- Modify: `lib/models/source_pick_model.dart:4-17` (deletes `kBuiltinSourceId`) and `:35-37` (the field doc)
- Test: `test/pack_grid_provider_test.dart`, `test/source_pick_service_test.dart`, `test/pack_grid_test.dart`, `test/game_detail_screen_test.dart`

Two production lines and one deleted constant. The work is the test cleanup, and it is mechanical if you follow the rule at the top of the group.

Note the import detail: `lib/providers/pack_grid_provider.dart` imports `source_pick_model.dart` at line 5 **only** because of `kBuiltinSourceId`. Verified with `grep -n "SourcePick\|BatchPlan\|PickFailure\|kBuiltinSourceId" lib/providers/pack_grid_provider.dart`, which returns one line only, line 75. Once the usage is removed, the import becomes an `unused_import` and analyze rises above 22. In `lib/services/source_pick_service.dart` the import stays, because that is where `SourcePick` and `BatchPlan` come from.

- [ ] **Step 1: Write the failing tests**

In `test/pack_grid_provider_test.dart`, add the addon model import alongside the others:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

replace the `_game` signature at lines 28 to 33 with this, which accepts the addon:

```dart
Game _game(String filename, {String sourceId = kBuiltinAddonId}) => Game(
      title: filename,
      url: 'https://example.org/snes/$filename',
      size: 2048,
      consoleId: 'snes',
      sourceId: sourceId,
    );
```

Replace the three `kBuiltinSourceId` references in the file **by the rule at the top of the group, which separates them**: the one at line 108 becomes `kBuiltinAddonId`, because there the test asserts the `sourceId` production computed; the ones at lines 126 and 141 become the literal `'listagem'`, because there the id is a `MatchedSource` fixture invented by the test and neither case's assertion reads it (one reads `found?.filename`, the other reads `found, isNull`). **Also delete `import 'package:roms_downloader/models/source_pick_model.dart';` at line 8 of this file.** It existed only because of the constant: after the replacement, the only remaining mention of that file is a comment phrase at line 146 (``// the path that becomes `PickFailure` in Task 14``), and `PickFailure` in backticks inside a comment is not a symbol. Left behind, it becomes an `unused_import`, which is a **warning**, not an `info`, and analyze rises to 23. Then add this case right after the test `'the matched source carries the size and the built-in source id'`:

```dart
  test('each source carries the addon id of the game that produced it', () async {
    final container = _container(games: [
      _game('Crystal Vanguard (USA).zip', sourceId: 'myrient'),
      _game('Super Vectron (USA).zip', sourceId: 'someones-archive'),
    ]);
    await _ready(container);

    // A map, not a list: what is asserted is that each source kept its own
    // game's id, independent of grid order.
    expect(
      {for (final e in container.read(packGridEntriesProvider)) e.game.id: e.sources.single.sourceId},
      {'snes/crystal-vanguard': 'myrient', 'snes/super-vectron': 'someones-archive'},
    );
  });
```

In `test/source_pick_service_test.dart`, replace the `_game` helper at lines 10 to 15 with:

```dart
Game _game(String filename, int size, {String sourceId = kBuiltinAddonId}) => Game(
      title: filename.replaceAll('.zip', ''),
      url: 'https://example.org/snes/$filename',
      size: size,
      consoleId: 'snes',
      sourceId: sourceId,
    );
```

add the addon model import:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

replace the `kBuiltinSourceId` at line 50 inside the `_v` helper with the literal `'listing'` (it is fixture: `_v` builds the input to `splitByVerification` and no assertion in the file reads that field), and add the two cases below right after the test `'each selected game becomes a pick, in the same order'`:

```dart
  test('planFromGames carries each game addon id', () {
    final plan = planFromGames([
      _game('Crystal Vanguard (USA).zip', 4 * 1024 * 1024, sourceId: 'myrient'),
      _game('Super Vectron (USA).zip', 2 * 1024 * 1024, sourceId: 'someones-archive'),
    ]);

    expect(plan.picks.map((p) => p.sourceId), ['myrient', 'someones-archive']);
  });

  test('a cached game with no declared addon becomes the builtin', () {
    // Built by hand, without `_game`, so the case exercises `Game`'s default
    // rather than the helper's own default.
    final plan = planFromGames([
      Game(title: 'Crystal Vanguard (USA)', url: 'https://example.org/snes/Crystal Vanguard (USA).zip', size: 1024, consoleId: 'snes'),
    ]);

    expect(plan.picks.single.sourceId, kBuiltinAddonId);
  });
```

In `test/pack_grid_test.dart`, replace both `kBuiltinSourceId` occurrences (lines 24 and 39) with the literal `'listing'` and delete the `source_pick_model.dart` import if it has no remaining uses. Verify with `grep -n "source_pick_model\|SourcePick\|BatchPlan" test/pack_grid_test.dart` before deleting: if the file uses `SourcePick` elsewhere, the import stays.

In `test/game_detail_screen_test.dart`, replace the `kBuiltinSourceId` at line 46 with the literal `'listing'` and delete the `source_pick_model.dart` import by the same criterion. The `grep` here is mandatory, not decorative: the file uses `SourcePick` in the `onDownload` callback, so the import probably stays.

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/pack_grid_provider_test.dart test/source_pick_service_test.dart
```

Expected: compilation error, `Undefined name 'kBuiltinSourceId'` in the files that still name it and `No named parameter with the name 'sourceId'` if Task 12 was skipped. Once it compiles, the three new cases fail: the grid and the batch still stamp the constant.

- [ ] **Step 3: The grid reads the game stamp**

In `lib/providers/pack_grid_provider.dart`, delete the import at line 5:

```dart
import 'package:roms_downloader/models/source_pick_model.dart';
```

and replace line 75:

```dart
      (filename: game.filename, sourceId: game.sourceId, size: game.size, url: game.url),
```

- [ ] **Step 4: The batch reads the game stamp**

In `lib/services/source_pick_service.dart`, at line 27 inside `planFromGames`:

```dart
          sourceId: game.sourceId,
```

and update the function doc, which currently says the priority rule "only has a subject in PACK MODE". Still true, but the mention of slice 3 Task 14 is confusing in a slice that also has Task 14:

```dart
/// The batch plan for SOURCE MODE.
///
/// There is no choice to make here: each selected `Game` is already a file, so
/// no pick is uncertain and the failure list is always empty. The real rule,
/// with region, revision, confidence, and addon priority, lives in
/// `planFromEntries`.
```

- [ ] **Step 5: Delete the constant**

In `lib/models/source_pick_model.dart`, delete the entire block at lines 4 to 17, doc and constant. If the file has no remaining use for the `game_model.dart` import, verify first: `SourcePick.game` is a `Game`, so the import stays.

Replace the doc of the `sourceId` field, at lines 35 to 37, which describes a world that just stopped existing:

```dart
  /// Which addon it came from, by [Addon] id. Comes from `Game.sourceId`.
  final String sourceId;
```

Verify nothing remains:

```bash
grep -rn "kBuiltinSourceId" lib/ test/
```

Expected: no lines.

- [ ] **Step 6: Run the touched files**

```bash
flutter test test/pack_grid_provider_test.dart test/source_pick_service_test.dart test/pack_grid_test.dart test/game_detail_screen_test.dart
```

Expected: zero failures. The three new cases pass and none of the old ones changed result, including the nine `'... listagem ...'` expectations in the detail screen, which remain valid because the literal stayed.

**Likely pitfall:** deleting the import at line 5 of `pack_grid_provider.dart` but not the right one, or deleting an import still used in `pack_grid_test.dart` and `game_detail_screen_test.dart`. Both errors are caught by `flutter analyze` in Step 8, one as `unused_import` and the other as a compilation error, but the first is an `info` and is easy to miss in a quick read of the output. The criterion is the `grep` for each file, not the eye.

**Second pitfall:** replacing the literal `'listagem'` with `'builtin'` "for consistency." The opening of the group explains why, and the consequence is ten red string expectations in `game_detail_screen_test.dart` in a Task that touched no screen.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```

Expected: `+497`, zero failures.

- [ ] **Step 8: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/pack_grid_provider_test.dart test/source_pick_service_test.dart test/pack_grid_test.dart test/game_detail_screen_test.dart
git commit -m "test(addon): a fonte casada passa a carregar o id do addon que a serviu"
git add lib/providers/pack_grid_provider.dart lib/services/source_pick_service.dart lib/models/source_pick_model.dart
git commit -m "feat(addon): a fonte casada passa a carregar o id do addon que a serviu"
```

### Task 16: both screens pass the user priority

**Files:**
- Modify: `lib/screens/home_screen.dart:43-47`
- Modify: `lib/screens/game_detail_screen.dart:74-78`
- Test: `test/game_detail_screen_test.dart`

`planFromEntries` has had `List<String> sourcePriority = const []` with a default value since slice 3, and that is why this Task is needed: without the default, the compiler would have demanded both callers on the day the parameter was born. With it, the app compiles today passing an empty list forever, and the order the user will drag in Group 5 would decide nothing.

**A note on coverage before the steps.** `test/` has no test for `HomeScreen`: the screen mounts the entire app, with the download queue, global state, and catalog. Its line is verified by reading and by the `flutter build linux --debug` of Step 6, not by the suite. What the suite proves is the other half: the detail screen calls the same function with the same list, and the cases below show that the output changes when the list changes. Do not write in the report that "both screens are tested."

- [ ] **Step 1: Write the failing tests**

In `test/game_detail_screen_test.dart`, add the addon provider import:

```dart
import 'package:roms_downloader/providers/addon_provider.dart';
```

give the `_source` helper at lines 39 to 49 a configurable source id:

```dart
MatchedSource _source(
  String filename, {
  int size = 4 * 1024 * 1024,
  MatchConfidence confidence = MatchConfidence.likely,
  String sourceId = 'listing',
}) =>
    MatchedSource(
      filename: filename,
      sourceId: sourceId,
      confidence: confidence,
      size: size,
    );
```

and give `_host` a priority parameter, with the provider override:

```dart
Widget _host(
  PackGridEntry entry, {
  void Function(SourcePick)? onDownload,
  VoidCallback? onBatchDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verification,
  List<String> priority = const [],
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
      sourcePriorityProvider.overrideWithValue(priority),
```

**The same override must also enter the standalone `ProviderScope` of the test `'the checkbox toggles selection by pack key'`, at lines 158 to 178**, which does not use `_host`. There it goes with an empty list:

```dart
        sourcePriorityProvider.overrideWithValue(const []),
```

Add the three cases at the end of `main`:

```dart
  testWidgets('the user priority decides the highlight between tied sources', (tester) async {
    // Same filename on both, so region, revision and confidence tie and only
    // the addon axis remains. `size` differs as an observable of which one won.
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'slow'),
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'fast'),
      ]),
      priority: const ['fast', 'slow'],
    ));

    // By arrival order the 10-byte one would win. The 20-byte one won.
    expect(find.text('20.0 B, fast'), findsOneWidget);
  });

  testWidgets('reversing addon order swaps the highlight', (tester) async {
    // The pair of the case above, with arrival order reversed alongside
    // priority: together they separate "the screen passes the user's list" from
    // "the screen passes any list that happened to be right".
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'fast'),
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'slow'),
      ]),
      priority: const ['slow', 'fast'],
    ));

    expect(find.text('10.0 B, slow'), findsOneWidget);
  });

  testWidgets('with no addon in the list, the tiebreak falls back to arrival order', (tester) async {
    // A user who removed every addon and kept only the cache. An empty list
    // must not throw nor drop the highlight.
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'slow'),
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'fast'),
      ]),
      priority: const [],
    ));

    expect(find.text('10.0 B, slow'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: the first two cases fail with `Expected: exactly one matching candidate / Actual: _TextFinder:<zero widgets>`, because the screen still passes no priority and the highlight comes out in arrival order. The third already passes, and that is correct: it is a safety net, not the driving assertion.

- [ ] **Step 3: The detail screen passes the priority**

In `lib/screens/game_detail_screen.dart`, add the import:

```dart
import 'package:roms_downloader/providers/addon_provider.dart';
```

and the new line in the call at lines 74 to 78:

```dart
    final plan = planFromEntries(
      [PackGridEntry(game: game, sources: [for (final v in split.eligible) v.source])],
      preferredRegions: ref.watch(preferredRegionsProvider),
      resolveGame: resolver,
      sourcePriority: ref.watch(sourcePriorityProvider),
    );
```

`watch`, not `read`, like the neighbors: dragging an addon on the addons screen must redraw the highlight on an open detail screen behind it.

- [ ] **Step 4: The home screen passes the priority**

In `lib/screens/home_screen.dart`, add the import:

```dart
import 'package:roms_downloader/providers/addon_provider.dart';
```

and the new line in `_selectionPlan`, lines 43 to 47:

```dart
      return planFromEntries(
        entriesForSelection(ref.read(allPackEntriesProvider), selected),
        preferredRegions: ref.read(preferredRegionsProvider),
        resolveGame: ref.read(gameResolverProvider),
        sourcePriority: ref.read(sourcePriorityProvider),
      );
```

`read`, not `watch`, like the neighbors: this runs inside a button callback, and `watch` outside of `build` is a Riverpod error, not a style choice.

**Likely pitfall:** copying the `watch` from the detail screen into `_selectionPlan`. The method is called from `_confirmBatch`, which is a `Future<void>` triggered by a tap. `ref.watch` there throws at runtime, and the test that would catch it does not exist, because `HomeScreen` has no test. What catches it is Step 6.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/game_detail_screen_test.dart
```

Expected: zero failures.

- [ ] **Step 6: Compile the full app**

```bash
flutter build linux --debug
```

Expected: `Building Linux application...` and no errors. This is what covers `home_screen.dart`, which has no widget test. It does not prove what appears on screen: it proves the screen compiles with the new call and that no import is missing.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```

Expected: `+500`, zero failures.

- [ ] **Step 8: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/game_detail_screen_test.dart
git commit -m "test(addon): as telas passam a ordem de addons do usuario para a regra de escolha"
git add lib/screens/game_detail_screen.dart lib/screens/home_screen.dart
git commit -m "feat(addon): as telas passam a ordem de addons do usuario para a regra de escolha"
```

### Task 17: the detail screen shows the addon name, not the id

**Files:**
- Modify: `lib/providers/addon_provider.dart` (gains `addonNamesProvider`)
- Modify: `lib/screens/game_detail_screen.dart` (`_Highlight` and `_OtherSources`/`_SourceRow` gain the map)
- Test: `test/addon_provider_test.dart`, `test/game_detail_screen_test.dart`

UI spec section 7 asks for "4.0 MB, Myrient". After Task 15, `SourcePick.sourceId` is `myrient_org_files`, because `Addon.idFromUrl` normalizes the URL to become a vault key and filename. A key is for machines. The screen must show `Addon.name`.

The two sites that draw the id are `game_detail_screen.dart:346`, inside `_Highlight`, and `:501`, inside `_SourceRow`. Both are `StatelessWidget`, and the file has a written rule about this: *"The child widgets never see `ref`"* (`game_detail_screen.dart:55`). So the map descends as data, like everything else. Do not turn `_Highlight` into a `ConsumerWidget`.

**How current these line numbers are.** Every `game_detail_screen.dart:NNN` here was verified against the tree **after Task 16**, which is what you will find. Task 16 added two lines to this file, and they do not shift everything uniformly: the `addon_provider.dart` import lands above everything, but the `sourcePriority:` argument falls at line 79, meaning **below** `final resolver` and the dumb-widgets comment. So those two shifted by one line only, and the rest by two. Measured, not calculated: "add 2 to everything" was wrong for the first two before Task 16 ran.

- [ ] **Step 1: Write the failing tests**

In `test/addon_provider_test.dart`, add the case at the end of `main`:

```dart
  test('addonNames maps each id to the addon name', () async {
    final m = await _build(const [
      Addon(id: 'myrient', name: 'Myrient'),
      Addon(id: kBuiltinAddonId, name: 'Built-in catalog'),
    ]);

    expect(m.container.read(addonNamesProvider), {
      'myrient': 'Myrient',
      kBuiltinAddonId: 'Built-in catalog',
    });
  });
```

In `test/game_detail_screen_test.dart`, give `_host` the names map:

```dart
Widget _host(
  PackGridEntry entry, {
  void Function(SourcePick)? onDownload,
  VoidCallback? onBatchDownload,
  GameResolver? resolver,
  SourceVerification Function(String filename)? verification,
  List<String> priority = const [],
  Map<String, String> names = const {},
}) {
```

with the override right below the priority override, for the same reason (the real provider reads `addonProvider`, which opens disk):

```dart
      addonNamesProvider.overrideWithValue(names),
```

and the same line, with `const {}`, in the standalone `ProviderScope` of the test `'the checkbox toggles selection by pack key'`.

Note that the default is an empty map, and it is that default which keeps the nine `'... listagem ...'` expectations in the file green: without a known name, the screen draws the id, and in those tests the id is `'listagem'`.

Add the three cases at the end of `main`:

```dart
  testWidgets('the highlight shows the addon name, not the id', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [_source('Crystal Vanguard (USA).zip', sourceId: 'myrient_org_files')]),
      names: const {'myrient_org_files': 'Myrient'},
    ));

    expect(find.text('4.0 MB, Myrient'), findsOneWidget);
  });

  testWidgets('the other-sources list also shows the name', (tester) async {
    await tester.pumpWidget(_host(
      _entry(sources: [
        _source('Crystal Vanguard (USA).zip', size: 10, sourceId: 'myrient_org_files'),
        _source('Crystal Vanguard (USA).zip', size: 20, sourceId: 'someones_archive'),
      ]),
      names: const {'myrient_org_files': 'Myrient', 'someones_archive': "Someone's Files"},
    ));

    await tester.tap(find.text('other source'));
    await tester.pumpAndSettle();

    expect(find.text("20.0 B, Someone's Files, HTTP, likely match"), findsOneWidget);
  });

  testWidgets('an addon no longer in the list falls back to the id, not blank', (tester) async {
    // The user removed the addon and its game cache is still on disk. The info
    // goes stale and must still exist: "4.0 MB, " with a dangling comma is worse
    // than an ugly id.
    await tester.pumpWidget(_host(
      _entry(sources:[_source('Crystal Vanguard (USA).zip', sourceId: 'addon_removed')]),
      names: const {},
    ));

    expect(find.text('4.0 MB, addon_removed'), findsOneWidget);
  });
```

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/addon_provider_test.dart test/game_detail_screen_test.dart
```

Expected: compilation error, `Undefined name 'addonNamesProvider'`.

- [ ] **Step 3: The names map provider**

In `lib/providers/addon_provider.dart`, right below `sourcePriorityProvider`:

```dart
/// Addon id to the display name the user wrote or the catalog carried.
///
/// Callers must handle a missing id: a removed addon's cached games outlive
/// the removal, and their `sourceId` is no longer in the list.
final addonNamesProvider = Provider<Map<String, String>>(
  (ref) => {for (final addon in ref.watch(addonProvider)) addon.id: addon.name},
);
```

- [ ] **Step 4: The map descends to those that draw**

In `lib/screens/game_detail_screen.dart`, inside `build`, right after `final resolver = ref.watch(gameResolverProvider);` (line 62):

```dart
    final addonNames = ref.watch(addonNamesProvider);
```

pass it to `_Highlight` (lines 136 to 144):

```dart
            _Highlight(
              pick: choice,
              addonNames: addonNames,
              verification: winner.state,
              crcConfirmed: split.confirmed,
              hesitating: split.verifying && !split.confirmed,
              onDownload: () => onDownload(choice),
            ),
```

and to `_OtherSources` (lines 154 to 160):

```dart
            _OtherSources(
              sources: others,
              addonNames: addonNames,
              discarded: split.discarded.length,
              startsOpen: split.noCertainty,
              onDownload: split.noCertainty ? downloadSource : null,
            ),
```

In `_Highlight` (line 277), add the field and the parameter:

```dart
class _Highlight extends StatelessWidget {
  final SourcePick pick;
  final Map<String, String> addonNames;
  final SourceVerification verification;
  final bool crcConfirmed;
  final bool hesitating;
  final VoidCallback onDownload;

  const _Highlight({
    required this.pick,
    required this.addonNames,
    required this.verification,
    required this.crcConfirmed,
    required this.hesitating,
    required this.onDownload,
  });
```

and replace the size/addon line:

```dart
            '${formatBytes(pick.size)}, ${addonNames[pick.sourceId] ?? pick.sourceId}'
            '${badge == null ? '' : ', $badge'}',
```

In `_OtherSources` (line 420), add the field, the parameter, and the pass-through:

```dart
class _OtherSources extends StatelessWidget {
  final List<VerifiedSource> sources;
  final Map<String, String> addonNames;
  final int discarded;
  final bool startsOpen;
  final void Function(VerifiedSource item)? onDownload;

  const _OtherSources({
    required this.sources,
    required this.addonNames,
    required this.discarded,
    required this.startsOpen,
    required this.onDownload,
  });
```

```dart
          for (final item in sources)
            _SourceRow(
              item: item,
              addonNames: addonNames,
              onDownload: onDownload == null ? null : () => onDownload!(item),
            ),
```

In `_SourceRow` (line 467):

```dart
class _SourceRow extends StatelessWidget {
  final VerifiedSource item;
  final Map<String, String> addonNames;
  final VoidCallback? onDownload;

  const _SourceRow({required this.item, required this.addonNames, required this.onDownload});
```

and replace the size/addon line:

```dart
            '${formatBytes(item.source.size)}, '
            '${addonNames[item.source.sourceId] ?? item.source.sourceId}, '
```

**Likely pitfall:** replacing `?? item.source.sourceId` with `?? ''` or `?? 'unknown'`. The first leaves `"4.0 MB, , HTTP, ..."` on screen with a dangling comma, and that is what happens with every game in the cache of a removed addon. The second erases the only clue the user has about where the file came from. The ugly id is the right answer here.

**Second pitfall:** turning `_Highlight` or `_SourceRow` into a `ConsumerWidget` to read the provider directly. That works and breaks the rule written at `game_detail_screen.dart:55`, which exists for a reason measured in slice 3: the child widgets are tested via `_host`, with injected data, and a `ref` inside them would require every child widget test to mount a `ProviderScope`.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addon_provider_test.dart test/game_detail_screen_test.dart
```

Expected: zero failures. The nine `'... listagem ...'` expectations remain green, because the `_host` default map is empty and the screen falls back to the id.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```

Expected: `+504`, zero failures.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_provider_test.dart test/game_detail_screen_test.dart
git commit -m "test(addon): a tela de detalhe mostra o nome do addon, com o id como reserva"
git add lib/providers/addon_provider.dart lib/screens/game_detail_screen.dart
git commit -m "feat(addon): a tela de detalhe mostra o nome do addon, com o id como reserva"
```

**End of Group 4.** Multi-addon is complete on the inside: each source says where it came from, the user's order decides the tiebreak, and the screen speaks the name they gave. What does not exist yet is the screen where they install, drag, and remove, nor the accounts screen with the plaintext vault warning. That is Group 5.

| Task | New | Cumulative |
| --- | --- | --- |
| 15, addon id in the grid and batch | 3 | 497 |
| 16, priority reaches the screens | 3 | 500 |
| 17, addon name on screen | 4 | 504 |

---

## Group 5: the screens

Everything UI spec section 9 asks for exists on the inside and has no door. The user cannot install an addon other than the builtin, cannot drag the order that `sourcePriorityProvider` derives, cannot type a third-party addon's token, does not see all their accounts in one place, and does not receive the warning that the vault fell back to plaintext. This group is what turns seventeen plumbing Tasks into software someone can use.

The ordering has one criterion: **never deliver a dead UI element**. Each Task leaves the screen it created fully wired before the next one begins. That is why the install service comes before the detail screen, the detail screen before the list that opens it, and the entry points last, when there is already somewhere to send the user. The consolidated Accounts closes the group because it reunites what the earlier Tasks scattered: without the addon list and without the per-pair form, there would be nothing to reunite.

Before the screens come two Tasks with no pixels, for the usual reason: what can be tested as a pure function does not go inside a widget. Task 18 extracts from the merged catalog the three questions the screens ask, and Task 19 closes the last half of the vault, which is the token moving from per-console to per-pair (addon, console).

**What this group does not do, stated here so it is not discovered in review:** section 9 asks, under Coverage, "which consoles it serves **and how many items in each**." The per-console item count only exists after `loadCatalog`, which is a network call by URL. Drawing it on the detail screen would mean fetching N catalogs when opening an addon's screen. It is left out, with Coverage showing the consoles but not the count, and the Group 6 sweep lists this as a known gap rather than claiming section 9 is complete.

---

### Task 18: the three questions the screens ask the catalog

**Files:**
- Modify: `lib/models/console_model.dart:84-95` (the getter becomes a call)
- Modify: `lib/services/console_merge.dart` (gains `authForAddon`, `AddonCoverage`, and `MergedCatalog.coverage`)
- Modify: `lib/providers/addon_provider.dart` (gains `addonCoverageProvider`)
- Test: `test/addon_coverage_test.dart`

Three questions, and none of them has an answer today:

1. **"does this source require an account?"** `Console.hasTokenAuth` answers for the console, and since Group 3 the auth that matters is the source's: with two addons serving the same console, `Console.auth` is that of the first one that declared it. A caller with a `ConsoleSource` in hand has no `Console` to call the getter on.
2. **"with what auth does this addon speak on this console?"** That is what the Task 19 `download_provider` needs to stop sending one server's cookie to another.
3. **"what does this addon cover?"** That is the `"25 consoles"` and the account chip in the section 9 row.

All three are pure functions over data the merge already has. Writing this inside the screens would turn a testable rule into a widget test.

The test file is new, `test/addon_coverage_test.dart`, for two reasons: there is no `Console` model test file in the repository (`ls test/` has none), and `test/console_merge_test.dart` has existed since Task 10 with the eleven merge cases, which are about something else.

- [ ] **Step 1: Write the failing tests**

Create `test/addon_coverage_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/console_merge.dart';

Console _console(String id, List<String> urls, {Map<String, dynamic>? auth}) =>
    Console(id: id, name: id.toUpperCase(), urls: urls, auth: auth);

AddonCatalog _catalog(String addonId, Map<String, Console> consoles) => (addonId: addonId, consoles: consoles);

void main() {
  group('authNeedsToken', () {
    test('console with no auth block needs no token', () {
      expect(authNeedsToken(null), isFalse);
    });

    test('the harvest mark alone is enough', () {
      // `requires_token` is what the harvest writes in place of the token it
      // strips from the shareable file.
      expect(authNeedsToken(const {'requires_token': true}), isTrue);
    });

    test('the raw catalog field still counts', () {
      // The built-in never went through the harvest, nor did a hand-opened file.
      expect(authNeedsToken(const {'token': 'tok'}), isTrue);
    });

    test('the login message alone counts', () {
      expect(authNeedsToken(const {'auth_message': 'Ask for an invite on the forum.'}), isTrue);
    });

    test('ia_s3 needs no token, even with the mark', () {
      // Internet Archive signs differently and has its own screen in Accounts.
      expect(authNeedsToken(const {'type': 'ia_s3', 'requires_token': true}), isFalse);
    });

    test('auth that says nothing about a token needs none', () {
      expect(authNeedsToken(const {'cookies': true, 'cookie_name': 'sess'}), isFalse);
    });

    test('hasTokenAuth is the function, not a second rule', () {
      // Guards against the duplication returning: if someone edits one of the
      // two places, this expect stops holding.
      const auth = {'requires_token': true};
      expect(_console('snes', const ['https://a/'], auth: auth).hasTokenAuth, authNeedsToken(auth));
      expect(_console('snes', const ['https://a/']).hasTokenAuth, authNeedsToken(null));
    });
  });

  group('authForAddon', () {
    final merged = mergeCatalogs([
      _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      _catalog('ultranx', {
        'snes': _console('snes', const ['https://ultranx/snes/'], auth: const {'token': 'tok', 'cookies': true}),
      }),
    ]);

    test('returns the auth of the requested addon\'s source', () {
      expect(authForAddon(merged.sources['snes']!, 'ultranx'), {'token': 'tok', 'cookies': true});
    });

    test('addon that does not serve this console returns null', () {
      expect(authForAddon(merged.sources['snes']!, 'someones-archive'), isNull);
    });

    test('addon that serves without declaring auth also returns null', () {
      // Both absences become the same `null` on purpose: the reader treats them
      // alike, sending no header.
      expect(authForAddon(merged.sources['snes']!, 'myrient'), isNull);
    });

    test('between two sources of the same addon, the first wins', () {
      const list = [
        ConsoleSource(addonId: 'a', url: 'https://one/', auth: {'token': 'first'}),
        ConsoleSource(addonId: 'a', url: 'https://two/', auth: {'token': 'second'}),
      ];

      expect(authForAddon(list, 'a'), {'token': 'first'});
    });
  });

  group('coverage', () {
    test('lists each addon\'s consoles', () {
      final merged = mergeCatalogs([
        _catalog('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/']),
          'md': _console('md', const ['https://myrient/md/']),
        }),
        _catalog('ultranx', {'switch': _console('switch', const ['https://ultranx/'])}),
      ]);

      expect(merged.coverage()['myrient']!.consoles, ['snes', 'md']);
      expect(merged.coverage()['ultranx']!.consoles, ['switch']);
    });

    test('a console served by two addons counts for both', () {
      final merged = mergeCatalogs([
        _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalog('acme', {'snes': _console('snes', const ['https://acme/snes/'])}),
      ]);

      expect(merged.coverage()['myrient']!.consoles, ['snes']);
      expect(merged.coverage()['acme']!.consoles, ['snes']);
    });

    test('two urls of the same addon on the same console count one console', () {
      // The count is "25 consoles", not "25 urls". One more mirror does not make
      // the source bigger.
      final merged = mergeCatalogs([
        _catalog('myrient', {
          'snes': _console('snes', const ['https://myrient/snes/', 'https://mirror/snes/']),
        }),
      ]);

      expect(merged.coverage()['myrient']!.consoles, ['snes']);
    });

    test('authConsoles carries only the consoles that need an account', () {
      final merged = mergeCatalogs([
        _catalog('ultranx', {
          'switch': _console('switch', const ['https://ultranx/switch/'], auth: const {'requires_token': true}),
          'wiiu': _console('wiiu', const ['https://ultranx/wiiu/']),
        }),
      ]);

      final coverage = merged.coverage()['ultranx']!;

      expect(coverage.consoles, ['switch', 'wiiu']);
      expect(coverage.authConsoles, ['switch']);
    });

    test('addon with no account on any console has empty authConsoles', () {
      // This empty is what hides the account chip, and it must be an empty list,
      // not `null`: the screen asks `isNotEmpty`.
      final merged = mergeCatalogs([
        _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
      ]);

      expect(merged.coverage()['myrient']!.authConsoles, isEmpty);
    });

    test('addon serving no console does not appear in the map', () {
      // A freshly installed addon whose catalog is not read yet, or one whose
      // url died. The row treats absent as zero, so the screen uses a fallback
      // record instead of `!`.
      final merged = mergeCatalogs([
        _catalog('myrient', {'snes': _console('snes', const ['https://myrient/snes/'])}),
        _catalog('empty', const {}),
      ]);

      expect(merged.coverage().containsKey('empty'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addon_coverage_test.dart
```

Expected: compilation error, `Undefined name 'authNeedsToken'`.

- [ ] **Step 3: The token rule moves out of the getter**

In `lib/models/console_model.dart`, **above** the `class Console {` declaration at line 1, add the top-level function:

```dart
/// Whether this `auth` block means the console needs a user token.
///
/// A top-level function, not just a getter, so a caller holding a source
/// (`ConsoleSource.auth`) can ask without a `Console`.
bool authNeedsToken(Map<String, dynamic>? auth) {
  if (auth == null) return false;
  if (auth['type'] == 'ia_s3') return false;
  return auth['requires_token'] == true || auth.containsKey('token') || auth.containsKey('auth_message');
}
```

and replace lines 84 to 95 with:

```dart
  /// True when this console uses a user-editable bearer/cookie token for auth.
  /// IA S3 auth is managed separately via the Internet Archive login flow.
  bool get hasTokenAuth => authNeedsToken(auth);
```

**Two caveats about that range, because it has been written wrong two ways.** The first is that it is 84 to 95, not 55 to 59: the plan was written against `ef5ee57`, and since then Task 8 added five comment lines inside the getter and Task 10 added `withUrls` above it. Verify before deleting: `sed -n '84,95p' lib/models/console_model.dart` must start at `/// True when this console uses` and end at the getter's `}`. The second is that the range **includes the two doc lines**, not just the body. It must, because the block above already brings those two lines back; replacing only the body would leave the doc duplicated. That was the second form of the error, present since the first version of the plan regardless of the offset.

The five comment lines Task 8 put inside the getter disappear here, and that is relocation not loss: they explained `requires_token` and the harvest, and that text is now in the `authNeedsToken` doc above, where the rule lives.

**Likely pitfall:** copying the rule into the function and leaving the old body in the getter, "to avoid touching what works." It behaves the same today and diverges the first day someone fixes one of the two. The case `'hasTokenAuth is the function, not a second rule'` exists to catch this, and it passes with duplication: what it fixes is that the two agree, and what prevents divergence is the delegation. Delegate.

- [ ] **Step 4: The per-addon auth and coverage**

In `lib/services/console_merge.dart`, right after the `typedef AddonCatalog`, add:

```dart
/// The auth [addonId] speaks in this console, or `null` if it doesn't serve
/// it. Not serving and serving without auth both return `null`.
Map<String, dynamic>? authForAddon(List<ConsoleSource> sources, String addonId) {
  for (final source in sources) {
    if (source.addonId == addonId) return source.auth;
  }
  return null;
}

/// What an addon covers: the consoles it serves, and which of them need auth.
typedef AddonCoverage = ({List<String> consoles, List<String> authConsoles});
```

and, inside `MergedCatalog`, right after `isEmpty`:

```dart
  /// From each addon to what it covers.
  ///
  /// An addon serving no console is absent from the map; readers treat absent
  /// as zero coverage.
  Map<String, AddonCoverage> coverage() {
    final byAddon = <String, List<String>>{};
    final withAccount = <String, List<String>>{};

    for (final entry in sources.entries) {
      final seen = <String>{};
      for (final source in entry.value) {
        if (!seen.add(source.addonId)) continue;
        byAddon.putIfAbsent(source.addonId, () => <String>[]).add(entry.key);
        if (authNeedsToken(source.auth)) {
          withAccount.putIfAbsent(source.addonId, () => <String>[]).add(entry.key);
        }
      }
    }

    return {
      for (final entry in byAddon.entries)
        entry.key: (consoles: entry.value, authConsoles: withAccount[entry.key] ?? const <String>[]),
    };
  }
```

**Likely pitfall:** deduplicating the addon with a `Set` outside the console loop, instead of one per console. That would enter the addon once into the entire map and its coverage would always become `["snes"]`, the first console it served. The `seen` set is born inside the `sources.entries` loop, and that is why.

- [ ] **Step 5: The provider the screens override**

In `lib/providers/addon_provider.dart`, right after `addonNamesProvider`:

```dart
/// Per-addon coverage, derived from the merged catalog.
final addonCoverageProvider = FutureProvider<Map<String, AddonCoverage>>((ref) async {
  return (await ref.watch(mergedCatalogProvider.future)).coverage();
});
```

with the new import:

```dart
import 'package:roms_downloader/services/console_merge.dart';
```

- [ ] **Step 6: Run to see it pass**

```bash
flutter test test/addon_coverage_test.dart
```

Expected: `+17`, zero failures.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```

Expected: `+521`, zero failures.

- [ ] **Step 8: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/addon_coverage_test.dart
git commit -m "test(addon): auth por fonte e cobertura por addon sobre o catalogo fundido"
git add lib/models/console_model.dart lib/services/console_merge.dart lib/providers/addon_provider.dart
git commit -m "feat(addon): auth por fonte e cobertura por addon sobre o catalogo fundido"
```

---

### Task 19: the token moves from the console to the (addon, console) pair

**Files:**
- Modify: `lib/services/settings_service.dart` (`clearConsoleToken` becomes `writeAddonToken`, plus `readAddonToken`)
- Modify: `lib/providers/settings_provider.dart` (`ready`, `setAddonToken`, `readAddonToken`, `setConsoleAuthToken` delegates)
- Modify: `lib/utils/console_auth.dart` (gains `addonsThatNeedToken`)
- Modify: `lib/providers/download_provider.dart:429-441`
- Modify: `lib/services/task_queue_service.dart:15-26`
- Modify: `test/settings_service_test.dart` (one case switches method, and the file count does not change)
- Test: `test/addon_token_test.dart`

Task 13 already made the **catalog** fetch each URL with the token of the addon that owns it. Two paths talking about a per-console token remained: downloading a file (`download_provider.dart:434`) and blocking the batch (`task_queue_service.dart:18-24`). Both still read `settings.consoleSettings[consoleId].authToken`, which is the builtin mirror. With two addons on the same console, the first sends the builtin's token to the third-party server, and the second blocks the entire batch because of an account that may not belong to the source the game came from.

Two decisions inside this Task are worth reading before the code.

**The mirror stays, and stays only for the builtin.** It would be tempting to hydrate every addon token into `AppSettings.consoleSettings` and let everyone read from there, synchronously. That doesn't work, for two independent reasons. The first is a contract reason: `SecretVault` does not enumerate, has no `readAll`, and that is intentional (Task 2), so the app cannot discover which pairs have a secret without already knowing the list. The second is a security reason: `consoleHasToken` and the two LAN `_authHeaders` read that mirror synchronously and without knowing which addon it belongs to, so a third-party token mirrored there would go out through the Tinfoil server as if it were the builtin's. Whoever needs a third-party token reads on demand, from the vault.

**Batch blocking is now per source.** Today it is `console.hasTokenAuth`, a question about the console. A console served by an open addon and a private one would block the download of the open file because of the private addon's account. The new rule asks which of the addons that served **these games** need a token, and charges only those.

- [ ] **Step 1: Write the failing tests**

Create `test/addon_token_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/utils/console_auth.dart';

/// Container with the real `settingsProvider` over a fake vault.
///
/// `app_settings` is seeded with `{}` on purpose. Without the key,
/// `loadSettings` falls into the default branch, which calls
/// `DirectoryService.getDownloadDir`, which on Android asks for permission via
/// plugin and gets no reply in a platformless test. With the key, loading
/// follows the normal path and `AppSettings.fromJson({})` returns the defaults.
Future<({ProviderContainer container, MemoryVault vault})> _build() async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final vault = MemoryVault();
  final container = ProviderContainer(overrides: [
    vaultProvider.overrideWith((ref) async => VaultChoice(vault, encryptedAtRest: true)),
  ]);
  addTearDown(container.dispose);
  await container.read(settingsProvider.notifier).ready;
  return (container: container, vault: vault);
}

Game _game(String title, {required String sourceId}) => Game(
      title: title,
      url: 'https://example.org/snes/$title',
      size: 2048,
      consoleId: 'snes',
      sourceId: sourceId,
    );

ConsoleSource _source(String addonId, {Map<String, dynamic>? auth}) =>
    ConsoleSource(addonId: addonId, url: 'https://$addonId/snes/', auth: auth);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('setAddonToken and readAddonToken', () {
    test('writes the token under the (addon, console) pair key', () async {
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok');
      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), 'tok');
    });

    test('reading what was never written returns empty, not null', () async {
      // Empty, not `null`, because every caller asks `isEmpty`. The vault
      // returns `null`, and this is where the translation happens, once only.
      final m = await _build();

      expect(await m.container.read(settingsProvider.notifier).readAddonToken('ultranx', 'snes'), '');
    });

    test('empty token deletes the key', () async {
      final m = await _build();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken('ultranx', 'snes', 'tok');

      await notifier.setAddonToken('ultranx', 'snes', '');

      expect(await m.vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    });

    test('the builtin token mirrors into settings', () async {
      // The mirror is what keeps `consoleHasToken` and the two LAN
      // `_authHeaders` alive, which read synchronously and know nothing about addons.
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });

    test('a third-party addon token does not mirror into settings', () async {
      // The case that makes this Task a security task. If it mirrored, the
      // Tinfoil server would send the UltraNX credential to the builtin server,
      // because it reads the mirror without asking which addon it belongs to.
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setAddonToken('ultranx', 'snes', 'tok');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
    });

    test('deleting the builtin token clears the mirror', () async {
      final m = await _build();
      final notifier = m.container.read(settingsProvider.notifier);
      await notifier.setAddonToken(kBuiltinAddonId, 'snes', 'tok');

      await notifier.setAddonToken(kBuiltinAddonId, 'snes', '');

      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, isNull);
      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), isNull);
    });

    test('two addons on the same console keep separate tokens', () async {
      final m = await _build();
      final notifier = m.container.read(settingsProvider.notifier);

      await notifier.setAddonToken('ultranx', 'snes', 'tok-ultranx');
      await notifier.setAddonToken('acme', 'snes', 'tok-acme');

      expect(await notifier.readAddonToken('ultranx', 'snes'), 'tok-ultranx');
      expect(await notifier.readAddonToken('acme', 'snes'), 'tok-acme');
    });

    test('setConsoleAuthToken is the builtin special case', () async {
      // Four screens still call the old name. It cannot silently become
      // something else underneath.
      final m = await _build();

      await m.container.read(settingsProvider.notifier).setConsoleAuthToken('snes', 'tok');

      expect(await m.vault.read(SecretRef.addonToken(kBuiltinAddonId, 'snes')), 'tok');
      expect(m.container.read(settingsProvider).consoleSettings['snes']?.authToken, 'tok');
    });
  });

  group('addonsThatNeedToken', () {
    test('addon whose source needs a token is included', () {
      final needing = addonsThatNeedToken(
        [_game('Aethel.nsp', sourceId: 'ultranx')],
        [_source('ultranx', auth: const {'requires_token': true})],
      );

      expect(needing, ['ultranx']);
    });

    test('addon whose source does not need a token is excluded', () {
      final needing = addonsThatNeedToken(
        [_game('Crystal Vanguard (USA).zip', sourceId: 'myrient')],
        [_source('myrient')],
      );

      expect(needing, isEmpty);
    });

    test("one addon's account does not block the other's download", () {
      // The reason the question is per-source. The console is served by both,
      // and the batch only has a file from the open one: charging the private
      // addon's account here would block a download that doesn't need it.
      final needing = addonsThatNeedToken(
        [_game('Crystal Vanguard (USA).zip', sourceId: 'myrient')],
        [_source('myrient'), _source('ultranx', auth: const {'requires_token': true})],
      );

      expect(needing, isEmpty);
    });

    test('game from an addon that no longer serves this console is excluded', () {
      // Cache from a removed addon. Blocking because of it would charge an
      // account for a source that no longer exists, and the user would have
      // nowhere to type it.
      final needing = addonsThatNeedToken(
        [_game('Aethel.nsp', sourceId: 'removed')],
        [_source('myrient')],
      );

      expect(needing, isEmpty);
    });

    test('each addon appears once, even with many games', () {
      final needing = addonsThatNeedToken(
        [
          _game('Aethel.nsp', sourceId: 'ultranx'),
          _game('Kaelis.nsp', sourceId: 'ultranx'),
          _game('Pixel.nsp', sourceId: 'ultranx'),
        ],
        [_source('ultranx', auth: const {'requires_token': true})],
      );

      expect(needing, ['ultranx']);
    });
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addon_token_test.dart
```

Expected: compile error, `The method 'setAddonToken' isn't defined`.

- [ ] **Step 3: The service learns to write, not only to delete**

In `lib/services/settings_service.dart`, replace the entire `clearConsoleToken` method with:

```dart
  /// The token for an (addon, console) pair in the vault. An empty value **deletes**.
  ///
  /// Was `clearConsoleToken(consoleId, vault)`, which knew how to delete but not
  /// write, and assumed the builtin. The addon becomes a parameter because two
  /// addons serving the same console have different tokens, and mixing them means
  /// sending one server's credential to the other.
  ///
  /// Still lives in this class, not in the notifier, because it is the sole owner
  /// of the key format: [_hydrate] and [_writeSecrets] read and write the same
  /// `SecretRef.addonToken`.
  Future<void> writeAddonToken(String addonId, String consoleId, String token, SecretVault vault) async {
    final key = SecretRef.addonToken(addonId, consoleId);
    if (token.isEmpty) return vault.delete(key);
    return vault.write(key, token);
  }

  /// The pair's token, or empty string. The translation from `null` to `''`
  /// happens here, once only, because every caller asks `isEmpty`.
  Future<String> readAddonToken(String addonId, String consoleId, SecretVault vault) async =>
      await vault.read(SecretRef.addonToken(addonId, consoleId)) ?? '';
```

and in the `_writeSecrets` doc, replace the phrase

```dart
  /// a hasty click on boot into losing all credentials, no error on screen.
  /// Deletion is [clearIaSecrets] and [clearConsoleToken], called on purpose.
```

with

```dart
  /// Writes what exists and does not delete what is `null`: a save triggered
  /// while the load is still in flight would otherwise wipe every credential.
  /// Deletion is [clearIaSecrets] and [writeAddonToken] with an empty value.
```

- [ ] **Step 4: Retarget the Task 6 test case**

The case `'clearing one console token leaves the neighbor'`, in `test/settings_service_test.dart`, calls the method that just disappeared. It is still the same case, with the same value: replace the line

```dart
    await SettingsService().clearConsoleToken('snes', vault);
```

with

```dart
    await SettingsService().writeAddonToken(kBuiltinAddonId, 'snes', '', vault);
```

The file count **does not change**. If you find yourself adding a case here, stop: the (addon, console) pair has its own coverage in `test/addon_token_test.dart`, and one more case here would shift the running total of all subsequent Tasks.

- [ ] **Step 5: The notifier gains `ready` and the two per-addon methods**

In `lib/providers/settings_provider.dart`, the top of the class becomes:

```dart
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SettingsService _settingsService = SettingsService();
  final Future<SecretVault> _vault;

  /// Resolves when the initial load from prefs and vault has arrived.
  ///
  /// Exists for tests, and is not decoration: without it, a test that reads
  /// state right after building the container reads `const AppSettings()` and
  /// passes by accident, including after a broken load. Same pattern as
  /// `AddonNotifier.ready` from Task 14.
  late final Future<void> ready;

  SettingsNotifier(this._vault) : super(const AppSettings()) {
    ready = _loadSettings();
  }
```

and the `setConsoleAuthToken` from Task 6 is replaced by three members:

```dart
  /// Saves, or deletes, the token for an (addon, console) pair.
  ///
  /// **The mirror in `AppSettings.consoleSettings` is only touched for the
  /// builtin addon, and that is not an optimization.** `consoleHasToken` (the
  /// two Task 7 screens) and the two LAN `_authHeaders` read that mirror
  /// synchronously and without knowing which addon it belongs to. Mirroring a
  /// third-party token there would make the LAN server send one server's
  /// credential to another, which is the leak that Task 13 just closed.
  ///
  /// The third-party token lives only in the vault. It cannot be hydrated into
  /// `AppSettings` because `SecretVault` does not enumerate: there is no
  /// `readAll`, by design (Task 2), so the app cannot discover which pairs have
  /// a secret without already knowing the list. Whoever needs it reads on
  /// demand, via [readAddonToken].
  Future<void> setAddonToken(String addonId, String consoleId, String token) async {
    await _settingsService.writeAddonToken(addonId, consoleId, token, await _vault);
    if (addonId != kBuiltinAddonId) return;

    final current = state.consoleSettings[consoleId] ?? const BaseSettings();
    final updated = token.isEmpty ? current.copyWith(clearAuthToken: true) : current.copyWith(authToken: token);
    await _persist(state.copyWith(
      consoleSettings: {...state.consoleSettings, consoleId: updated},
    ));
  }

  Future<String> readAddonToken(String addonId, String consoleId) async =>
      _settingsService.readAddonToken(addonId, consoleId, await _vault);

  /// The builtin addon special case. Keeps this name because four screens call it.
  Future<void> setConsoleAuthToken(String consoleId, String token) => setAddonToken(kBuiltinAddonId, consoleId, token);
```

with the new import:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

**Likely pitfall:** leaving `_persist` outside the third-party branch "just to be safe". `_persist` calls `saveSettings`, which calls `_writeSecrets`, which writes `SecretRef.addonToken(kBuiltinAddonId, id)` for each console in the mirror. Running it after writing a third-party token causes no corruption, but is a disk write for nothing on every addon token keystroke. The early `return` is intentional.

- [ ] **Step 6: The blocking rule becomes a pure function**

In `lib/utils/console_auth.dart`, add:

```dart
/// The addons that served [games] and whose source on this console needs a token.
///
/// Pure and here, not inside `TaskQueueService._downloadBlockReason`,
/// because that method is static, async, and full of `ref`: without separating,
/// the blocking rule would only be testable through a widget test.
///
/// Two cases deliberately excluded. A game whose `sourceId` is no longer among
/// the console's sources (cache from a removed addon) blocks nothing, because
/// there would be nowhere for the user to type the missing account. And an open
/// addon on the same console as a private one is not infected by the neighbor's
/// account: downloading from the open one doesn't need it.
List<String> addonsThatNeedToken(List<Game> games, List<ConsoleSource> sources) {
  final needing = <String>{};
  final seen = <String>{};
  for (final source in sources) {
    if (!seen.add(source.addonId)) continue;
    if (authNeedsToken(source.auth)) needing.add(source.addonId);
  }

  return [
    for (final addonId in {for (final game in games) game.sourceId})
      if (needing.contains(addonId)) addonId,
  ];
}
```

with the new imports:

```dart
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/services/console_merge.dart';
```

- [ ] **Step 7: The batch charges per source**

In `lib/services/task_queue_service.dart`, replace **lines 15 to 26** with:

```dart
    final catalogService = CatalogService();
    final console = (await catalogService.getConsoles())[consoleId];
    if (console == null) return null;

    final settingsNotifier = ref.read(settingsProvider.notifier);

    // Per source, not per console. A console served by an open addon and a
    // private one would block the open file because of the private addon's
    // account, which that download doesn't need.
    for (final addonId in addonsThatNeedToken(games, await catalogService.sourcesFor(console.id))) {
      if ((await settingsNotifier.readAddonToken(addonId, console.id)).isEmpty) {
        return console.authMessage ?? 'This system requires authentication. Sign in from the system settings first.';
      }
    }
```

**Check the range before deleting**, because an earlier version of this Task said `14-24` and line 14 is the **signature** of `_downloadBlockReason`, which does not leave. Measured in the tree: line 15 is `final console = (await CatalogService().getConsoles())[consoleId];`, line 24 is the `}` closing `if (console.hasTokenAuth)`, line 25 is blank, and line 26 is `final settingsNotifier = ref.read(settingsProvider.notifier);`. All twelve leave together: the `settingsNotifier` from line 26 does not disappear, it moves up into the block above, and the NSZ block, which starts at line 27, stays the same and keeps using that same `settingsNotifier`. Leave a blank line between the `for`'s `}` and the NSZ `if`.

The imports change: add

```dart
import 'package:roms_downloader/utils/console_auth.dart';
```

and keep `import 'package:roms_downloader/providers/settings_provider.dart';`, because that is where `settingsProvider` comes from.

**Likely pitfall:** the message. It stays as `console.authMessage ?? ...`, exactly as it is today, and does not name the addon. Naming it would be better and would cost bringing `addonNamesProvider` into a static method in a commit that is about which account is charged. Left as-is, on purpose.

- [ ] **Step 8: The download uses the auth and token of the file's source**

In `lib/providers/download_provider.dart`, replace the block on lines 429 to 441 with:

```dart
    final settings = _ref.read(settingsProvider);
    final catalogService = CatalogService();
    final isIaUrl = game.url.contains('archive.org/download/');
    // Auth is per source, not per console: `console.auth` is the first addon's,
    // so using it here would send one server's cookie with another's token.
    final auth = authForAddon(await catalogService.sourcesFor(game.consoleId), game.sourceId);
    final token = await _ref.read(settingsProvider.notifier).readAddonToken(game.sourceId, game.consoleId);
    final headers = <String, String>{
      ...buildConsoleAuthHeaders(auth, tokenOverride: token.isEmpty ? null : token),
      if (isIaUrl && (settings.iaCookies?.isNotEmpty ?? false))
        'Cookie': settings.iaCookies!
      else if (isIaUrl && (settings.iaAccessKey?.isNotEmpty ?? false) && (settings.iaSecretKey?.isNotEmpty ?? false))
        'Authorization': 'LOW ${settings.iaAccessKey}:${settings.iaSecretKey}',
    };
```

with the new import:

```dart
import 'package:roms_downloader/services/console_merge.dart';
```

Note that the line `final console = (await CatalogService().getConsoles())[game.consoleId];` **leaves**. It only existed for `console?.auth`, and leaving it becomes `unused_local_variable`, which is an extra finding in `flutter analyze` and breaks the `22 issues found` target.

**Likely pitfall:** keeping a `?? console?.auth` fallback "to avoid breaking old cache". That undoes the entire Task in the most dangerous case, which is exactly the console with two addons. Cache from before the slice has `sourceId == kBuiltinAddonId` (the default of `Game.fromJson` from Task 12), and the builtin is among the sources, so that case already works. What remains without a header is cache from a **removed** addon, and for that the right answer is to fail visibly, not to send the neighbor's credential.

**This Step has no test, and it is honest to say so.** `executeDownload` reaches `CatalogService`, `background_downloader`, and disk, and a test here would require three fakes to assert a header map. What has tests is `authForAddon` (Task 18) and `readAddonToken` (this Task), which are the two pieces. The link between them is verified by reading and by the `flutter build linux --debug` in Step 11.

- [ ] **Step 9: Run to see it pass**

```bash
flutter test test/addon_token_test.dart test/settings_service_test.dart
```

Expected: `+13` in the new file, and the service file with the same count as before, zero failures in both.

- [ ] **Step 10: Run the full suite**

```bash
flutter test
```

Expected: `+534`, zero failures.

- [ ] **Step 11: Analyze and build**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found`, build ok.

- [ ] **Step 12: Commit**

```bash
git add test/addon_token_test.dart test/settings_service_test.dart
git commit -m "test(seguranca): token por par addon e console, e bloqueio de lote por fonte"
git add lib/services/settings_service.dart lib/providers/settings_provider.dart lib/utils/console_auth.dart lib/services/task_queue_service.dart lib/providers/download_provider.dart
git commit -m "feat(seguranca): token por par addon e console, e bloqueio de lote por fonte"
```

---

### Task 20: the account form becomes per-addon

**Files:**
- Modify: `lib/widgets/settings/console_auth_setting.dart` (gains `addonId` and reads from the vault)
- Modify: `lib/widgets/settings/settings_content.dart:158`
- Modify: `lib/screens/tinfoil_server_screen.dart:106` (the second caller, plus the import)
- Modify: `lib/screens/setup_wizard_screen.dart:435` (the third caller)
- Modify: `lib/providers/settings_provider.dart:168-174` (two docs left without a reader)
- Test: `test/console_auth_setting_test.dart`

`ConsoleAuthSetting` is the form that section 9 asks for inside the addon detail ("**Account**: the credential form"). It already exists and already knows how to log in by username and password, paste a raw token, show the catalog message, and log out. What it does not know is which addon's token it belongs to: it reads `settingsProvider.consoleSettings[id].authToken`, which after Task 19 is the builtin mirror and nothing else.

The change is about the data source, not about appearance: the token comes from the vault, via the (addon, console) pair, and goes back into the vault via the same pair. Because reading from the vault is async and `initState` is not, the widget gains a loading state. This is visible: for one frame, the form shows a progress bar instead of the field.

The test file is new. None of the four settings widgets has a test today (`grep -rl "ConsoleAuthSetting" test/` finds nothing), and this Task is the first to give one to one of them.

- [ ] **Step 1: Write the failing tests**

Create `test/console_auth_setting_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://example.org/snes/'], auth: {'requires_token': true});

/// `Scaffold` because the widget calls `ScaffoldMessenger` when saving, and
/// `app_settings` seeded with `{}` for the same reason as `addon_token_test`:
/// without the key the load falls into the branch that asks for directory via plugin.
Widget _host(MemoryVault vault, {String addonId = kBuiltinAddonId}) {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  return ProviderScope(
    overrides: [
      vaultProvider.overrideWith((ref) async => VaultChoice(vault, encryptedAtRest: true)),
    ],
    child: MaterialApp(
      home: Scaffold(body: ConsoleAuthSetting(console: _snes, addonId: addonId)),
    ),
  );
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

void main() {
  testWidgets('with no stored token, shows the input field', (tester) async {
    await tester.pumpWidget(_host(MemoryVault()));
    await tester.pumpAndSettle();

    expect(find.text('Bearer token'), findsOneWidget);
    expect(find.text('Signed in'), findsNothing);
  });

  testWidgets('with a token in the vault, shows signed in', (tester) async {
    // The read is async, so the initial state is loading and only then becomes
    // "Signed in". Without `pumpAndSettle`, this case would see the empty form
    // and assert the opposite of what the user sees.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken(kBuiltinAddonId, 'snes'), 'tok');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
  });

  testWidgets('saving writes under the (addon, console) pair key', (tester) async {
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-ultranx');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), 'tok-ultranx');
  });

  testWidgets('the same console on two addons does not share the token', (tester) async {
    // What this Task exists to guarantee. The user has an account on UltraNX
    // but not on the builtin, and both serve `snes`.
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsNothing);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('logging out deletes the pair key', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('ultranx', 'snes'), 'tok-ultranx');

    await tester.pumpWidget(_host(vault, addonId: 'ultranx'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('ultranx', 'snes')), isNull);
    expect(find.text('Bearer token'), findsOneWidget);
  });

  testWidgets('the builtin token still reaches the settings mirror', (tester) async {
    // The mirror is what keeps `consoleHasToken` and the LAN `_authHeaders`
    // alive. Saving through the screen must continue feeding both.
    final vault = MemoryVault();
    await tester.pumpWidget(_host(vault));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'tok-builtin');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(_container(tester).read(settingsProvider).consoleSettings['snes']?.authToken, 'tok-builtin');
  });
}
```

**Why `find.text('Save')` and not `find.widgetWithText(FilledButton, 'Save')`:** `FilledButton.icon` is a factory that returns `_FilledButtonWithIcon`, and `find.byType` matches by exact runtime type (`finders.dart`: `candidate.widget.runtimeType == widgetType`). The type-based finder would find zero and the test would die at `Bad state: No element` before asserting anything, which is exactly what kept `test/rar_decompress_screen_test.dart` red for months. Tapping the `Text` works because it is inside the button's tap area.

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/console_auth_setting_test.dart
```

Expected: compile error, `No named parameter with the name 'addonId'`.

- [ ] **Step 3: The widget becomes per-addon**

In `lib/widgets/settings/console_auth_setting.dart`, the header:

```dart
class ConsoleAuthSetting extends ConsumerStatefulWidget {
  final Console console;

  /// Which addon this account belongs to. The same console can be served by
  /// two addons with different credentials, and the form belongs to one of them.
  final String addonId;

  const ConsoleAuthSetting({super.key, required this.console, required this.addonId});
```

the state gains two fields and loses the synchronous read:

```dart
class _ConsoleAuthSettingState extends ConsumerState<ConsoleAuthSetting> {
  final TextEditingController _tokenController = TextEditingController();
  final Map<String, TextEditingController> _signinControllers = {};

  /// What is currently stored in the vault. Not from `settingsProvider`: that
  /// mirror only covers the builtin addon (Task 19).
  String _saved = '';
  bool _loading = true;
  bool _obscure = true;
  bool _dirty = false;
  bool _signingIn = false;

  List<String> get _signinParams => List<String>.from(widget.console.authSignin?['params'] as List? ?? const []);

  @override
  void initState() {
    super.initState();
    for (final param in _signinParams) {
      _signinControllers[param] = TextEditingController();
    }
    _loadToken();
  }

  /// The vault is async and `initState` is not, so the form starts in loading
  /// state. One frame with a bar is better than one frame with an empty field:
  /// the empty field says "you have no account" to someone who does.
  Future<void> _loadToken() async {
    final token = await ref.read(settingsProvider.notifier).readAddonToken(widget.addonId, widget.console.id);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _tokenController.text = token;
      _loading = false;
    });
  }
```

Note that `_tokenController` is no longer a `late final` with an initial text value; it became an empty controller created in the field: the text arrives in `_loadToken`.

The three methods that write go through the pair:

```dart
  Future<void> _store(String token) async {
    await ref.read(settingsProvider.notifier).setAddonToken(widget.addonId, widget.console.id, token);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _dirty = false;
    });
  }

  Future<void> _signin() async {
    setState(() => _signingIn = true);
    try {
      final token = await signinForToken(
        widget.console.authSignin!,
        {for (final e in _signinControllers.entries) e.key: e.value.text.trim()},
      );
      _tokenController.text = token;
      await _store(token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed in, token saved.'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), duration: const Duration(seconds: 4)),
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _save() async {
    await _store(_tokenController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auth token saved.'), duration: Duration(seconds: 2)),
      );
    }
  }

  Future<void> _clear() async {
    _tokenController.clear();
    await _store('');
  }
```

Today's `_save` calls `setState` **before** the `if (mounted)`, which is a window for `setState() called after dispose` if the user leaves the screen during a save. This disappears because now it is `_store` that calls `setState`, behind its own `if (!mounted) return`. It is not in scope for this Task and comes out for free.

And the `build` swaps the first two lines:

```dart
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      );
    }
    final hasToken = _saved.isNotEmpty;
```

The rest of `build` and `_tokenSection` stay identical.

**Likely pitfall:** leaving `ref.watch(settingsProvider)` in `build` "because it's free". It's not: the widget would rebuild on every save of any setting, and, worse, someone would read the token from there six months from now thinking that is the live value. For a third-party addon it is always `null`. The line goes away.

- [ ] **Step 4: The settings screen says which addon it is**

In `lib/widgets/settings/settings_content.dart`, line 158:

```dart
              // The console settings panel is the door to the builtin catalog.
              // A third-party addon's account is edited in its detail screen (Task 22).
              child: ConsoleAuthSetting(console: selectedConsole!, addonId: kBuiltinAddonId),
```

with the new import:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

- [ ] **Step 4b: The other two callers, or nothing compiles**

`ConsoleAuthSetting` has **three** callers in `lib/`, not one. Step 4 fixes only the settings one. Since Step 3 declares `required this.addonId`, the other two immediately stop compiling with `The named parameter 'addonId' is required`. This is not a lint: it is an error, so Step 6 fails, `flutter analyze` in Step 7 goes from 22 to 24 **with two errors**, and `flutter build linux --debug` does not even finish. An earlier version of this Task listed only `settings_content.dart` in **Files** and omitted the two.

The three are `lib/widgets/settings/settings_content.dart:158`, `lib/screens/tinfoil_server_screen.dart:106`, and `lib/screens/setup_wizard_screen.dart:435` (measured with `grep -rn "ConsoleAuthSetting" lib/`, which also finds the four lines of the declaration itself). In the two new ones the addon is the builtin, for the same reason as Step 4 and because Task 19 already decided: the LAN path and the wizard path read the synchronous mirror, which belongs to the builtin and nobody else.

In `lib/screens/tinfoil_server_screen.dart`, line 106:

```dart
            children: [ConsoleAuthSetting(console: c, addonId: kBuiltinAddonId)],
```

This file does **not** import `addon_model.dart` today (measured), so it gets the import too:

```dart
import 'package:roms_downloader/models/addon_model.dart';
```

In `lib/screens/setup_wizard_screen.dart`, line 435:

```dart
                children: [ConsoleAuthSetting(console: c, addonId: kBuiltinAddonId)],
```

Here the import **already exists**, at line 7, placed by Task 9: the file already writes `kBuiltinAddonId` three times, at lines 100, 112, and 124. Do not duplicate it.

- [ ] **Step 4c: Two notifier methods are left without a reader, and a comment starts lying**

This Task is the one that empties both, so this is where the text gets corrected. None of this breaks the build or lint: both are public, and `unused_element` only catches private declarations. It is text hygiene, and the reason to do it now is that six months from now nobody will remember.

`setConsoleAuthToken` (`settings_provider.dart:170`) carries the doc that Task 19 wrote: *"Keeps this name because four screens call it."* **That was never true.** Measured in `ef5ee57`, before the slice started: there are three calls, and all three in the same file, `console_auth_setting.dart:52`, `:72`, and `:86`. One widget, not four screens. Step 3 replaces all three with `_store`, so after this Task **zero** calls remain in `lib/`, and only the one from Task 19 in `test/addon_token_test.dart:124`.

The method stays, because that test case is the builtin contract and whoever comes next will need it. What goes is the false justification:

```dart
  /// The builtin addon special case: writes to the (builtin, console) pair.
  /// After Task 20 no site in `lib/` calls it, and what keeps it is the case
  /// `'setConsoleAuthToken is the builtin special case'`, which locks the
  /// equivalence with `setAddonToken(kBuiltinAddonId, ...)`.
  Future<void> setConsoleAuthToken(String consoleId, String token) => setAddonToken(kBuiltinAddonId, consoleId, token);
```

`getConsoleAuthToken`, right below, is the other one: `console_auth_setting.dart:29` was its **only** reader in the entire repository (measured in `lib/` and `test/`), and Step 3 deletes that line. It reads the synchronous mirror, which is now only the builtin's, and is exactly the trap that the **Pitfall** in Step 3 describes, except it is a public method rather than a line in `build`. Do not delete it in this Task, which is out of scope, and note that it is a public method with no test covering it. Mark:

```dart
  /// The synchronous mirror of the builtin, and only it. No reader since Task 20:
  /// for a third-party addon it returns `null` even when there is a token in the
  /// vault, so whoever uses this probably wants `readAddonToken`.
  String? getConsoleAuthToken(String consoleId) {
```

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/console_auth_setting_test.dart
```

Expected: `+6`, zero failures.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```

Expected: `+540`, zero failures.

- [ ] **Step 7: Analyze and build**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found`, build ok.

- [ ] **Step 8: Commit**

```bash
git add test/console_auth_setting_test.dart
git commit -m "test(addon): formulario de conta passa a ser do par addon e console"
git add lib/widgets/settings/console_auth_setting.dart lib/widgets/settings/settings_content.dart lib/screens/tinfoil_server_screen.dart lib/screens/setup_wizard_screen.dart lib/providers/settings_provider.dart
git commit -m "feat(addon): formulario de conta passa a ser do par addon e console"
```

---

### Task 21: install an addon from a URL

**Files:**
- Create: `lib/services/addon_install.dart`
- Modify: `lib/services/catalog_service.dart` (`_parseConsoles` becomes public; no line number on purpose, for the same reason as Task 22: Task 13 rewrites this file)
- Test: `test/addon_install_test.dart`

This is the entry point for section 9: "**Add addon**: a URL field and a button". Everything it needs already exists in pieces, and no piece knows about the others. `Addon.idFromUrl` (Task 9) gives the stable key, `CatalogService.harvestAuthTokens` (Task 8) pulls the token from the file and puts it in the vault, and `AddonNotifier.install` (Task 14) writes the catalog and the list. This Task is the glue, and it lives in its own file because it belongs to none of the three: `CatalogService` does not know about `AddonNotifier`, and that is a good thing.

The order of the three calls is not a preference, it is the unconditional half of 6.3: **harvest before validating and before installing**. If validation came first, a catalog that failed for another reason would have gone to disk with the token inside. As it is, nothing is written until the harvest has returned the clean JSON.

A consequence worth saying aloud: when validation fails **after** harvesting, the token stays in the vault and the addon is not installed. That is intentional. The secret came from the file the user themselves sent for installation, storing it means a second attempt will not ask again, and a vault entry under an id that is not in the list is read by nobody: the reader is `SecretRef.addonToken(addonId, consoleId)` from an installed addon.

The network comes in as a parameter. `http` is not a dependency of this project (`grep '^  http:' pubspec.yaml` finds nothing), so `MockClient` does not exist here and the test has no way to intercept a real `HttpClient`. The injectable `CatalogFetcher` is what makes this function testable without a running server.

- [ ] **Step 1: Write the failing tests**

Create `test/addon_install_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _catalogWithToken = '''
[{"name": "SNES", "urls": ["https://example.org/snes/"], "auth": {"token": "file-secret"}}]
''';

const _catalogWithoutConsole = '[]';

/// A notifier with a store in a temp directory and no `path_provider`.
///
/// `invalidateCache` is replaced because the default goes through
/// `getApplicationCacheDirectory`, which throws in a test with no platform.
Future<AddonNotifier> _notifier() async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('addon_install_test');
  addTearDown(() => root.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), root);
  await store.save(const []);
  final notifier = AddonNotifier(Future.value(store), invalidateCache: () async {});
  addTearDown(notifier.dispose);
  await notifier.ready;
  return notifier;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('downloads, harvests the token and installs the clean catalog', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    final addon = await installAddonFromUrl(
      'https://example.org/catalog.json',
      notifier: notifier,
      vault: vault,
      fetch: (_) async => _catalogWithToken,
    );

    expect(notifier.state.map((a) => a.id), [addon.id]);
    // The token left the file and is in the vault under the (addon, console)
    // pair. This case asserts that URL install goes through the harvest.
    expect(await vault.read(SecretRef.addonToken(addon.id, 'snes')), 'file-secret');
  });

  test('the id comes from Addon.idFromUrl and the name from the host', () async {
    final notifier = await _notifier();

    final addon = await installAddonFromUrl(
      'https://WWW.Example.org/catalog.json?v=2',
      notifier: notifier,
      vault: MemoryVault(),
      fetch: (_) async => _catalogWithToken,
    );

    expect(addon.id, Addon.idFromUrl('https://example.org/catalog.json'));
    expect(addon.name, 'example.org');
    expect(addon.url, 'https://WWW.Example.org/catalog.json?v=2');
  });

  test('reinstalling the same source via another url form does not duplicate', () async {
    final notifier = await _notifier();
    final vault = MemoryVault();

    await installAddonFromUrl('http://www.example.org/catalog.json/',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogWithToken);
    await installAddonFromUrl('https://example.org/catalog.json',
        notifier: notifier, vault: vault, fetch: (_) async => _catalogWithToken);

    expect(notifier.state.length, 1);
  });

  test('a non-JSON body installs nothing', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://example.org/catalog.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => '<html>login</html>'),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('valid JSON with no console installs nothing', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://example.org/catalog.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => _catalogWithoutConsole),
      throwsA(isA<FormatException>()),
    );
    expect(notifier.state, isEmpty);
  });

  test('a network error propagates and installs nothing', () async {
    final notifier = await _notifier();

    await expectLater(
      installAddonFromUrl('https://example.org/catalog.json',
          notifier: notifier, vault: MemoryVault(), fetch: (_) async => throw const HttpException('HTTP 404 fetching catalog')),
      throwsA(isA<HttpException>()),
    );
    expect(notifier.state, isEmpty);
  });
}
```

Note that the `MemoryVault` case does not check the written file. What locks the clean JSON format is `catalog_service_test.dart`, in Task 8, with nine cases just for that; repeating the assertion here would give the same coverage twice and break in two places on the next format change. What this file locks is the glue: that URL installation **goes through** the harvest.

- [ ] **Step 2: Run to see it fail**

```bash
flutter test test/addon_install_test.dart
```

Expected: compile failure, `Error: Couldn't resolve the package 'roms_downloader/services/addon_install.dart'`.

- [ ] **Step 3: Open the catalog parser**

In `lib/services/catalog_service.dart`, in the declaration of `_parseConsoles`, remove the underscore:

```dart
  static Map<String, Console> parseConsoles(String jsonStr) {
```

**The declaration is at line 112, not 79.** 79 was the position against `ef5ee57`, and Task 13 rewrote this file, which is exactly why this Task's **Files** list gives no line number. Verify with the grep below before editing, rather than trusting 112.

And replace the **two** internal calls from `_parseConsoles(` to `parseConsoles(`:

```bash
grep -n "_parseConsoles(" lib/services/catalog_service.dart
```

Measured now: line 61, inside `buildCatalog`, which is the call Task 13 created, and line 203, inside `setCatalogFromJson`. Two, not three: an earlier version of this Step said "the two the grep finds outside the declaration, plus the one Task 13 created", and counted the Task 13 one twice, because it is one of the ones the grep finds.

Made public intentionally, not copied: validating a downloaded catalog with a different parser from the one that will read it later is like the app accepting at install time a file it cannot open at boot. It must be the same code or it means nothing.

```bash
grep -n "_parseConsoles" lib/services/catalog_service.dart
```

Expected: no lines.

- [ ] **Step 4: Write the installer**

Create `lib/services/addon_install.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

/// How the catalog arrives from the network.
///
/// Passed as a parameter because `http` is not a dependency of this project,
/// so `MockClient` does not exist here: without injection, testing this function
/// would require a real server.
typedef CatalogFetcher = Future<String> Function(String url);

/// Downloads the catalog from [url], stores any tokens in it, and installs the
/// source as an addon.
///
/// The order is the unconditional half of spec section 6.3: harvest before
/// validating and before writing. Nothing touches disk until
/// [CatalogService.harvestAuthTokens] has returned the JSON without the tokens.
///
/// When validation fails after harvesting, the secret stays in the vault and the
/// addon is not added to the list. That is intentional: the token came from the
/// file the user themselves sent for installation, and a vault entry under an id
/// that is not in the list is read by nobody.
///
/// Throws [FormatException] if the body is not a catalog with at least one
/// console, and whatever [fetch] throws if the network fails.
Future<Addon> installAddonFromUrl(
  String url, {
  required AddonNotifier notifier,
  required SecretVault vault,
  CatalogFetcher? fetch,
}) async {
  final body = await (fetch ?? fetchCatalogByHttp)(url);
  final id = Addon.idFromUrl(url);

  final cleaned = await CatalogService.harvestAuthTokens(body, vault: vault, addonId: id);
  if (CatalogService.parseConsoles(cleaned).isEmpty) {
    throw const FormatException('No consoles found in the provided catalog.');
  }

  final addon = Addon(id: id, name: _nameOf(url, id), url: url);
  await notifier.install(addon, cleaned);
  return addon;
}

/// The name shown in the addon list: the host, without `www.`.
///
/// Host and not id because the id is a vault key and a file name
/// (`myrient_erista_me_files`), and keys are for machines. A URL without a host,
/// which `Addon.idFromUrl` accepts, falls back to the id, which is ugly but
/// better than empty.
String _nameOf(String url, String id) {
  final host = Uri.tryParse(url.trim())?.host ?? '';
  if (host.isEmpty) return id;
  return host.replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
}

/// The real network, same as `CatalogService.setCatalogFromUrl`
/// (the body of `setCatalogFromUrl`): same 30-second timeout to connect and the
/// same rejection of any status other than 200.
Future<String> fetchCatalogByHttp(String url) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 30);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode} fetching catalog');
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}
```

**Likely pitfall:** passing `body` to `notifier.install` instead of `cleaned`. Both compile, the other five cases pass, and the token goes back to disk, now in a new file at `config/addons/<id>.json`. The case that catches this is the first one, and only because it reads the vault after installing; that is why it exists.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addon_install_test.dart
```

Expected: `+6`, zero failures.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```

Expected: `+546`, zero failures.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`, and none of them in `addon_install.dart`, `addon_install_test.dart`, or `catalog_service.dart`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_install_test.dart
git commit -m "test(addon): instalacao de addon por url"
git add lib/services/addon_install.dart lib/services/catalog_service.dart
git commit -m "feat(addon): instalar addon a partir de uma url"
```

---

### Task 22: the addon detail screen

**Files:**
- Create: `lib/screens/addon_detail_screen.dart`
- Modify: `lib/providers/addon_provider.dart` (gains `mergedCatalogProvider`, and `addonCoverageProvider` starts deriving from it)
- Test: `test/addon_detail_screen_test.dart`
- Test: `test/support/fake_addon_store.dart` (new, shared helper, no `main`; Tasks 23, 24 and 25 reuse it)

Section 9 asks for five blocks on this screen, in this order: identity, account, coverage, priority, and remove. Four of them already have a ready answer in providers: `addonProvider` gives name, URL, and position; `MergedCatalog.coverage()` gives the consoles and which ones need an account (Task 18); and `ConsoleAuthSetting(console:, addonId:)` is the account form (Task 20). This Task just assembles.

**One requirement from section 9 is left out, and it is better to say so now than to find out during review.** The spec asks for "**Coverage**: which consoles it serves **and how many items in each**". The first half goes in; the second does not. Counting items on a console means fetching its listing (`_fetchCatalog`, in `lib/services/catalog_service.dart`; no line number here on purpose, because Task 13 rewrites that file and any number written now would be stale by the time this Task runs. This section has already cited `catalog_service.dart:4016`, which is a line in no file: the file has 651 lines), one request per console, and the app loads listings on demand precisely because they are expensive. An addon with 25 consoles would pay 25 requests just to open a read-only screen. What the screen shows is `"3 consoles"` and the list of them. Per-console counting waits until there is a cheap way to count, and that is declared debt, not an oversight.

The change in `addon_provider.dart` is to keep the screen from reading disk twice. Today `addonCoverageProvider` builds the entire `MergedCatalog` and returns only the coverage, but this screen also needs the `Console` objects themselves, to get the console's display name and to pass to the account form. Rather than a second provider that redoes the same work, the merged catalog becomes the provider and the coverage starts deriving from it.

**Real disk does not work here, and the reason is measured.** The body of a `testWidgets` runs inside a `FakeAsync`: the timers are fake and the real event loop does not advance there. Any response that comes from the file system therefore never arrives, and the `await` hangs forever. Measured in this repository, with four probes:

| inside `testWidgets` | result |
| --- | --- |
| `await Directory.systemTemp.createTemp(...)` | **hangs** |
| `await File('/tmp/does_not_exist').exists()` | **hangs** |
| `await SharedPreferences.getInstance()` and `setString`, with `setMockInitialValues` | passes |
| `await tester.runAsync(() => createTemp(...))` | passes |

It is not `createTemp`: it is any kind of disk IO. Mocked `shared_preferences` passes because it is in memory, which is why `console_auth_setting_test` never ran into this. The service tests that build `AddonStore` in `Directory.systemTemp` (`addon_store_test`, `addon_provider_test`, `catalog_addons_test`, `addon_install_test`) remain correct and do not change: they are ordinary `test()` calls, where the real loop runs, and exercising real disk is exactly what you want from them.

**And `tester.runAsync` does not solve this case.** It would save the store setup, but the "Remove" path calls `AddonNotifier.remove` -> `AddonStore.deleteCatalog` -> `File.exists()` from inside `pumpAndSettle`, triggered by an `onPressed`. There is no point where anything can be wrapped there. That is why the solution is an in-memory store, not a wrapper.

Create `test/support/fake_addon_store.dart` first. It does not end in `_test.dart` on purpose: it is a shared helper, has no `main`, and Tasks 23, 24, and 25 import this same file instead of each one writing its own.

```dart
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

/// A complete in-memory `AddonStore`, for widget tests.
///
/// Exists because disk IO **hangs** inside a `testWidgets` body: the body runs
/// in a `FakeAsync` and the file system response arrives via the real event loop,
/// which does not advance there. What exercises real disk is `addon_store_test`,
/// in ordinary `test()` calls, and that is where it must be proven.
///
/// `noSuchMethod` with `implements` avoids reimplementing `catalogFile`, the
/// only remaining member, and the `throw` is what distinguishes this fake from
/// a permissive mock: if a future case calls something that does not exist here,
/// it dies saying which method it was, instead of passing silently.
class FakeAddonStore implements AddonStore {
  List<Addon> _addons;

  /// What `writeCatalog` stored, per addon. Public so a case can assert the
  /// install wrote the catalog, not only that it touched the list.
  final Map<String, String> catalogs = {};

  FakeAddonStore(List<Addon> addons) : _addons = List.of(addons);

  @override
  List<Addon> load() => List.of(_addons);

  @override
  Future<void> save(List<Addon> list) async {
    _addons = List.of(list);
  }

  @override
  Future<String?> readCatalog(String addonId) async => catalogs[addonId];

  @override
  Future<void> writeCatalog(String addonId, String jsonStr) async {
    catalogs[addonId] = jsonStr;
  }

  @override
  Future<void> deleteCatalog(String addonId) async {
    catalogs.remove(addonId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'FakeAddonStore does not respond to ${invocation.memberName}.',
      );
}
```

- [ ] **Step 1: Write the failing tests**

Create `test/addon_detail_screen_test.dart`. Note that there is **no** `import 'dart:io'` and no `import '.../services/addon_store.dart'`: in both cases the only reason for them was the disk store that left, and an orphan import is `unused_import`, which is a **warning**, not an `info`. Leaving both would push Step 7 from 22 to 24.

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

import 'support/fake_addon_store.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://other/ps2/']);

/// Two addons serving three consoles: `myrient` serves Switch (with account)
/// and SNES, `other` serves PS2. The `myrient` screen must not show PS2.
MergedCatalog _catalog() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'other', url: 'https://other/ps2/')],
      },
    );

/// A real `AddonNotifier` over an in-memory store: the Remove case needs the
/// removal to pass through `AddonNotifier.remove`. Only disk is fake, because
/// disk IO hangs inside `testWidgets`.
///
/// No `addTearDown(notifier.dispose)`: the `StateNotifierProvider` disposes it
/// when the tree falls, and a second dispose kills every case. `app_settings`
/// seeded with `{}` so settings load does not fall into the plugin directory
/// branch.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final notifier = AddonNotifier(Future.value(FakeAddonStore(addons)), invalidateCache: () async {});
  await notifier.ready;
  return notifier;
}

/// Pushes the screen over an empty home. Pushed, not as `home`, because
/// `Navigator.pop` on the root route is a no-op: the Remove case would pass
/// without proving the screen closes.
Future<void> _open(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalog,
  String addonId = 'myrient',
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalog ?? _catalog()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addonId)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the name and source url', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient.erista.me/catalog.json')]);

    await _open(tester, notifier: notifier);

    expect(find.text('myrient.erista.me'), findsWidgets);
    expect(find.text('https://myrient.erista.me/catalog.json'), findsOneWidget);
  });

  testWidgets('addon without url shows the source in words', (tester) async {
    // The built-in and file-opened catalogs have no address; an empty url field
    // would make a normal case look broken.
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Built-in catalog')]);

    await _open(tester, notifier: notifier, addonId: kBuiltinAddonId);

    expect(find.text('Built-in catalog'), findsWidgets);
    expect(find.text('Installed with the app'), findsOneWidget);
  });

  testWidgets('coverage lists only this addon\'s consoles', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('Switch'), findsWidgets);
    expect(find.text('SNES'), findsOneWidget);
    expect(find.text('PS2'), findsNothing);
  });

  testWidgets('addon covering nothing yet shows zero and does not crash', (tester) async {
    // `coverage()` omits an addon with no console, so this is the missing-key
    // path, not the empty-list one: the state of a freshly installed addon
    // whose catalog is not read yet.
    final notifier = await _notifier(const [Addon(id: 'incoming', name: 'incoming.org', url: 'https://incoming.org/c.json')]);

    await _open(tester, notifier: notifier, addonId: 'incoming');

    expect(find.text('No console'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('only the console that needs an account gets a form', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);

    final forms = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(forms.length, 1);
    expect(forms.single.console.id, 'switch');
    // The `addonId` is what makes the token be stored under the right pair.
    // Passing the builtin here compiles, the screen works, and the Myrient token
    // goes into the builtin catalog's drawer.
    expect(forms.single.addonId, 'myrient');
  });

  testWidgets('priority shows the position in the list', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: kBuiltinAddonId, name: 'Built-in catalog'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    expect(find.text('2 of 3'), findsOneWidget);
  });

  testWidgets('cancelling removal does not remove', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(notifier.state.length, 1);
    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('confirming removes and closes the screen', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    // The dialog button label differs from the screen's on purpose: with both
    // reading "Remove", this tap would match two widgets and die ambiguous.
    await tester.tap(find.text('Remove addon'));
    await tester.pumpAndSettle();

    expect(notifier.state, isEmpty);
    expect(find.byType(AddonDetailScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addon_detail_screen_test.dart
```

Expected: compile failure, `Error: Couldn't resolve the package 'roms_downloader/screens/addon_detail_screen.dart'`.

- [ ] **Step 3: The merged catalog becomes a provider**

In `lib/providers/addon_provider.dart`, replace the entire `addonCoverageProvider` (the one Task 18 created) with two providers:

```dart
/// The merged catalog of all installed addons, in their order.
///
/// **No test, and intentionally so.** `mergedCatalog()` reaches disk via
/// `path_provider`, which in a platformless test does not fail: it silently
/// returns empty. A test here would assert an empty catalog and pass forever,
/// including after the rule breaks. What has tests is `mergeCatalogs` and
/// `MergedCatalog.coverage()`, which is where the rule lives. The Task 22,
/// 23, and 25 screens override this provider.
final mergedCatalogProvider = FutureProvider<MergedCatalog>((ref) async {
  ref.watch(addonProvider);
  return CatalogService().mergedCatalog();
});

/// From each addon to what it covers.
///
/// Derives from the merged catalog instead of rebuilding it: the detail screen
/// needs both, and two disk reads for the same answer is the kind of cost
/// nobody notices until the addon list gets large.
final addonCoverageProvider = FutureProvider<Map<String, AddonCoverage>>((ref) async {
  return (await ref.watch(mergedCatalogProvider.future)).coverage();
});
```

- [ ] **Step 4: Write the screen**

Create `lib/screens/addon_detail_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

/// The five blocks that UI spec section 9 asks for an addon:
/// identity, account, coverage, priority, and remove.
///
/// Coverage shows which consoles the addon serves, **not** how many items in
/// each. Per-console counting is one listing request per console
/// (`CatalogService._fetchCatalog`), and the app loads listings on demand
/// precisely because they are expensive: an addon with 25 consoles would pay
/// 25 requests just to open a read-only screen.
class AddonDetailScreen extends ConsumerWidget {
  final String addonId;

  const AddonDetailScreen({super.key, required this.addonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final index = addons.indexWhere((a) => a.id == addonId);

    // Removal changes the list before the `pop` completes, so this frame really
    // exists. Without the guard, `addons[index]` below blows up with index -1
    // on the happy path of the Remove button.
    if (index < 0) return const Scaffold(body: SizedBox.shrink());

    final addon = addons[index];
    final catalog = ref.watch(mergedCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: Text(addon.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Source',
            child: Text(addon.url ?? (addon.isBuiltin ? 'Installed with the app' : 'Installed from file')),
          ),
          catalog.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (e, _) => _Section(title: 'Coverage', child: Text('Unreadable catalog: $e')),
            data: (merged) {
              final coverage = merged.coverage()[addonId] ?? (consoles: const <String>[], authConsoles: const <String>[]);
              // A declaration, not `final name = (String id) => ...`:
              // `prefer_function_declarations_over_variables` is on and the
              // variable form would trip the lint.
              String name(String id) => merged.consoles[id]?.name ?? id;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (coverage.authConsoles.isNotEmpty) const VaultWarning(),
                  for (final consoleId in coverage.authConsoles)
                    if (merged.consoles[consoleId] != null)
                      _Section(
                        title: 'Account: ${name(consoleId)}',
                        child: ConsoleAuthSetting(console: merged.consoles[consoleId]!, addonId: addonId),
                      ),
                  _Section(
                    title: 'Coverage',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(coverage.consoles.isEmpty
                            ? 'No console'
                            : '${coverage.consoles.length} console${coverage.consoles.length == 1 ? '' : 's'}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final id in coverage.consoles) Chip(label: Text(name(id)))],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          _Section(
            title: 'Priority',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${index + 1} of ${addons.length}'),
                const SizedBox(height: 4),
                Text(
                  'Drag in the addons list to change the order. The first source that has the file is the one that downloads.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmRemoval(context, ref, addon),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoval(BuildContext context, WidgetRef ref, Addon addon) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${addon.name}?'),
        // The token stays in the vault on purpose (`AddonNotifier.remove`);
        // saying so here stops the user from thinking they must rediscover the
        // credential to reinstall.
        content: const Text('The catalog leaves the app. The credential stays saved, and reinstalling the same source finds it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove addon')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(addonProvider.notifier).remove(addon.id);
    navigator.pop();
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
```

**Likely pitfall:** storing `Navigator.of(context)` **after** the `await`. The `use_build_context_synchronously` from `flutter_lints` is `info`, so it does not break the build, but it pushes analyze to 23 and the Task fails at Step 7 for a reason that looks cosmetic. The line `final navigator = Navigator.of(context);` before the dialog is what prevents this.

**Second pitfall:** building the account block from `coverage.consoles` filtered by `Console.hasTokenAuth`. This works in most cases and fails exactly in the case that Group 3 fixed: with two addons serving the same console, `Console.auth` belongs to the **first** one that declared it, so the second addon's screen would show the first one's form. `authConsoles` comes from `coverage()`, which iterates sources, and that is why it exists.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addon_detail_screen_test.dart
```

Expected: `+8`, zero failures.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```

Expected: `+554`, zero failures.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`, and none of them in `addon_detail_screen.dart`, `addon_detail_screen_test.dart`, or `addon_provider.dart`.

- [ ] **Step 8: Commit**

```bash
git add test/addon_detail_screen_test.dart test/support/fake_addon_store.dart
git commit -m "test(addon): tela de detalhe do addon"
git add lib/screens/addon_detail_screen.dart lib/providers/addon_provider.dart
git commit -m "feat(addon): tela de detalhe com origem, conta, cobertura e prioridade"
```

---

### Task 23: the addon list, with drag-to-reorder and URL installation

**Files:**
- Create: `lib/screens/addons_screen.dart`
- Modify: `lib/providers/addon_provider.dart` (gains `catalogFetcherProvider`)
- Test: `test/addons_screen_test.dart`

The line that section 9 asks for: "icon, name, short coverage summary ("25 consoles"), "account" chip when it requires credentials, drag handle, and arrow. At the end, "+ Install from URL"". This Task is the last UI piece of the slice, and is where priority stops being a concept and becomes a handle the user drags.

The drag is the point. `sourcePriorityProvider` (Task 14) is already the order of this list, and `planFromEntries` (slice 3) already uses `sourcePriority` as the last tiebreaker from section 6. None of that is observable today because the order never changes. After this Task, dragging a row changes which source downloads the file.

`catalogFetcherProvider` exists for one test reason and one production reason. For testing: `installAddonFromUrl` is only injectable as a parameter, and a widget has no way to receive a parameter from inside an `onPressed`. For production: it is the only place where the screen touches the network, so it is the only place that needs to change if there is ever a proxy or a custom header.

- [ ] **Step 1: Write the failing tests**

Create `test/addons_screen_test.dart`. `FakeAddonStore` is the one from Task 22 (`test/support/fake_addon_store.dart`), already committed; only an import is needed here. The import is relative and not `package:`, which is the convention of the files that already use `test/support/`. And there is no `import 'dart:io'` and no `import '.../services/addon_store.dart'`: the only reason for both was the disk store, and an orphan import is `unused_import`, which is a **warning** and would push Step 7 from 22 to 24.

**Two imports from this list are not obvious, and without them the block does not compile.** The first version of this block did not have them, and `flutter test` stopped before running any case, with `Type 'CatalogFetcher' not found` and `Undefined name 'kLongPressTimeout'`:

- `package:roms_downloader/services/addon_install.dart` is where `typedef CatalogFetcher` lives (`addon_install.dart:14`), used in the `CatalogFetcher? fetch` parameter of `_open`. There is no `export` anywhere in `lib/` (measured: `grep -rn '^export ' lib/` finds nothing), so the typedef is only visible to whoever imports its file. This import was cut out along with `addon_store.dart`, and the cut removed one too many.
- `package:flutter/gestures.dart` is where `kLongPressTimeout` lives (`gestures/constants.dart:29`), used in the drag test. `material.dart` does **not** re-export `gestures.dart`, and neither do `widgets.dart` or `flutter_test.dart` (measured in all three). It is the first file in the repo to import `gestures.dart`, so there is no precedent to copy from.

Neither becomes `unused_import`: both symbols are used in the block itself, and the target of 22 for Step 7 does not change.

**The `moveBy(Offset(0, 300))` in the drag case is measured, not chosen by eye.** The first version of this block moved 100 px and the case failed with no error at all, just the list in the original order, which is the most expensive defect to diagnose here: it looks like a production bug and it is a short gesture. Measured on this screen, with rows of 74 and 72 px: 100, 120, and 137 px swap nothing, 150 px swaps. The value was left generous on purpose, and with two rows going past the end is the same as swapping. Whoever shortens this will not see an error, they will see the order assertion.

```dart
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/screens/addons_screen.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';

import 'support/fake_addon_store.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);
const _ps2 = Console(id: 'ps2', name: 'PS2', urls: ['https://other/ps2/']);

const _catalogFetched = '''
[{"name": "PS2", "urls": ["https://incoming.org/ps2/"]}]
''';

/// `myrient` covers two consoles and one of them requires an account; `other` covers one and
/// none require an account.
MergedCatalog _catalog() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes, 'ps2': _ps2},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true})],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
        'ps2': [ConsoleSource(addonId: 'other', url: 'https://other/ps2/')],
      },
    );

/// Top-level function, not a literal in the `??`, because `fetch ?? (_) async => ...` does
/// not parse as it reads.
Future<String> _fetchDefault(String url) async => _catalogFetched;

/// A real notifier over an in-memory store: drag and install must pass through
/// `reorder` and `install`. Only disk is fake, since it hangs inside
/// `testWidgets`. No `addTearDown(notifier.dispose)`: the provider disposes it
/// when the tree falls, and a second dispose kills every case.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final notifier = AddonNotifier(Future.value(FakeAddonStore(addons)), invalidateCache: () async {});
  await notifier.ready;
  return notifier;
}

Future<void> _open(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalog,
  CatalogFetcher? fetch,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalog ?? _catalog()),
      catalogFetcherProvider.overrideWithValue(fetch ?? _fetchDefault),
      vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(home: AddonsScreen()),
  ));
  await tester.pumpAndSettle();
}

/// Fills the install dialog field and confirms.
Future<void> _install(WidgetTester tester, String url) async {
  await tester.tap(find.text('Install from URL'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), url);
  await tester.tap(find.text('Install'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists addons in priority order', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    final names = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(names.indexOf('myrient.erista.me'), lessThan(names.indexOf('other.org')));
  });

  testWidgets('each row summarizes coverage', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    expect(find.text('2 consoles'), findsOneWidget);
    expect(find.text('1 console'), findsOneWidget);
  });

  testWidgets('the account chip only shows on addons needing a credential', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    expect(find.text('account'), findsOneWidget);
  });

  testWidgets('addon with no coverage stays in the list', (tester) async {
    // `coverage()` omits an addon with no console; omitting it on screen would
    // be worse than showing zero: the user just installed a source and, not
    // seeing it, installs again.
    final notifier = await _notifier(const [Addon(id: 'incoming', name: 'incoming.org', url: 'https://incoming.org/c.json')]);

    await _open(tester, notifier: notifier);

    expect(find.text('incoming.org'), findsOneWidget);
    expect(find.text('No console'), findsOneWidget);
  });

  testWidgets('empty list invites installing', (tester) async {
    final notifier = await _notifier(const []);

    await _open(tester, notifier: notifier);

    expect(find.text('No addons installed.'), findsOneWidget);
    expect(find.text('Install from URL'), findsOneWidget);
  });

  testWidgets('tapping a row opens the detail', (tester) async {
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    expect(find.byType(AddonDetailScreen), findsOneWidget);
  });

  testWidgets('dragging reorders and the new order persists', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other.org/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    // On the handle, not the row: the whole row is a `ListTile` with `onTap`
    // that opens the detail, and dragging the row would open the screen instead
    // of reordering.
    //
    // Manual gesture, not `tester.drag`: `ReorderableDragStartListener` uses
    // `ImmediateMultiDragGestureRecognizer`, which needs the `moveBy` in its own
    // frame for the reorder to start. With `drag` the test passes or fails
    // depending on the row height, which is the worst kind of test.
    //
    // The distance is generous on purpose. Measured on this screen: 100, 120 and
    // 137 px swap nothing, 150 px swaps, because `ReorderableListView` only
    // rearranges when the dragged item goes past the full neighbor, and the two
    // rows are 74 and 72 px. A short gesture fails with no error: the list stays
    // intact and the assertion blames the original order, without saying the
    // gesture was too short. With two rows, going past the end is the same as
    // swapping, so the generous distance costs no precision.
    final handle = find.byIcon(Icons.drag_handle).first;
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout);
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(notifier.state.map((a) => a.id), ['other', 'myrient']);
  });

  testWidgets('installing from URL appends the addon', (tester) async {
    final notifier = await _notifier(const []);

    await _open(tester, notifier: notifier);
    await _install(tester, 'https://incoming.org/catalog.json');

    expect(notifier.state.map((a) => a.id), [Addon.idFromUrl('https://incoming.org/catalog.json')]);
  });

  testWidgets('a url returning no catalog shows the error and does not install', (tester) async {
    final notifier = await _notifier(const []);

    await _open(tester, notifier: notifier, fetch: (_) async => '<html>login</html>');
    await _install(tester, 'https://incoming.org/catalog.json');

    expect(notifier.state, isEmpty);
    expect(find.textContaining('Could not install'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/addons_screen_test.dart
```

Expected: compile failure, `Error: Couldn't resolve the package 'roms_downloader/screens/addons_screen.dart'`.

- [ ] **Step 3: The network becomes a provider**

In `lib/providers/addon_provider.dart`, add, after `mergedCatalogProvider`:

```dart
/// How the addon screen downloads a catalog.
///
/// Exists because `installAddonFromUrl` is only injectable as a parameter and
/// an `onPressed` does not receive a parameter. In production it is always
/// `fetchCatalogByHttp`; in tests, a function that returns a string.
final catalogFetcherProvider = Provider<CatalogFetcher>((ref) => fetchCatalogByHttp);
```

with the new import:

```dart
import 'package:roms_downloader/services/addon_install.dart';
```

- [ ] **Step 4: Write the screen**

Create `lib/screens/addons_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/console_merge.dart';

/// The ordered list of sources. The order is the priority: it feeds
/// `sourcePriorityProvider`, so dragging a row here changes which source
/// downloads the file.
class AddonsScreen extends ConsumerWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final coverage = ref.watch(addonCoverageProvider).valueOrNull ?? const <String, AddonCoverage>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Addons')),
      body: Column(
        children: [
          Expanded(
            child: addons.isEmpty
                ? const Center(child: Text('No addons installed.'))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: addons.length,
                    onReorder: (from, to) => ref.read(addonProvider.notifier).reorder(from, to),
                    itemBuilder: (context, i) {
                      final addon = addons[i];
                      return _Row(
                        key: ValueKey(addon.id),
                        index: i,
                        addon: addon,
                        // Absent means zero coverage, not error: the state of a
                        // freshly installed addon whose catalog is not read yet.
                        coverage: coverage[addon.id] ?? (consoles: const <String>[], authConsoles: const <String>[]),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _installDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Install from URL'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _installDialog(BuildContext context, WidgetRef ref) async {
    final url = await showDialog<String>(context: context, builder: (_) => const _UrlDialog());
    if (url == null || url.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final vault = (await ref.read(vaultProvider.future)).vault;
      await installAddonFromUrl(
        url,
        notifier: ref.read(addonProvider.notifier),
        vault: vault,
        fetch: ref.read(catalogFetcherProvider),
      );
    } catch (e) {
      // A message instead of a stack trace: the two likely errors are a wrong
      // URL and a server that returns a login page, neither of which is a bug.
      messenger.showSnackBar(SnackBar(content: Text('Could not install: $e')));
    }
  }
}

/// The "Install from URL" dialog. Stateful only for the sake of `dispose`: the
/// controller must outlive the `TextField`, and disposing it inline would kill
/// it mid-transition. With it in `State`, the framework disposes it after the
/// route is actually gone.
class _UrlDialog extends StatefulWidget {
  const _UrlDialog();

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install from URL'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Catalog address', hintText: 'https://example.org/catalog.json'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Install')),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final int index;
  final Addon addon;
  final AddonCoverage coverage;

  const _Row({super.key, required this.index, required this.addon, required this.coverage});

  @override
  Widget build(BuildContext context) {
    final n = coverage.consoles.length;
    return ListTile(
      leading: const Icon(Icons.extension_outlined),
      title: Text(addon.name),
      subtitle: Row(
        children: [
          Text(n == 0 ? 'No console' : '$n console${n == 1 ? '' : 's'}'),
          if (coverage.authConsoles.isNotEmpty) ...[
            const SizedBox(width: 8),
            const Chip(
              label: Text('account'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The handle is the only drag point, which is why
          // `buildDefaultDragHandles` is false above: with it on, the whole row
          // drags and the tap that opens the detail becomes a one-pixel drag.
          ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addon.id)),
      ),
    );
  }
}
```

**Likely pitfall:** leaving `buildDefaultDragHandles` at its default of `true`. The screen still works and the tap test passes, because on desktop `ReorderableListView` only adds its own handle on mobile. What breaks is on mobile, where the whole row becomes draggable and the tap that opens the detail competes with the drag. The pair `buildDefaultDragHandles: false` plus `ReorderableDragStartListener` is what gives both behaviors on every platform.

**Second pitfall:** `ValueKey(i)` instead of `ValueKey(addon.id)`. `ReorderableListView` requires a key and the index satisfies that requirement, so nothing complains. But the key then changes exactly when the list reorders, which is when it needed to be stable, and the animation swaps the contents of the wrong rows.

**Third pitfall, and this one already happened:** building the `TextEditingController` inside `_installDialog` and disposing it on the line right after `await showDialog(...)`. That is what the first version of this block did, and both dialog cases in Step 5 failed with

```
A TextEditingController was used after being disposed.
  The relevant error-causing widget was:
    TextField TextField:.../lib/screens/addons_screen.dart:70:18
```

`showDialog` returns when the route is popped, and the exit animation still runs after that: on the next frame the transition re-subscribes to the `TextField`, which is still in the tree, and finds a dead controller. The assertion cascade prevents the installation from completing, so the `SnackBar` in the error case also never appears and **both** cases fail for the same cause. That is why the dialog is a `_UrlDialog extends StatefulWidget` with the controller in the `State`: the framework then decides when to `dispose`, after the route has actually left.

- [ ] **Step 5: Run to see it pass**

```bash
flutter test test/addons_screen_test.dart
```

Expected: `+9`, zero failures. The file is new and has nine `testWidgets`, so the standalone count and what the Task adds to the suite are the same. This number was once written as `+11`, and that was wrong: counting the cases in the Step 1 block gives nine. The running total chain in Step 6 was always correct: `554 + 9 = 563`.

**The sentence above once cited `551 + 9 = 560`**, which was the chain from before Tasks 8b, 11b, and 12b. It no longer matches any baseline: the total after Task 22 is 554, not 551, and this Task's total is 563, not 560. The `+9` and `+563` in Steps 5 and 6 are the measured numbers; only the explanatory arithmetic was stale.

- [ ] **Step 6: Run the full suite**

```bash
flutter test
```

Expected: `+563`, zero failures.

- [ ] **Step 7: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`, and none of them in `addons_screen.dart`, `addons_screen_test.dart`, or `addon_provider.dart`.

- [ ] **Step 8: Commit**

```bash
git add test/addons_screen_test.dart
git commit -m "test(addon): lista de addons com arrasto e instalacao por url"
git add lib/screens/addons_screen.dart lib/providers/addon_provider.dart
git commit -m "feat(addon): lista de addons com prioridade arrastavel"
```

---

### Task 24: the entry points for the screen, and the warning that the vault does not encrypt

**Files:**
- Create: `lib/widgets/settings/vault_warning.dart`
- Modify: `lib/screens/addon_detail_screen.dart` (the warning goes above the account block)
- Modify: `lib/widgets/settings/accounts_setting.dart` (the warning goes at the top)
- Modify: `lib/screens/menu_screen.dart` (the Tools tiles become a top-level function and gain "Addons")
- Test: `test/vault_warning_test.dart` (new, 5 cases)
- Test: `test/menu_grid_test.dart` (existing, +1 case)

`test/support/fake_addon_store.dart` does **not** go here: it was created and committed in Task 22, and this Task only imports it.

Two small things that close Group 5: the addon screen is still unreachable by anyone, and the locked vault decision has not appeared in any pixel yet.

**The warning is the second half of the locked decision, and it is what keeps the slice from being window-dressing.** Section 6.3 has two goals and only one is unconditional. Removing the token from the shareable JSON closes on every platform, because that is the file the user sends to someone else, and what closes it is `harvestAuthTokens` (Task 8). Encrypting the secret **at rest** is best-effort: on a server Linux, without `gnome-keyring` or KWallet on D-Bus, `flutter_secure_storage` does not open and `chooseVault` falls back to `PrefsVault`, which is plain text. On that machine the secret stays where it always was. The user must know this on the screen where they type the secret, not in a CHANGELOG.

`AsyncLoading` does not warn on purpose. While the keyring probe has not returned, the app does not know whether it encrypts, and a warning that flashes on every boot of a machine that **does** have a keyring is a warning the user learns to ignore. `AsyncError` warns: a keyring that did not open is exactly the case the warning exists to report.

- [ ] **Step 1: Write the failing tests**

Create `test/vault_warning_test.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

import 'support/fake_addon_store.dart';

const _warning = 'Credentials are stored in plain text on this device.';

/// Seeds the prefs before mounting anything that reads `settingsProvider`.
///
/// Top-level function and not two lines inside `_host` because the last case
/// does not use `_host` and needs this anyway: it mounts `AddonDetailScreen`,
/// which mounts `ConsoleAuthSetting`, which reads `settingsProvider` in
/// `_loadToken` of `console_auth_setting.dart`. No line number on purpose:
/// Task 25 inserted the `onSaved` field above it and the `48` that was written
/// here became `58` in a commit that did not touch this file. Without seeding,
/// that case only passes because the four before it ran first and left the mock
/// in place, and breaks when someone runs it alone with `--plain-name`.
void _seedPrefs() {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
}

Widget _host(Override vault, {Widget child = const VaultWarning()}) {
  _seedPrefs();
  return ProviderScope(
    overrides: [vault],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Override _vault({required bool encrypted}) =>
    vaultProvider.overrideWith((ref) async => VaultChoice(MemoryVault(), encryptedAtRest: encrypted));

void main() {
  testWidgets('non-encrypting vault warns', (tester) async {
    await tester.pumpWidget(_host(_vault(encrypted: false)));
    await tester.pumpAndSettle();

    expect(find.text(_warning), findsOneWidget);
  });

  testWidgets('encrypting vault warns nothing and takes no space', (tester) async {
    await tester.pumpWidget(_host(_vault(encrypted: true)));
    await tester.pumpAndSettle();

    expect(find.text(_warning), findsNothing);
    expect(tester.getSize(find.byType(VaultWarning)), Size.zero);
  });

  testWidgets('does not warn while the keyring is being probed', (tester) async {
    final pending = Completer<VaultChoice>();
    // Complete in teardown so the pending Completer does not leak a future.
    addTearDown(() => pending.complete(VaultChoice(MemoryVault(), encryptedAtRest: true)));

    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) => pending.future)));
    await tester.pump();

    expect(find.text(_warning), findsNothing);
  });

  testWidgets('no vault opened warns harder', (tester) async {
    // The `error` branch needs the fallback itself to throw; a missing keyring
    // is swallowed and arrives as `data` with `encryptedAtRest: false`.
    await tester.pumpWidget(_host(vaultProvider.overrideWith((ref) async => throw StateError('not even the fallback opened'))));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not open any vault'), findsOneWidget);
  });

  testWidgets('the addon detail warns next to the account form', (tester) async {
    _seedPrefs();
    const console = Console(id: 'switch', name: 'Switch', urls: ['https://m/switch/'], auth: {'requires_token': true});
    const merged = MergedCatalog(
      consoles: {'switch': console},
      sources: {
        'switch': [ConsoleSource(addonId: 'myrient', url: 'https://m/switch/', auth: {'requires_token': true})],
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        _vault(encrypted: false),
        addonProvider.overrideWith((ref) => AddonNotifier(
              Future.value(FakeAddonStore(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://m/c.json')])),
              invalidateCache: () async {},
            )),
        mergedCatalogProvider.overrideWith((ref) async => merged),
      ],
      child: const MaterialApp(home: AddonDetailScreen(addonId: 'myrient')),
    ));
    await tester.pumpAndSettle();

    expect(find.text(_warning), findsOneWidget);
  });
}
```

Note the line `import 'support/fake_addon_store.dart';` in the Step 1 block, separated from the others by a blank line. It is relative and not `package:`, which is the convention the seven test files that already use `test/support/` follow (`crc_confirm_service_test.dart:8`, `pack_matcher_test.dart:5`, and the others). An earlier version of this Step **did not include that line**, and the block uses `FakeAddonStore` in the fifth case: without it, Step 2 fails with `Undefined name 'FakeAddonStore'` instead of failing for the `vault_warning.dart` that does not yet exist, and Step 6 does not compile at all. It is a compile error, not a lint.

The file itself is not written here: it has been in the repository since Task 22, which created it because real disk IO hangs inside a `testWidgets` body. This Step only calls `load()` on it.

**The fourth case was once written against the wrong widget, on two levels.** The assertion looked for `'Could not open the keyring'` and the Step 3 widget emits `'Could not open any vault, neither the system one nor the fallback: $e'`. One is not a substring of the other, so the case fell with `Found 0 widgets`, and only **that one**: the other four passed, which makes the defect look like a production bug. The widget is right, and its own doc comment, three blocks below, argues why: "blaming the keyring here would send the user looking for the problem in the wrong place".

The second level is worse than the string, and is why the case name changed too: it was called "keyring that did not open warns" and **that is not what it mounts**. A keyring that does not open produces no `error`, it produces `data` with `encryptedAtRest: false`, which is the first case in the file. The fourth case is the one where the fallback throws, and the `StateError('sem D-Bus')` it used to throw described exactly the situation that does not pass through there. Fixing only the string would leave a test whose name contradicts the doc comment of the widget it tests, and someday someone would believe the name.

**The `_seedPrefs()` in the fifth case is not redundancy.** The first four cases seed through `_host`, and the fifth builds its own `ProviderScope` without going through it. Since `setMockInitialValues` installs a **global** mock that survives from one case to the next, the fifth would pass for free in file order and fail alone with `--plain-name`, which is the worst kind of green test. It needs this because `AddonDetailScreen` mounts `ConsoleAuthSetting`, which reads `settingsProvider` in `_loadToken`. Step 6 gained an extra check because of this.

The doc comment for `_seedPrefs` used to cite `console_auth_setting.dart:48` and the citation was **correct** when it was written. Task 25, three Tasks later, inserted the `onSaved` field above that line and it became `58` without anyone touching `test/vault_warning_test.dart`. Measured, not predicted: `grep -n readAddonToken` after `c61cf99`. The fix replaces the number with the method name, which is unique in the file and does not move, and the block above already reflects that. It is a rule for the rest of the plan: **when the citation points to a file that another Task in the same slice will edit above the cited point, cite the symbol.** A line number only holds when the target is stable.

And add a case to `test/menu_grid_test.dart`, inside the existing `main`:

```dart
  testWidgets('the Tools tiles open the Addons screen', (tester) async {
    final opened = <Type>[];
    final tiles = toolsTiles((screen) => opened.add(screen.runtimeType));

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MenuGrid(tiles: tiles))));
    await tester.tap(find.text('Addons'));
    await tester.pump();

    expect(opened, [AddonsScreen]);
  });
```

with the new imports at the top of the file:

```dart
import 'package:roms_downloader/screens/addons_screen.dart';
import 'package:roms_downloader/screens/menu_screen.dart';
```

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/vault_warning_test.dart test/menu_grid_test.dart
```

Expected: compile failure in both, `Couldn't resolve the package 'roms_downloader/widgets/settings/vault_warning.dart'` and `Undefined name 'toolsTiles'`.

- [ ] **Step 3: Write the warning**

Create `lib/widgets/settings/vault_warning.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/vault_provider.dart';

/// Warns, where the secret is typed, that this machine has no keyring.
///
/// It is the second half of architecture spec section 6.3, and the half that
/// is **not** unconditional. Removing the token from the shareable JSON closes
/// on every platform (`CatalogService.harvestAuthTokens`); encrypting at rest
/// depends on `gnome-keyring` or KWallet being on D-Bus, and on a server Linux
/// there is none. On that machine the secret stays in plain text, and whoever
/// types it must know that at the time they type it.
///
/// Loading does not warn: while the probe has not returned, the app does not
/// know whether it encrypts, and a warning that flashes on every boot of a
/// machine that has a keyring is a warning the user learns to ignore. Error
/// warns, and warns worse than the normal case, because then there is no vault
/// at all.
///
/// **The error branch is not the keyring failing.** A keyring that does not
/// open is the expected path: the probe swallows the exception, returns `false`
/// and the choice falls to the fallback, which arrives here as `data` with
/// `encryptedAtRest: false`. The only way for `error` to happen is for the
/// **fallback** to throw, i.e., `PrefsVault.open()` (`vault_provider.dart:33`,
/// outside any `try`). That is why the message speaks of vault and not keyring:
/// blaming the keyring here would send the user looking for the problem in the
/// wrong place.
class VaultWarning extends ConsumerWidget {
  const VaultWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(vaultProvider).when(
          loading: () => null,
          error: (e, _) => 'Could not open any vault, neither the system one nor the fallback: $e',
          data: (choice) => choice.encryptedAtRest ? null : 'Credentials are stored in plain text on this device.',
        );
    if (text == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_open, size: 20, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: colors.onErrorContainer)),
                const SizedBox(height: 4),
                Text(
                  'Without gnome-keyring or KWallet, the app stores the secret as before. The catalog you share stays free of tokens.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
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

The second line of the warning is not decoration: without it, the user reads "plain text" and concludes that the file they send to a friend has their token inside. It is exactly the opposite, and that is the half that was closed.

- [ ] **Step 4: Place the warning in both screens**

In `lib/screens/addon_detail_screen.dart`, inside the `data:` of `catalog.when`, replace the `for` in the account block with a block that starts with the warning:

```dart
                  if (coverage.authConsoles.isNotEmpty) const VaultWarning(),
                  for (final consoleId in coverage.authConsoles)
                    if (merged.consoles[consoleId] != null)
```

The `if` in front prevents an addon that requires no account from gaining a warning about a secret it does not store.

And the import:

```dart
import 'package:roms_downloader/widgets/settings/vault_warning.dart';
```

In `lib/widgets/settings/accounts_setting.dart`, replace the `return ExpansionTile(` with a column with the warning at the top:

```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VaultWarning(),
        ExpansionTile(
```

closing the column after the `children: const [IaCredentialsSetting()],` of the `ExpansionTile`:

```dart
          children: const [IaCredentialsSetting()],
        ),
      ],
    );
```

with the same import.

- [ ] **Step 5: The entry point for the screen**

In `lib/screens/menu_screen.dart`, move the Tools tile list out of `build` and make it a top-level function, above the class:

```dart
/// The Tools tiles, outside `build` so they can have a test.
///
/// [push] comes in as a parameter because navigation from inside `MenuScreen`
/// depends on its `context`, and a test that needed that context would have
/// to mount the whole screen, with the task queue and everything.
List<MenuTile> toolsTiles(void Function(Widget screen) push) => [
      MenuTile(label: 'Addons', icon: Icons.extension, accentColor: const Color(0xFF2E7D5B), onTap: () => push(const AddonsScreen())),
      MenuTile(label: 'NSZ Decompress', icon: Icons.unarchive, accentColor: const Color(0xFFE56717), onTap: () => push(const NszDecompressScreen())),
      MenuTile(label: 'Steam Shortcuts', icon: Icons.videogame_asset, accentColor: const Color(0xFF3B6FB5), onTap: () => push(SteamShortcutScreen())),
      MenuTile(label: 'New Catalog Source', icon: Icons.playlist_add, accentColor: const Color(0xFF2E7D5B), onTap: () => push(const AddCatalogSourceScreen())),
      MenuTile(label: 'Collection Clean', icon: Icons.cleaning_services, accentColor: const Color(0xFF9C4DA0), onTap: () => push(const CollectionCleanScreen())),
      MenuTile(label: 'Rar Decompress', icon: Icons.folder_zip, accentColor: const Color(0xFFB4632E), onTap: () => push(const RarDecompressScreen())),
      MenuTile(label: 'M3U Playlists', icon: Icons.playlist_play, accentColor: const Color(0xFF3B6FB5), onTap: () => push(const M3uScreen())),
      MenuTile(label: 'CHD Converter', icon: Icons.compress, accentColor: const Color(0xFF167C80), onTap: () => push(const ChdConvertScreen())),
      MenuTile(label: '3DS → CIA', icon: Icons.sd_card, accentColor: const Color(0xFF9C4DA0), onTap: () => push(const CiaConvertScreen())),
    ];
```

and in `build`, the Tools tile becomes:

```dart
      MenuTile(
        label: 'Tools',
        icon: Icons.build,
        accentColor: const Color(0xFFE56717),
        onTap: () => _push(MenuGridScreen(title: 'Tools', tiles: toolsTiles(_push))),
      ),
```

with the new import:

```dart
import 'package:roms_downloader/screens/addons_screen.dart';
```

"Addons" is first in the list, and not at the end next to "New Catalog Source", because section 9 opens by saying "installing an addon is the first thing the user does". The two entry points coexist, and the spec already accepted that cost: the tool mounts a console by hand, and "+ Install from URL" installs a ready-made catalog.

`_push` has signature `void Function(Widget)`, which is exactly what `toolsTiles` expects, so there is no adapter in between.

- [ ] **Step 6: Run to see it pass**

```bash
flutter test test/vault_warning_test.dart test/menu_grid_test.dart
```

Expected: `+7`, zero failures, with 5 from the new file and 2 from `menu_grid_test`, which already had one.

And run the fifth case **alone**, which is the check that `_seedPrefs()` exists to pass:

```bash
flutter test test/vault_warning_test.dart --plain-name "the addon detail warns next to the account form"
```

Expected: `+1`, zero failures. If this command fails while the one above passes, the case is living off the mock another case left behind, and the fix is where `_seedPrefs()` is called, not in the case.

- [ ] **Step 7: Run the full suite**

```bash
flutter test
```

Expected: `+569`, zero failures.

- [ ] **Step 8: Analyze**

```bash
flutter analyze
flutter build linux --debug
```

Expected: `22 issues found`, build ok.

- [ ] **Step 9: Commit**

```bash
git add test/vault_warning_test.dart test/menu_grid_test.dart
git commit -m "test(cofre): aviso de texto puro e porta para a tela de addons"
git add lib/widgets/settings/vault_warning.dart lib/screens/addon_detail_screen.dart lib/widgets/settings/accounts_setting.dart lib/screens/menu_screen.dart
git commit -m "feat(cofre): avisar quando o segredo fica em texto puro"
```

### Task 25: Accounts becomes the consolidated view

**Files:**
- Modify: `lib/providers/addon_provider.dart` (gains `addonAccountsProvider`)
- Modify: `lib/widgets/settings/console_auth_setting.dart` (gains `onSaved`)
- Modify: `lib/widgets/settings/accounts_setting.dart`
- Modify: `lib/widgets/settings/settings_content.dart` (one comment only)
- Test: `test/accounts_setting_test.dart`

Section 9 says this in writing: "**Accounts** (`accounts_setting.dart`) remains the single vault and becomes the consolidated view: all accounts in one place, from addons or not, with the connection status. The same credential is editable through both paths, and that is the accepted cost of the decision."

Without this Task, what the slice delivers is the opposite: a third-party addon's account only exists inside that addon's detail, and the screen called "Accounts" continues showing only one provider, Internet Archive. A user with three accounts has to open three screens to know which ones are connected.

The three pieces already exist. `MergedCatalog.coverage()` says, per addon, which consoles require an account (Task 18). `addonProvider` gives the order and name (Task 14). `ConsoleAuthSetting(console:, addonId:)` is the pair's form (Task 20). This Task lists the pairs and stacks the forms.

**The pair is the unit, not the console.** Two addons serving the same console appear as two rows, with the same console name and different addon names. It is ugly to look at and it is the only honest way: they are two secrets, in two drawers, and a single row would make the user log in to one and think they logged in to both. A test case locks this.

**The connection status costs a callback, and that is why it exists.** The subtitle needs to say "Connected" or "Not connected", and the only source of that answer is the vault, which is async and which `SecretVault` does not enumerate on purpose (Task 2). Reading once at mount resolves the screen opening and fails right after: the user types the token in the inner form, the form writes to the vault, and the outer subtitle keeps saying "Not connected" above a filled field. For a third-party addon, watching `settingsProvider` does not even help, because `setAddonToken` returns before touching the mirror when the addon is not the builtin (Task 19). So `ConsoleAuthSetting` gains an `onSaved`, and whoever draws the subtitle re-reads.

- [ ] **Step 1: Write the failing test**

Create `test/accounts_setting_test.dart`. The `FakeAddonStore` is the one from Task 22, already committed, and comes in via a relative import. No `dart:io` and no `services/addon_store.dart` for the same reason as Tasks 22 and 23: both only existed for the disk store, and an orphan import is `unused_import`, which is a **warning**.

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/secret_vault.dart';
import 'package:roms_downloader/widgets/settings/accounts_setting.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';

import 'support/fake_addon_store.dart';

const _switch = Console(id: 'switch', name: 'Switch', urls: ['https://myrient/switch/'], auth: {'requires_token': true});
const _snes = Console(id: 'snes', name: 'SNES', urls: ['https://myrient/snes/']);

/// Two addons on the **same** account console, plus a console with no account. It is
/// the case the screen must draw as two rows, and the case a console-keyed
/// implementation would draw as one.
MergedCatalog _twoInSame() => const MergedCatalog(
      consoles: {'switch': _switch, 'snes': _snes},
      sources: {
        'switch': [
          ConsoleSource(addonId: 'myrient', url: 'https://myrient/switch/', auth: {'requires_token': true}),
          ConsoleSource(addonId: 'other', url: 'https://other/switch/', auth: {'requires_token': true}),
        ],
        'snes': [ConsoleSource(addonId: 'myrient', url: 'https://myrient/snes/')],
      },
    );

/// Only the builtin addon, serving a console that requires no account.
MergedCatalog _noAccount() => const MergedCatalog(
      consoles: {'snes': _snes},
      sources: {
        'snes': [ConsoleSource(addonId: kBuiltinAddonId, url: 'https://myrient/snes/')],
      },
    );

/// In-memory store, not an `AddonStore` in `Directory.systemTemp`: disk IO
/// hangs inside `testWidgets`. And no `addTearDown(notifier.dispose)`, which
/// would be a second dispose after the one `StateNotifierProvider` already does
/// when the tree falls. See Task 22 for both.
Future<AddonNotifier> _notifier(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({'app_settings': jsonEncode(<String, dynamic>{})});
  SharedPreferences.resetStatic();
  final notifier = AddonNotifier(Future.value(FakeAddonStore(addons)), invalidateCache: () async {});
  await notifier.ready;
  return notifier;
}

Future<void> _open(
  WidgetTester tester, {
  required AddonNotifier notifier,
  MergedCatalog? catalog,
  SecretVault? vault,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      addonProvider.overrideWith((ref) => notifier),
      mergedCatalogProvider.overrideWith((ref) async => catalog ?? _twoInSame()),
      vaultProvider.overrideWith((ref) async => VaultChoice(vault ?? MemoryVault(), encryptedAtRest: true)),
    ],
    child: const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: AccountsSetting())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no addon requiring an account, only Internet Archive remains', (tester) async {
    final notifier = await _notifier(const [Addon(id: kBuiltinAddonId, name: 'Built-in catalog')]);

    await _open(tester, notifier: notifier, catalog: _noAccount());

    expect(find.text('Internet Archive'), findsOneWidget);
    expect(find.byType(ConsoleAuthSetting), findsNothing);
  });

  testWidgets('each (addon, console) pair that requires an account becomes a block', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    // Two blocks, not one: the console is the same and the secrets are two.
    expect(find.text('myrient.erista.me'), findsOneWidget);
    expect(find.text('other.org'), findsOneWidget);
    expect(find.textContaining('Switch'), findsNWidgets(2));
    // SNES does not require an account and does not appear.
    expect(find.textContaining('SNES'), findsNothing);
  });

  testWidgets('the block order is the addon priority order', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
    ]);

    await _open(tester, notifier: notifier);

    final titles = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().toList();
    final first = titles.indexOf('other.org');
    final second = titles.indexOf('myrient.erista.me');
    // The two `isNonNegative` checks are not excess caution: `indexOf` returns
    // `-1` for absent, and `-1` is less than any valid index. Without them,
    // comparing the two directly makes the case **pass exactly when the block
    // that should come first has vanished from the tree**, which is half the
    // defect it exists to catch. The previous case locks presence, but it is a
    // different case: a `--plain-name` on this one runs it alone.
    expect(first, isNonNegative);
    expect(second, isNonNegative);
    expect(first < second, isTrue);
  });

  testWidgets('the inner form receives the correct pair', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier);
    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();

    final forms = tester.widgetList<ConsoleAuthSetting>(find.byType(ConsoleAuthSetting)).toList();
    expect(forms.length, 1);
    expect(forms.single.addonId, 'myrient');
    expect(forms.single.console.id, 'switch');
  });

  testWidgets('empty vault says not connected and full vault says connected', (tester) async {
    final vault = MemoryVault();
    await vault.write(SecretRef.addonToken('other', 'switch'), 'tok');
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier, vault: vault);

    expect(find.text('Switch: Not connected'), findsOneWidget);
    expect(find.text('Switch: Connected'), findsOneWidget);
  });

  testWidgets('saving in the form updates the subtitle without reloading the screen', (tester) async {
    final vault = MemoryVault();
    final notifier = await _notifier(const [Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json')]);

    await _open(tester, notifier: notifier, vault: vault);
    expect(find.text('Switch: Not connected'), findsOneWidget);

    await tester.tap(find.text('myrient.erista.me'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'tok-new');
    // Required: `enterText` builds no frame, so without this pump the Save
    // button is still disabled (built with `_dirty` false) and the tap below
    // is a silent no-op.
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(await vault.read(SecretRef.addonToken('myrient', 'switch')), 'tok-new');
    expect(find.text('Switch: Connected'), findsOneWidget);
    expect(find.text('Switch: Not connected'), findsNothing);
  });

  testWidgets('removing an addon removes its account from the list', (tester) async {
    final notifier = await _notifier(const [
      Addon(id: 'myrient', name: 'myrient.erista.me', url: 'https://myrient/c.json'),
      Addon(id: 'other', name: 'other.org', url: 'https://other/c.json'),
    ]);

    await _open(tester, notifier: notifier);
    expect(find.text('other.org'), findsOneWidget);

    await notifier.remove('other');
    await tester.pumpAndSettle();

    expect(find.text('other.org'), findsNothing);
    expect(find.text('myrient.erista.me'), findsOneWidget);
  });
}
```

The last case is what justifies the list being derived and not stored. `mergedCatalogProvider` already watches `addonProvider` (Task 22), so removing the addon rebuilds the merge, the merge rebuilds the pairs, and the row disappears on its own. If someone swaps the `ref.watch` for a `ref.read`, this is the case that falls.

`'Save'` and `'Not connected'` stay in English because those are the strings that already exist in the widgets (`console_auth_setting.dart` and `accounts_setting.dart`). This Task does not translate screens.

The two `isNonNegative` checks in the order case came later, from a quality review, and the earlier version shows how a green case can prove nothing. It was one line: `expect(titles.indexOf('other.org') < titles.indexOf('myrient.erista.me'), isTrue)`. The case name talks about **order**, but `indexOf` returns `-1` for absent, and `-1` is less than zero, so the case also passed in the scenario where the first block simply was not in the tree. In other words, it passed both when the order was right and in one of the two breaks it existed to catch. The protection that existed was accidental and external: the previous case locks the presence of both names with `findsOneWidget`, so the **suite** would catch the disappearance. But a case is a unit, and `--plain-name` runs one alone; a case that is only healthy because of its neighbor is healthy by luck. The lesson applies beyond this file: **every comparison on the return of a search that signals absence by a sentinel value must assert presence before comparing**, because the absence value almost always satisfies half the comparisons you were about to write.

The `await tester.pump()` in the sixth case was once missing here, and the way the case fell is the reason the comment is so long. The symptom was `Expected: 'tok-new' / Actual: <null>` reading the vault, meaning **the test pointed at production**: it looked like `_store` was not writing, or that the Task 19 `onSaved` was not arriving. It was neither. The `tap` landed on a disabled button and became a silent no-op, so no production line ran at all, and that is why the error had no production stack: only the assertion. A `tap` that does nothing silently is the worst neighbor of an `expect` that reads `null`.

The convention already existed in the repository, and that is where to check if the doubt comes back: `test/console_auth_setting_test.dart`, in the case `'saving writes under the (addon, console) pair key'`, does exactly `enterText` → `pump()` → `tap('Save')`, and has passed since Task 19. A new case that touches the same form and drops the `pump` is not simplifying: it is departing from the convention that makes the form testable.

The comment cites `onChanged` and `onPressed` **by name and without a line number**, on purpose. Step 4 of this same Task inserts a new field block above both, so any `console_auth_setting.dart:NNN` written here would be born pointing at the wrong line: for whoever writes the test the file is still the one before Step 4, and for whoever reads it later it is already after. A symbol name does not have that problem, and `onChanged` and the Save `onPressed` are unique in that file.

- [ ] **Step 2: Run to see it fail**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/accounts_setting_test.dart
```

Expected: compiles and fails in six of the seven cases, with `Expected: exactly one matching candidate / Actual: _TextFinder:<zero widgets>` on `find.text('myrient.erista.me')` and the subtitle variations. The test does not cite `addonAccountsProvider` or `onSaved` on purpose: it asserts what the screen shows, so it does not need to wait for production to exist before compiling.

The **first** case passes from the start, because today's screen already shows only Internet Archive. That is expected and is not a reason to rewrite it: it is the case that ensures the Task did not add a block where there is no account, and it passes before and after.

- [ ] **Step 3: The pairs that require an account**

In `lib/providers/addon_provider.dart`, right after `addonCoverageProvider`:

```dart
/// An (addon, console) pair that requires a credential.
///
/// The pair is the unit, not the console: two addons serving the same console
/// have two secrets, in two vault keys, and drawing a single row makes the user
/// log in to one and think they logged in to both.
typedef AddonAccount = ({Addon addon, Console console});

/// Every addon account, in addon priority order.
final addonAccountsProvider = FutureProvider<List<AddonAccount>>((ref) async {
  final addons = ref.watch(addonProvider);
  final merged = await ref.watch(mergedCatalogProvider.future);
  final coverage = merged.coverage();
  return [
    for (final addon in addons)
      for (final consoleId in coverage[addon.id]?.authConsoles ?? const <String>[])
        if (merged.consoles[consoleId] != null) (addon: addon, console: merged.consoles[consoleId]!),
  ];
});
```

with the import for `console_model.dart`, if it is not already in the file.

The `if (merged.consoles[consoleId] != null)` is not gratuitous paranoia: `coverage()` builds `authConsoles` from `sources`, and the invariant that ties `sources` to `consoles` (Task 10) is fixed by test, not by the compiler. A `!` there would swap a merge bug for a crash on the settings screen.

- [ ] **Step 4: The form notifies when it writes**

In `lib/widgets/settings/console_auth_setting.dart`, the header gains a field:

```dart
  /// Called after the token reaches the vault, with the new value (empty when
  /// the user logged out).
  ///
  /// Exists because whoever draws the connection status **outside** this form
  /// has no way of knowing it wrote: the vault does not notify, and for a
  /// third-party addon `setAddonToken` returns before touching `settingsProvider`
  /// (Task 19). Optional, because the other two callers draw the status inside
  /// here.
  final void Function(String token)? onSaved;

  const ConsoleAuthSetting({super.key, required this.console, required this.addonId, this.onSaved});
```

and `_store` notifies at the end, after `setState`:

```dart
  Future<void> _store(String token) async {
    await ref.read(settingsProvider.notifier).setAddonToken(widget.addonId, widget.console.id, token);
    if (!mounted) return;
    setState(() {
      _saved = token;
      _dirty = false;
    });
    widget.onSaved?.call(token);
  }
```

The three paths that write (`_save`, `_signin`, `_clear`) all go through `_store`, so a single notification covers all three. Putting the notification in `_save` alone would give a subtitle that gets it right for a pasted token and wrong for a username-and-password login.

- [ ] **Step 5: The screen stacks the accounts**

In `lib/widgets/settings/accounts_setting.dart`, the entire file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/settings/ia_credentials_setting.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

/// Connected accounts, one accordion per provider. Collapsed once connected so
/// it stays out of the way; opens when the user still needs to log in.
///
/// The consolidated view from UI spec section 9: accounts that are not from
/// an addon (today, Internet Archive) and one per (addon, console) pair that
/// requires a credential. The same credential is editable here and in the
/// addon detail, and that is an accepted cost, not an oversight.
class AccountsSetting extends ConsumerWidget {
  const AccountsSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(settingsProvider).hasIaCredentials;
    final accounts = ref.watch(addonAccountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VaultWarning(),
        ExpansionTile(
          // Rebuild so the status subtitle updates after login/logout.
          key: ValueKey('ia_$loggedIn'),
          initiallyExpanded: false,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: EdgeInsets.zero,
          // account_balance is the columned-building glyph — matches the IA logo.
          leading: const Icon(Icons.account_balance),
          title: const Text('Internet Archive'),
          subtitle: Text(loggedIn ? 'Connected' : 'Not connected'),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: const [IaCredentialsSetting()],
        ),
        // Loading and error draw nothing: this is a section inside the settings
        // screen, and a progress bar flashing here on every open costs more
        // than waiting one frame.
        ...accounts.maybeWhen(
          data: (list) => [for (final account in list) _AddonAccount(account: account)],
          orElse: () => const <Widget>[],
        ),
      ],
    );
  }
}

/// An addon account, with the connection state in the subtitle.
class _AddonAccount extends ConsumerStatefulWidget {
  final AddonAccount account;

  const _AddonAccount({required this.account});

  @override
  ConsumerState<_AddonAccount> createState() => _AddonAccountState();
}

class _AddonAccountState extends ConsumerState<_AddonAccount> {
  String? _token;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final token = await ref.read(settingsProvider.notifier).readAddonToken(
          widget.account.addon.id,
          widget.account.console.id,
        );
    if (!mounted) return;
    setState(() => _token = token);
  }

  @override
  Widget build(BuildContext context) {
    final console = widget.account.console;
    // Until the vault responds the subtitle is just the console name, never
    // "Not connected": telling a connected user they are not, for one frame, is
    // the only one of the three answers that is a lie.
    final state = _token == null ? console.name : '${console.name}: ${_token!.isEmpty ? 'Not connected' : 'Connected'}';

    return ExpansionTile(
      initiallyExpanded: false,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined),
      title: Text(widget.account.addon.name),
      subtitle: Text(state),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        ConsoleAuthSetting(
          console: console,
          addonId: widget.account.addon.id,
          onSaved: (token) {
            if (mounted) setState(() => _token = token);
          },
        ),
      ],
    );
  }
}
```

**Likely pitfall:** giving `key: ValueKey(...)` with the token inside, copying the Internet Archive row. There the key exists to force rebuilding when `settingsProvider` changes; here `setState` already rebuilds, and a key that changes with the token **destroys and remounts** `ConsoleAuthSetting` the instant it writes, erasing the text field under the user's finger.

- [ ] **Step 6: Adjust the settings screen comment**

In `lib/widgets/settings/settings_content.dart`, the Task 20 comment was left incomplete. Replace

```dart
              // The console settings panel is the door to the builtin catalog.
              // A third-party addon's account is edited in its detail screen (Task 22).
```

with

```dart
              // The console settings panel is the door to the builtin catalog.
              // A third-party addon's account is edited in Accounts (Task 25)
              // or in the addon detail (Task 22), and both write to the same vault key.
```

- [ ] **Step 7: Run to see it pass**

```bash
flutter test test/accounts_setting_test.dart test/console_auth_setting_test.dart test/addon_detail_screen_test.dart
```

Expected: `+21`, zero failures, with 7 from the new file, 6 from `console_auth_setting_test`, and 8 from `addon_detail_screen_test`. The two existing files enter the count because they are the other two callers of `ConsoleAuthSetting`, and `onSaved` is optional precisely so that neither of them changes: if one falls here, the new parameter was not truly optional.

- [ ] **Step 8: Run the full suite**

```bash
flutter test
flutter analyze
```

Expected: `+576`, zero failures, `22 issues found`.

- [ ] **Step 9: Commit**

```bash
git add test/accounts_setting_test.dart
git commit -m "test(accounts): a visao consolidada lista uma conta por par addon e console"
git add lib/providers/addon_provider.dart lib/widgets/settings/console_auth_setting.dart lib/widgets/settings/accounts_setting.dart lib/widgets/settings/settings_content.dart
git commit -m "feat(accounts): reunir as contas de addon na tela de Accounts"
```

---

Group 5 closes. Eight Tasks, 72 new cases, and the suite goes from `+504` to `+576`. Both endpoints were once written as `+492` and `+564`. Today the difference is twelve, not nine: nine was the original gap, two came from Task 11b and one from Task 12b, both born from the mutation review of Tasks 9 and 10. The 72 and the table below were always correct, and that is what locates the defect: they measure what the group adds, and only the endpoints depend on where the group starts, so the error is entirely before Task 18. These were corrections made after this paragraph and not propagated back to it. One of them I know which is, because it was me: `803669b`, which found 14 cases where Task 11 said 13, accounts for one of the nine. The other eight I did not trace, and I prefer to write that rather than invent the origin. The correct numbers are the current ones, checked step by step against the chain: Task 17 closes at `+504` and the Task 25 row in the table closes at `+576`.

What the group delivered, against UI spec section 9: the ordered list with a drag handle, the per-addon detail with origin, account, coverage, priority, and removal, URL installation, the consolidated Accounts with one row per (addon, console) pair and the connection status, and the token moving from being per-console to being per-pair. What it did not deliver, declared in Task 22: the item count per console in coverage, which would cost one listing request per console when opening a read-only screen.

| Task | Casos | Acumulado |
| --- | --- | --- |
| 18 | 17 | `+521` |
| 19 | 13 | `+534` |
| 20 | 6 | `+540` |
| 21 | 6 | `+546` |
| 22 | 8 | `+554` |
| 23 | 9 | `+563` |
| 24 | 6 | `+569` |
| 25 | 7 | `+576` |

---

## Group 6: the contract with the RTS, and the slice sweep

Two Tasks. The first pins something the architecture spec states and no test supports: the app is both producer and consumer of the same addon format, and this slice touched the format. The second is the acceptance criterion for the entire slice.

### Task 26: the RTS keeps feeding the app

**Files:**
- Test: `test/rts_addon_contract_test.dart`

No production file. This Task only writes a test, and that is by design.

Architecture spec section 6.4 says that the **Retro Tools Server** builds a catalog of local folders and serves it at `http://host:port/consoles.json`, which is exactly the address addon installation consumes. Producer and consumer are the same binary. And it draws the consequence: "any extension of the format must also be emitted by the RTS. If the addon starts declaring `auth` and the RTS keeps emitting the old format, the app will no longer be able to feed itself."

This slice touched the format: `harvestAuthTokens` removes `auth.token` and inserts `requires_token`, the merge started loading `ConsoleSource` per console, and the addon id became a vault key. None of that breaks the RTS, which never emitted `auth`. What does not exist is a test that falls on the day it does break, and the cost of writing it is five cases without a single production line.

`RtsServerService.consoleJson` and `buildConsolesJson` are static and pure (`rts_server_service.dart:13-24`), so the test wires producer to consumer without starting a server.

- [ ] **Step 1: Write the tests**

Create `test/rts_addon_contract_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/rts_folder_model.dart';
import 'package:roms_downloader/models/secret_ref.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';
import 'package:roms_downloader/services/rts_server_service.dart';
import 'package:roms_downloader/services/secret_vault.dart';

const _folders = [
  RtsFolder(path: '/home/u/psp', name: 'PSP', formats: ['.iso'], romsSubfolder: 'psp'),
  RtsFolder(path: '/home/u/snes', name: 'SNES', formats: ['.zip'], romsSubfolder: 'snes'),
];

String _emitted() => RtsServerService.buildConsolesJson(_folders, '192.168.0.10:8080');

void main() {
  test('what the RTS emits is a catalog the consumer parses', () {
    final consoles = CatalogService.parseConsoles(_emitted());

    expect(consoles.keys, containsAll(<String>['psp', 'snes']));
    expect(consoles['psp']!.urls.single, 'http://192.168.0.10:8080/f/0/');
  });

  test('the id the RTS generates equals the id the consumer computes', () {
    // Both sides are spelled out literally on purpose: asserting one derivation
    // against the same derivation passes for any implementation, even a broken one.
    final emitted = (jsonDecode(_emitted()) as List).cast<Map<String, dynamic>>();

    expect(emitted.map((c) => c['name']).toList(), <String>['PSP', 'SNES']);
    expect(CatalogService.parseConsoles(_emitted()).keys.toList(), <String>['psp', 'snes']);
  });

  test('the RTS emits no token, so harvesting leaves its output unchanged', () async {
    final vault = MemoryVault();
    final clean = await CatalogService.harvestAuthTokens(_emitted(), vault: vault, addonId: 'rts');

    expect(CatalogService.parseConsoles(clean).keys, CatalogService.parseConsoles(_emitted()).keys);
    for (final folder in _folders) {
      expect(await vault.read(SecretRef.addonToken('rts', CatalogService.consoleId(folder.name))), isNull);
    }
  });

  test('no RTS console asks for an account', () {
    for (final console in CatalogService.parseConsoles(_emitted()).values) {
      expect(authNeedsToken(console.auth), isFalse);
    }
  });

  test('the RTS catalog merges under the installer addon id', () {
    final merged = mergeCatalogs([
      (addonId: Addon.idFromUrl('http://192.168.0.10:8080/consoles.json'), consoles: CatalogService.parseConsoles(_emitted())),
    ]);

    expect(merged.sources['psp']!.single.addonId, '192_168_0_10_8080_consoles_json');
    expect(merged.sources['psp']!.single.auth, isNull);
  });
}
```

The last case fixes the id in full, and not via `Addon.idFromUrl(...)` on both sides, because an assertion that calls the same function that produced the value passes even when the function is wrong. `192_168_0_10_8080_consoles_json` is ugly and that is the point: that is the name of the file that goes into `config/addons/`, and seeing it written once in the test is what stops someone from "improving" the slug without realizing it is a vault key.

`_folders` is iterated in a loop in the third case on purpose: the folder list is the producer's input, so iterating it is iterating exactly what the RTS emitted, without depending on the consumer having parsed correctly.

The second case was also a loop over `_folders`, and the version it had is the record that this vice recurs. The last case in this file rightly brags about writing `192_168_0_10_8080_consoles_json` in full instead of calling `Addon.idFromUrl` on both sides; three cases above, the second did exactly what the last avoids. It wrote `parseConsoles(_emitted()).containsKey(consoleId(folder.name))`, and both sides of that are `_nameToId` of the same name: the producer emits `'name': f.name` verbatim and `parseConsoles` keys with `_nameToId(name)`, while `consoleId` is `_nameToId`. The assertion was true for any id rule, including a broken one, and the comment was selling exactly the guarantee the code was not giving. Worse than not having the case: a case that promises detection and does not detect makes the next person trust it. The current version anchors each assertion on a literal, and covers something the first case does not cover, which is the producer sending the raw name instead of a pre-made slug.

- [ ] **Step 2: Run**

```bash
export PATH=/home/exedev/flutter/bin:$PATH
flutter test test/rts_addon_contract_test.dart
```

Expected: `+5`, zero failures. **No "see it fail" step:** this Task has no production code, and the five cases pass on the first run. A contract test that is already green is its normal state; the value is in falling when the next slice touches the format.

If any falls here, **do not fix the test**. It is saying the producer and consumer diverged in this slice, and the fix is on the side that diverged.

- [ ] **Step 3: Run the full suite**

```bash
flutter test
```

Expected: `+581`, zero failures.

- [ ] **Step 4: Analyze**

```bash
flutter analyze
```

Expected: `22 issues found`, and none of them in `rts_addon_contract_test.dart`.

- [ ] **Step 5: Commit**

```bash
git add test/rts_addon_contract_test.dart
git commit -m "test(rts): contrato entre o servidor que emite catalogo e o app que instala"
```

---

### Task 27: the slice sweep

**Files:** none. This Task writes no code: it measures.

The acceptance criterion for the entire slice, against commit **`ef5ee57`**, which is the HEAD before slice 4. That hash is load-bearing: it is written here and nowhere else, so no rebase, amend, or filter-branch that reaches it while the slice is open.

A warning that cost two full measurements in a previous slice: **do not chain `git checkout <ref> && <command>; git checkout -` in a single call.** To inspect history, use `git show <ref>:<path>` and `git diff <refA> <refB> -- <path>`, which do not touch HEAD.

- [ ] **Step 1: What the slice could not touch**

```bash
git diff --stat ef5ee57 -- \
  lib/services/tinfoil_server_service.dart \
  lib/services/jdkv_server_service.dart \
  lib/services/rts_server_service.dart \
  lib/services/smb_service.dart \
  lib/services/webdav_server_service.dart \
  lib/services/metadata_pack_service.dart \
  lib/services/pack_matcher.dart \
  lib/models/metadata_pack_model.dart \
  lib/models/pack_index_model.dart
```

Expected: empty output.

The five file-serving servers are there because section 6.4 says, in writing: "the other five servers (Tinfoil, JDKV, FBI, SMB, FTP) are a different category: they serve **files** to a console or another device, not a **catalog** to the app. Nothing in this document affects them". `rts_server_service.dart` is there because Task 26 wrote tests for it **without** changing it, and a non-empty diff here means someone fixed the producer instead of fixing whatever diverged. The rest is slice 1, which this slice had no reason to reach.

- [ ] **Step 2: What the slice touched in `lib/`**

```bash
git diff --name-only ef5ee57 -- lib/ | sort
```

Expected: exactly these 39 files.

```
lib/models/addon_model.dart
lib/models/console_model.dart
lib/models/game_model.dart
lib/models/secret_ref.dart
lib/models/settings_model.dart
lib/models/source_pick_model.dart
lib/providers/addon_provider.dart
lib/providers/catalog_provider.dart
lib/providers/download_provider.dart
lib/providers/fbi_server_provider.dart
lib/providers/pack_grid_provider.dart
lib/providers/settings_provider.dart
lib/providers/tinfoil_server_provider.dart
lib/providers/vault_provider.dart
lib/screens/addon_detail_screen.dart
lib/screens/addons_screen.dart
lib/screens/game_detail_screen.dart
lib/screens/home_screen.dart
lib/screens/menu_screen.dart
lib/screens/setup_wizard_screen.dart
lib/screens/tinfoil_server_screen.dart
lib/services/addon_install.dart
lib/services/addon_store.dart
lib/services/catalog_service.dart
lib/services/console_merge.dart
lib/services/prefs_vault.dart
lib/services/secret_migration.dart
lib/services/secret_vault.dart
lib/services/secure_storage_vault.dart
lib/services/settings_service.dart
lib/services/source_pick_service.dart
lib/services/task_queue_service.dart
lib/utils/console_auth.dart
lib/utils/network.dart
lib/widgets/settings/accounts_setting.dart
lib/widgets/settings/catalog_source_setting.dart
lib/widgets/settings/console_auth_setting.dart
lib/widgets/settings/settings_content.dart
lib/widgets/settings/vault_warning.dart
```

Check item by item, not just the total: the count matches by coincidence when an expected file vanished and an unexpected one entered. The `39` is derived from this list, so a QA note that creates a new file updates both at the same time.

- [ ] **Step 3: What the slice touched in `test/`**

```bash
git diff --name-only ef5ee57 -- test/ | sort
```

Expected: exactly these 33 files.

```
test/accounts_setting_test.dart
test/addon_coverage_test.dart
test/addon_detail_screen_test.dart
test/addon_install_test.dart
test/addon_model_test.dart
test/addon_provider_test.dart
test/addon_store_test.dart
test/addon_token_test.dart
test/addons_screen_test.dart
test/catalog_addons_test.dart
test/catalog_auth_token_test.dart
test/console_auth_setting_test.dart
test/console_auth_test.dart
test/console_merge_test.dart
test/game_detail_screen_test.dart
test/game_source_id_test.dart
test/menu_grid_test.dart
test/pack_grid_provider_test.dart
test/pack_grid_test.dart
test/prefs_vault_test.dart
test/rts_addon_contract_test.dart
test/secret_migration_test.dart
test/secret_ref_test.dart
test/secret_vault_test.dart
test/secure_storage_vault_test.dart
test/settings_hydrate_test.dart
test/settings_model_secrets_test.dart
test/settings_service_test.dart
test/source_pick_service_test.dart
test/support/fake_addon_store.dart
test/vault_contract.dart
test/vault_provider_test.dart
test/vault_warning_test.dart
```

Five of them are **existing** files that were modified, not created: `test/game_detail_screen_test.dart`, `test/menu_grid_test.dart`, `test/pack_grid_provider_test.dart`, `test/pack_grid_test.dart`, and `test/source_pick_service_test.dart`. Any other existing file in this list is a finding, not noise: it means the slice changed behavior it did not declare changing. `test/settings_service_test.dart` is **not** existing: the repository had no `SettingsService` test before this slice. `test/settings_hydrate_test.dart` is not either: Task 8b created it in `b5553bf` and Task 9 touched it in `41991eb`.

This Step was once wrong, and the error is the same one the Task 9 paragraph tells from another angle: the list was written before Task 8b existed, and `test/settings_hydrate_test.dart`, which belongs to it, was left out. The total said `32`. Measured with the slice at `414c43f`, missing only Tasks 24 to 26: `git diff --name-only ef5ee57 -- test/ | sort` returns 30 files, and `comm` against this Step's list flagged three expected absences (`accounts_setting_test`, `rts_addon_contract_test`, and `vault_warning_test`, from the three missing Tasks) plus **one unexpected presence**, `settings_hydrate_test`. 30 plus the three outside gives 33, not 32. The lesson is the same as Step 2 just above, and applies to both: check item by item, because a total that matches does not prove a list that matches, and here the total did not even match.

`test/vault_contract.dart` and `test/support/fake_addon_store.dart` do not end in `_test.dart` on purpose: they are shared helpers with no `main`, so the runner does not execute them on their own.

- [ ] **Step 4: `pubspec`**

```bash
git diff ef5ee57 -- pubspec.yaml
```

Expected: one line added, `flutter_secure_storage`, and nothing else. `pubspec.lock` changes with it and that is expected.

- [ ] **Step 5: Analyze**

```bash
flutter analyze
```

Expected: **`22 issues found`**.

Watch this number carefully: they are **21 `info` and one `warning`**, and the `warning` is the `unnecessary_non_null_assertion` in `test/webdav_server_test.dart:69`, which is pre-existing and not in a file this slice touched. The criterion is **not** "zero warnings"; it is: 22 findings, zero `error`, and **zero findings in a file touched by the slice**. Cross the output against the two lists from Steps 2 and 3.

- [ ] **Step 6: The suite**

```bash
flutter test
```

Expected: `+581`, zero failures.

There is no longer "the usual failure": the only red test in the repository (`test/rar_decompress_screen_test.dart`) was fixed in `5d21b14`, before this slice started. Any failure here is a regression.

- [ ] **Step 7: The app compiles in full**

```bash
flutter build linux --debug
```

Expected: build ok.

**This is not a visual check, and pretending otherwise would be wrong.** The VM is headless: it has no `DISPLAY` or `Xvfb`, so `flutter run -d linux` does not run. The build compiles the whole app and catches compile regressions on the GUI path, which is most of this slice, and proves nothing about what appears on screen. The addons screen, the drag, the consolidated Accounts, and the vault warning are verified by widget test and by reading. Say that in the report instead of writing "verified visually".

- [ ] **Step 8: The 6.3 sweep, with the two halves separated**

This is the reason for the slice's existence, and it is the step most tempting to summarize incorrectly.

First, the sites that read the token from inside the shareable file. The grep that finds all four is **not** by `buildConsoleAuthHeaders`, which only finds its callers:

```bash
grep -rnE "auth\??\['token'\]" lib/
```

The `-E` is mandatory, and if you run the BRE version of this grep the sweep lies to you: without `-E`, `\?` becomes a quantifier and the second `?` becomes a literal, the pattern then requires a `?` after `auth`, and the only one of the four that writes `auth['token']` without `?` is exactly `network.dart:41`, the site that section 6.3 lists. Measured before Task 7 ran: BRE found three, `-E` found four.

Expected: **one single line**, and no other: **the comment in `lib/utils/network.dart:41`**, which cites `` `?? auth['token']` `` in backticks to record what was there before; it is text, not a read, and confirmed by inspecting the line. Any second line is a live site.

An earlier version of this Step said "two classes of lines", counting `harvestAuthTokens` as the first. That is wrong, and the correction is measured: Task 7 wrote `harvestAuthTokens` with `auth.containsKey('token')` and `auth.remove('token')`, never with a subscript `auth['token']`, so this first grep cannot find it. What finds `harvestAuthTokens` is the **second** grep, the one for `'token'` in `catalog_service.dart`, just below. The two classes exist, but one in each sweep, not both in the first. The four starting sites were `lib/utils/network.dart:41`, `lib/services/task_queue_service.dart:20`, `lib/screens/tinfoil_server_screen.dart:91`, and `lib/screens/setup_wizard_screen.dart:392`. The last two did not build a header: they decided whether the console "has auth configured" with `(c.auth?['token'] as String?)?.isNotEmpty ?? false`, which is why they go unnoticed in a grep for `buildConsoleAuthHeaders`. If they remain, the app continues saying "this console has auth" based on a field nobody reads anymore for authentication. It is not a leak; it is an interface lie.

Then, the shareable file itself:

```bash
grep -rn "'token'" lib/services/catalog_service.dart lib/models/settings_model.dart
```

Expected: only the occurrences inside `harvestAuthTokens`.

And then **write the report with the two halves separated**. They did not close together, and reporting "6.3 fixed" without separating them is window-dressing:

1. **Removing the token from the shareable JSON: closed, unconditional, on every platform.** It is the file the user sends to someone else, and `harvestAuthTokens` removes the token from it at installation, on any operating system, with or without a keyring. Proven by the Task 8 cases and the greps above. The **export** half that section 6.3 also asks for was not done because there is nothing to do: the app does not export a catalog at `ef5ee57`. Say that with those words, and not "export fixed".
2. **Encrypting the secret at rest: best-effort, and does not happen on every machine.** Depends on `flutter_secure_storage` opening, and on Linux that requires `gnome-keyring` or KWallet live on D-Bus. On a server Linux there is none, `chooseVault` falls back to `PrefsVault`, and the secret stays in plain text, as it always was. What the slice delivers in that case is the warning on the screen where the secret is typed (Task 24), not the encryption.

State which of the two cases **this** machine fell into:

```bash
flutter test test/vault_provider_test.dart
```

The Task 4 cases say what `chooseVault` does with a backend that responds and one that does not; what they do not say is which of the two is the D-Bus on this VM. If you want that answer, it comes from the running app, not from the suite, and on a headless VM it remains open. Report it as open rather than assuming.

- [ ] **Step 9: The report**

No commit. What comes out of here is the closing text for the slice, and it must contain, in this order: the literal result of each of the eight Steps, the separation of the two 6.3 halves, the declared debt from Task 22 (coverage does not count items per console), and what was verified only by reading (the order inside `invalidateForAddonChange`, in Task 14, and the appearance of the two new screens and the rebuilt Accounts).

---
