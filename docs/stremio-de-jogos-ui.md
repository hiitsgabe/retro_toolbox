# Stremio for Games: UI

Date: 2026-09-10
Status: proposal, awaiting review
Complements: `docs/stremio-de-jogos-design.md`

## 1. Scope

This document defines the interface. The architecture is in the sibling spec and is not repeated here.

Almost everything below applies to **PACK MODE** (section 7 of the architecture spec). In **SOURCE
MODE**, which today is only the Switch, the grid stays exactly as it is: raw listing, per-tile
download button, no change. A console without a pack is not affected by this document.

Two things apply to both modes, because they do not depend on a pack: the selection bar in the
footer (section 5) and the batch confirmation sheet (section 6). Multi-selection already exists
today, with the "Download Selected" button in the header, and these two sections improve what is
already there. In section 4, the short tap is PACK MODE, because only there is there a detail
screen to open. The rest of section 4 applies to both.

## 2. Locked decisions

| Decision | Reason |
| --- | --- |
| **A short tap always opens the detail screen** | The meaning of the tap never changes. This eliminates a "selection mode" and, along with it, the contextual bar that would replace the header. |
| **Selection is state that survives navigation** | The user selects, opens a game, reads the synopsis, goes back and keeps selecting. It is already this way in the state (`catalogProvider.selectedGames`), and it becomes this way in the UI. |
| **The selection counter lives in a fixed bar in the footer** | Same position on the grid and on the detail, impossible to miss. The `×` on the left clears the selection. |
| **The selection bar stacks on top of the tasks footer** | Both things stay active at the same time and neither hides the other. |
| **A batch is rule plus confirmation** | The app picks the version by a deterministic rule and shows the result before enqueuing, with a per-item override. |
| **The detail highlights the best choice and collapses the rest** | One tap in the common case, expansion for whoever wants to choose. |
| **The tile marks only the exception** | 96.98% of games have a source. Marking the ones that have a source is noise on 97% of the covers. |
| **Match confidence does not appear on the tile** | Confidence is a property of the source, and a source only appears in the detail. The game exists; what is uncertain is one of its sources. |
| **An uncertain match is resolved by CRC when the detail is opened** | 2 `Range` requests, 326 bytes. Better than asking the user to guess by filename. |
| **An addon has its own detail screen** | Coverage, account, priority and removal in one place. Accounts stays the single vault and becomes the consolidated view. |
| **Priority between sources is manual, by drag** | The app has no way to compute "best source": it does not know which server is faster nor which dump is more reliable. |
| **Debrid resolves inside the task, not blocking the screen** | It is the only option that works in a batch, and the queue is already where slow things live in the app. |

## 3. The grid

### 3.1 The tile

The tile now represents a **game**, not a file. Three consequences in
`game_grid_item.dart`:

1. The disc, revision and region tags (`:123-186`) leave the tile. They describe a version, and
   the version is now chosen on the detail screen.
2. The `GameActionButtons` in the top right corner (`:210-230`) leaves. The tile no longer knows
   which file to download, so it cannot have a download button.
3. The tile gains `onTap`, which opens the detail, and `onLongPress`, which selects.

What the tile shows: cover, overlaid title, the "no source" mark when applicable, the selection
checkbox when there is an active selection, the existing state border (`:34-46`) and the existing
progress bar (`:187-205`).

**"No source" mark**: a desaturated cover plus an icon (`Icons.cloud_off_rounded`) in the top
right corner. Two deliberately redundant signals, because gray alone is ambiguous with
"loading" and several period covers are already almost monochrome. The ones that have a source
get no mark at all.

The source count does **not** appear on the tile. It appears on the detail, as "N other sources".

**The "already downloaded" border changes meaning.** Today it reflects a file:
`library_snapshot_provider.dart` indexes the directory by exact name and base name, and the name
on the grid is the name on disk. In PACK MODE the tile is a game, so the border now means
"you have some version of this game". This requires mapping a local file back to a canonical
game, with the name first and CRC only when in doubt rule from section 5.7 of the architecture
spec. While the scan runs, the tile shows no border at all, never a wrong border.

### 3.2 Empty states

The "mark only the exception" argument depends on most games having a source, and that depends on
the installed addon. With no addon installed, 100% of the games would be an exception, which is
absurd.

Rule: if **no addon is installed**, the grid marks no tile at all. It shows a banner at the top,
"no source installed", with a shortcut to the addons screen. This is an empty state of the grid,
not a state of the tile.

If there is an addon installed but it does not cover the current console, the banner is the same
with different text: "no installed addon covers this console".

## 4. Selection

There is no selection mode. Selection is a state, it survives navigation and the short tap never
changes meaning.

| Gesture | Effect |
| --- | --- |
| Short tap on the tile | Opens the detail screen. PACK MODE only: in SOURCE MODE the tile has no short tap today and stays without one |
| Long press on the tile | Toggles the selection of that game |
| Click on the checkbox | Toggles the selection of that game |
| `×` in the footer bar | Clears the entire selection |

**Checkbox visibility.** Today the checkbox appears whenever the game is interactive
(`game_grid_item.dart:69`). It now appears only when the selection is not empty, on **all** the
tiles, until the selection is emptied. A clean cover while no one has selected anything, an
obvious discovery after the first long press. On desktop it also appears on tile hover, with the
selection empty or not.

**Entering the selection from the detail.** The detail screen has a checkbox next to the favorite
heart, in the same corner. Without it, the user who opened a game would have to go back to the
grid just to select.

## 5. The selection bar and the footer

The tasks footer already exists and is already occupied (`footer.dart`): on the left "Downloading
N, Extracting M" and the game count, on the right the progress bar and the directory, in the
middle the arrow that opens the `TaskPanelModal`.

The selection bar sits **on top** of it, as a second strip, in solid purple. It appears when
there is a selection and disappears when it is emptied. Both can be active at the same time,
because selecting 3 games while another 2 are downloading is the normal case.

```
+-----------------------------------------------+
|  ×  3 selected                  [ Download ]  |  <- purple, disappears when emptied
+-----------------------------------------------+
|  Downloading 2, Extracting 1   ====  /roms    |  <- footer.dart, untouched
+-----------------------------------------------+
```

Accepted cost: with an active selection, one row of covers disappears on a phone.

The bar exists on both screens, grid and detail, in the same position.

**Consequence in the header**: the "Download Selected" button (`header.dart:186-194`) leaves. The
footer bar does the same thing, in a more visible place and with the counter alongside. Two
buttons for the same action is worse than one.

## 6. Batch: rule plus confirmation

When tapping Download with N games selected, the app picks one version per game with this rule,
in this order:

1. **Preferred region**, read from the existing filter (`catalog_filter_model.dart`, `regions`,
   default `{'USA'}`).
2. **Highest revision**.
3. **Highest match confidence**.
4. **Addon priority**, the manual order from section 9.

Before enqueuing, a confirmation sheet: "40 games, 1.2 GB", the list of what was chosen and a
per-item override. Games without a source and games where the rule found no candidate appear
separately, with the reason, and do not enter the queue.

The rule is the same one that picks the highlight on the detail screen. One rule, two places.

**The batch does not verify CRC before enqueuing.** The verification in section 8 costs 2 requests
per uncertain file, and across 40 games that becomes a burst of 80 requests before the download
begins. Instead, the confirmation sheet marks the uncertain items with the same badge as the
detail, and the safety net is the CRC32 verification the pipeline already does **after** the
download. Whoever wants certainty beforehand opens the game, which is exactly the trigger for
section 8.

## 7. The detail screen

New screen, `lib/screens/game_detail_screen.dart`. It is not a bottom sheet and not an inline
expansion.

**Top**, the same in all states: cover, title, metadata (console, year, publisher, genre),
synopsis, favorite heart and the selection checkbox.

**Body**, in the common case: a highlight card with the version the app would pick, the reason
written out in full, and the Download button. The rest collapses behind "N other sources".

```
+---------------------------------------------+
| <-  Crystal Vanguard            (heart) [ ] |
+---------------------------------------------+
| [cover] Crystal Vanguard                    |
|         SNES, 1995, Square, RPG             |
|         synopsis...                         |
+---------------------------------------------+
| Crystal Vanguard (USA)                HTTP  |
| 4.0 MB, Myrient                             |
| chosen by your preferred region             |
| [           Download            ]           |
+---------------------------------------------+
| v 5 other sources                           |
+---------------------------------------------+
```

The reason is mandatory, not decorative. It is the only thing that separates "the app chose for
you" from "the app chose at random".

Expanded, each line shows: filename, size, originating addon, source type (HTTP, SEED, RD) and
the confidence state.

**"No source" state**, the 3% from section 3.1: the screen is complete and functional. Cover,
synopsis, metadata and favorite all work. In place of the highlight card, a banner "no installed
addon has this game" with a shortcut to the addons screen. The game keeps existing and stays
favoritable, it just has nowhere to come from today.

## 8. Match confidence

Around 10% of name matches are wrong on non-canonical sources. Highlighting a guess with the same
look as a certainty is a lie, and the app has a way not to lie.

**When the detail is opened**, for each source whose match is not trustworthy, the app fires off
the CRC32 read from the ZIP header via HTTP `Range`: 2 requests, 326 bytes per file. While it
runs, the source shows the "verifying" label and the button says "Download anyway".

When it finishes, each source falls into one of three states:

| State | What appears |
| --- | --- |
| CRC matches the pack | A "CRC ok" badge and the reason becomes "confirmed by CRC, this is exactly this dump" |
| CRC matches nothing | The source is dropped from the highlight and moves down into the list, marked. The counter becomes "N other sources, 1 discarded" |
| Verification impossible | Falls into the behavior described two paragraphs below |

The highlight **may switch files** after verification. That is the point: the app corrects its own
choice before the user spends bandwidth.

**When verification is impossible** (server without `Range` support, a file that is not a ZIP, a
debrid source not yet resolved), the app highlights nothing. The card becomes "I am not sure of
any of them" and the list opens expanded, with a Download button per line and the uncertainty
badge on each one. It never fakes certainty.

The verification result is cached per (source, file), so the second opening of the same game is
instant.

This is the "confidence in the UI" from slice 2 of the architecture spec.

## 9. Addons and accounts

The app ships with no source at all, so **installing an addon is the first thing the user does**.
The plumbing to install by URL already exists (`setCatalogFromUrl`,
`add_catalog_source_screen.dart`), and today's `consoles.json` enters as addon no. 1, at the top
of the order. Whoever already uses the app sees no difference the next day.

**Addons screen**, a lean list. Each row: icon, name, coverage summary ("25 consoles"), an
"account" chip when it requires a credential, a drag handle and an arrow. At the end, "+ Install
from URL".

**The "New Catalog Source" tool stays in Tools, where it is.** The two paths coexist because they
serve different audiences: the tool assembles a console by hand, asking for name, ROMs folder,
formats and unzip behavior; "+ Install from URL" installs a catalog that comes ready-made.
Accepted cost: two paths that end up in the same place. What the hand-assembled console gains is
appearing in the addons list like any other, with draggable priority and an account if needed.

The **Retro Tools Server** appears in the addons list of whoever installs its URL, and nothing
changes on the server screen itself. It is the producer of the same format, and the link is in
section 6.4 of the architecture spec.

**Addon detail screen**, one per addon:

- Identification: name and origin URL
- **Account**: the credential form, in the format the addon declares (username and password,
  API key, S3 keys)
- **Coverage**: which consoles it serves and how many items in each
- **Priority**: the current position, with the instruction to drag in the list
- **Remove**

**Accounts** (`accounts_setting.dart`) stays the single vault and becomes the consolidated view:
all accounts in one place, from an addon or not, with the connection state. The same credential is
editable through both paths, and that is the accepted cost of the decision.

**Real-Debrid is not an addon, it is an account.** It appears in Accounts and never in the addons
list. Whoever produces the magnet is the torrent addon, whoever resolves the magnet into a direct
link is the account. This matters because the same account serves several torrent addons at the
same time.

**Priority is manual, by drag.** The order of the list is the tiebreaker for section 6 and for the
highlight in section 7.

Credentials go to `flutter_secure_storage`, never to the addon's shareable JSON nor to
`shared_preferences`. This is slice 4 of the architecture spec and is detailed there.

## 10. Debrid: the wait lives in the queue

Downloading from an HTTP source is immediate: there is a URL, enqueue, done. Via Real-Debrid it is
not. The app sends the magnet, selects the files and waits for RD to download the torrent from the
peers before asking for the direct link. Cached it is seconds, out of cache it can be minutes or
never. And there is no way to know beforehand: `instantAvailability` responds `error_code 37`
since Real-Debrid turned it off.

**Tapping Download is always instant.** The task is born in the queue
(`task_queue_service.dart`) with a new state, "resolving", and turns into "downloading" on its own
when the link comes out. The screen does not block and there is no modal.

This is mandatory because of the batch: selecting 40 games where some are RD cannot become 40 waits
nor 40 progress sheets.

In the footer, the counter gains the state: "Resolving 1, Downloading 2". The progress bar stays
indeterminate while there is only a resolving task, because at that stage there is no true
percentage on the app side.

In the `TaskPanelModal`, the task line shows the game, the addon, the size and the state.

**A failure here is the common case, not the exception**: torrent with no seeds, an account with no
traffic, an invalid magnet. The failed task stays in the panel with the reason on one line and a
"try another source" button, which reopens the game detail with the source that failed already
struck out. No disappearing on its own.

## 11. What changes in existing code

| File | Change |
| --- | --- |
| `widgets/game_grid/game_grid_item.dart` | Two variants by mode. In PACK MODE: the tags block leaves (`:123-186`), `GameActionButtons` leaves (`:210-230`), `onTap` and `onLongPress` enter, the "no source" mark enters, the checkbox (`:69-84`) becomes conditional on a non-empty selection. In SOURCE MODE: untouched |
| `widgets/game_grid/game_grid.dart` | Empty-state banner at the top when there is no addon or the addon does not cover the console |
| `widgets/footer/footer.dart` | Selection bar stacked above, counter and `×`, "Resolving N" state |
| `widgets/footer/task_list_view.dart` | "resolving" state and a failure line with reason and "try another source" |
| `widgets/header/header.dart` | The "Download Selected" button leaves (`:186-194`) |
| `widgets/settings/accounts_setting.dart` | Becomes the consolidated view of accounts, including debrid |
| `services/task_queue_service.dart` | "resolving" state before "downloading" |
| `models/catalog_filter_model.dart` | `regions` now feeds the batch rule, in addition to the filter |
| `providers/library_snapshot_provider.dart` | In PACK MODE, maps a local file to a canonical game: name first, CRC when in doubt, cache by path, size and mtime |
| `screens/add_catalog_source_screen.dart` | No flow change. The console it creates now appears in the addons list |
| `screens/rts_server_screen.dart` | No screen change. It just needs to emit the format extensions when they exist, section 6.4 of the architecture spec |
| **new** `screens/game_detail_screen.dart` | Sections 7 and 8 |
| **new** `screens/addons_screen.dart` | Addons list, section 9 |
| **new** `screens/addon_detail_screen.dart` | Addon detail, section 9 |
| **new** batch confirmation sheet widget | Section 6 |

## 12. Out of scope

- **Where to buy.** It was already out in the architecture spec, it stays out.
- **Contextual selection bar.** It died along with the selection mode.
- **"Cached on debrid" badge.** Impossible to give honestly while `instantAvailability` is dead.
- **Coverflow and list.** `ViewMode.coverflow` and `ViewMode.list` keep existing and stay as they
  are. This document only covers the grid. Adapting them to PACK MODE is separate work.
- **Theme redesign.** Material 3, seed `#7C4DEF` and ChakraPetch stay as they are.
- **Tinfoil, JDKV, FBI, SMB and FTP.** They serve files to another device, not a catalog to the
  app. Untouched.
- **The local-file tools.** NSZ, RAR, CHD, CIA, M3U, Collection Clean, Steam Shortcuts and Sports
  stay as they are. It is worth noting that in PACK MODE they gain something they never had, a
  canonical name and a CRC per game, but taking advantage of that is separate work.

## 13. Implementation order

This document does not become a single plan. It spreads across the slices of the architecture
spec:

| Section of this document | Slice |
| --- | --- |
| 8, match confidence | Slice 2, Identity |
| 3.1, "already downloaded" border | Slice 2, Identity |
| 3, 4, 5, 6, 7, grid, selection, batch and detail | Slice 3, Grid and modes |
| 9, addons and accounts | Slice 4, Addon and Accounts |
| 10, debrid in the queue | Slice 6, Debrid |

Sections 5 and 6, plus the part of section 4 that is not the short tap, are the useful exception:
they do not depend on a pack, on the matcher nor on an addon. They can be done before everything
else, in isolation, and they already improve today's app.
