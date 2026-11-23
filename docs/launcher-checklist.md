# Launcher mode on a device

Run this after installing a build, on an Android device with the emulators
you can get, and on each desktop OS you have. Nothing here can be checked by
the Dart tests: they pin what Dart sends over `retro_toolbox/launcher`, and
only a device shows what an emulator does with it.

A preset flips to `"verified": true` in `launch_presets/launch_presets.json`
only once its row passed.

## Before the rows

1. **Library folder.** Settings > Download folder is outside `Android/data`
   (for example `/storage/emulated/0/ROMs`). With the default app folder,
   every `path` and `saf` launch ends in "Move your library out of
   Android/data", which is item 6.
2. **Detection.** Open the details page of a game you have on disk. Play is
   the action bar's primary, and Start presses it. With one installed
   emulator for that system, Play starts it; with none, Play is disabled and
   reads "No emulator for <system>". On a landscape handheld (731 px wide or
   less), the bar still fits with Play, Open with, Open <emulator>, Extract,
   Select and Favourite.
3. **Open with.** "Open with…" lists every installed emulator for the
   system, "not tested" beside each unverified one. "Just this once" starts
   it and keeps nothing; "Always for this game" starts it, and the next Play
   on that game uses it again, also after an app restart.
4. **Dual screen.** On a dual screen device with *Main on bottom*, Play: the
   game opens on the top screen, and Retro Toolbox does not come back over
   it.
5. **Gone emulator.** Uninstall an emulator after a launch, then press Play
   again without leaving the page: "<emulator> is not installed anymore"
   with "Detect again".
6. **Android/data.** Point a console's folder at the app's own
   `Android/data/.../files` folder and press Play with a `path` or `saf`
   preset: "Move your library out of Android/data" with "Choose folder", and
   no emulator opens. A `provider` preset still opens the game.
7. **Folder access hint.** With a `saf` preset chosen, the page shows "If
   <emulator> says it cannot open the file, give it access to <folder>" and
   "Open <emulator>", which opens the emulator.
8. **All files access.** On Android 11 or later, with an emulator that asks
   for all files access (the website RetroArch, DuckStation), the launcher
   wizard's Systems step shows "Allow all files access for <emulator>". It
   opens the system page of that emulator, not of Retro Toolbox; with the
   access on there, a `path` launch opens the game.
9. **Wizard, Emulators.** Settings > Library > Launcher mode > Set up. Step 1
   lists the installed emulators with their version, "not tested" beside
   each unverified one. Uninstall one, press Detect again: it is gone. With
   none installed, it names up to three to install.
10. **Wizard, Systems.** One row per console whose folder holds a game, none
    for the others; each starts on the first emulator the preset file lists.
    A RetroArch row has a core row under it and says to install the core.
    With the library left in the app's own `Android/data` folder, a row
    warns "Other apps cannot read this folder".
11. **Wizard, Folder access.** Pick a `saf` emulator (PPSSPP, Flycast): the
    Folder access step names it and its folder; "Open <emulator>" opens it.
    Give the folder inside the emulator, then Play opens a game. With only
    `path` and `provider` emulators picked, the step is not there.
12. **Wizard, Finish.** Finish turns the mode on. Play on a game of a set up
    console starts its emulator without asking, also after an app restart,
    and the restart does not detect again first. B on step 1 leaves without
    turning anything on. With no game in any console folder, Systems says
    so, Next stays on, and Finish turns the mode on with no console set up.
13. **Resume.** With the mode on, uninstall an emulator from system Settings
    and come back to the app: Open with no longer lists it.
14. **Mode off, new emulator.** With the mode off and a detection saved
    (open a game's page once), install an emulator for a console that had
    none and restart the app: Play still reads "No emulator for <system>".
    Press Detect again beside it: Play comes on and opens the game.
15. **Grid launch.** With the mode on, open a set up console: the list shows
    only the games on disk (the Owned button is lit), each with a play
    badge. A, a tap and Start with nothing selected start the game; Y and a
    long press open its page; Back from the emulator lands on the same
    list. With the second screen open, the first tap shows the game there
    and the second starts it.
16. **Loose files.** Copy a ROM the catalog does not list (a hack, a
    homebrew `.zip`, a `.chd` with a name of your own) into a console's
    folder, then come back to the app: the owned view lists it by its file
    name, with no Download, and A starts it. A cue with its bin tracks, and
    a set of discs with its `.m3u`, each show as one game.
17. **Empty or failed catalog.** In airplane mode, open a console that has
    loose games: they show instead of the error. With nothing in the folder,
    the error shows as before.
18. **Unreadable folder.** Point a console at a folder Retro Toolbox cannot
    list (on desktop, `chmod 000`): the console page says "Cannot read
    <folder>".
19. **Console list.** With the mode on, the console list shows only the
    consoles whose folder holds a game; the Owned button in its header shows
    them all again.

## Home screen (Android)

Dart cannot run any of this: the tests pin what Dart sends over
`retro_toolbox/launcher` (`isHomeHeld`, `setHome`, the `home` call back), and
only a device shows what Android does with it. Note the Android version and
the device on each item. A debug build is `name.rafaismy.retrotoolbox.dev`, a
separate app from the release one.

20. **Launcher icon after the update.** The icon now names
    ExternalEntryActivity, so a home screen shortcut made before this build
    may be gone or need adding again. The icon, Settings > Apps > Retro
    Toolbox > Open and a tap on a download notification each open the app
    where it was, with no blank screen and no second Retro Toolbox in
    recents.
21. **HOME on, in the wizard.** Settings > Launcher mode > Set up: a Home
    screen step comes before Done. Turn the switch on and Finish: Android
    asks which app is the home app (the role dialog on Android 10 and
    later). Pick Retro Toolbox: the app stays where it was, Settings >
    Launcher mode shows the switch on, and recents holds one Retro Toolbox.
22. **Home button.** From a game's details page, press Home: the console
    list shows, with nothing above it. From the main menu, press Home: the
    console list opens.
23. **App drawer.** The console list ends with an Apps tile. It lists every
    app with an icon, by name; choosing one opens it, and Home comes back to
    the console list.
24. **HOME off.** Turn the switch off in Settings > Launcher mode: Android
    goes back to the previous home app, or asks which one. Turning launcher
    mode off does the same.
25. **HOME on mid-session.** Start a download, then turn HOME on in Settings
    and press Home: recents holds one Retro Toolbox, and the download goes on
    in the Task Manager without starting over.
26. **Notification in HOME mode.** With HOME on and a download running, tap
    its notification: the app shows as it was, the download goes on, and
    recents still holds one Retro Toolbox (no second engine started).
27. **B on the root.** With HOME on and a download running, press B (or
    Back) on the main menu until nothing is left to close: the app stays,
    and the download goes on.
28. **Below Android 10, and with no home role.** On Android 9 or older, and
    on a build without the home role (a TV box): turning HOME on opens the
    system's home app settings instead of a dialog. Pick Retro Toolbox and
    come back: the switch is on. Come back without picking it: the switch is
    off.
29. **Another home app picked outside.** With HOME on, pick another home app
    in system Settings, then come back to Retro Toolbox: the switch reads
    off.
30. **HOME off mid-session.** With HOME on, start a download, then turn the
    switch off in Settings > Launcher mode: the app stays on that page and
    the download goes on. Press Home (Android goes to another home app or
    asks), then tap the Retro Toolbox icon: the app shows as it was, recents
    holds one Retro Toolbox, and the download goes on in the Task Manager
    without starting over. Do it all again turning launcher mode off instead
    of the switch.
31. **Another home app picked, then the icon.** With HOME on and a download
    running, pick another home app in system Settings, then tap the Retro
    Toolbox icon: the app shows as it was, recents holds one Retro Toolbox,
    and the download goes on without starting over. Do it again tapping the
    download notification instead of the icon.
32. **Another home app, the icon, then Retro Toolbox again.** With HOME on
    and a download running, pick another home app in system Settings and tap
    the Retro Toolbox icon. Pick Retro Toolbox again in system Settings, then
    press Home: the app shows as it was, recents holds one Retro Toolbox, and
    the download goes on without starting over. Do it again tapping the icon
    instead of pressing Home.
33. **Ask every time, below Android 10.** On Android 9 or older with HOME on,
    install another app with a home screen, so Android asks which home app
    to use. Start a download, press Home and pick Retro Toolbox just once:
    the app stays where it was. Press Home and pick it just once again, and
    press B on the main menu until nothing is left to close: recents holds
    one Retro Toolbox, and the download goes on without starting over.
34. **JDKV notification in HOME mode.** With HOME on and the JDKV server
    running, open another app and tap the server's notification: Retro
    Toolbox opens on the JDKV screen. Do it again with HOME on but another
    home app picked in system Settings and Retro Toolbox in the background.
35. **Dual screen.** On a dual screen device: with Main on bottom, the Home
    screen switch is off and says why, in the wizard and in Settings; with
    HOME on, the dual screen card's Main on bottom is off and says why. With
    Main on top and HOME on, the companion opens on the other screen, closes
    when an emulator starts and opens again on the way back.

## One row per Android preset

For each preset: install the emulator, launch one single-file game and one
multi-file game (cue/bin, gdi or m3u) when the system has them. Write pass or
fail, the Android version, and the mode the launch used (the Mode column, or
the scoped one when the emulator has no all files access).

| Preset | Systems | Mode | Single file | Multi-file | Notes |
|---|---|---|---|---|---|
| `retroarch` | nes, snes, gb, gbc, gba, nds, 3ds, n64, gamecube, wii, psx, ps2, psp, genesis, saturn, dreamcast, arcade | path (scoped: saf) | | | |
| `duckstation` | psx | path (scoped: saf) | | | |
| `epsxe` | psx | path | | | |
| `fpse` | psx | provider | | | |
| `nethersx2` | ps2 | saf | | | |
| `play` | ps2 | saf | | | |
| `ppsspp` | psp | saf | | | |
| `dolphin` | gamecube, wii | provider (multi-file: provider) | | | |
| `dolphin-mmjr` | gamecube, wii | path (scoped: saf) | | | |
| `eden` | switch | provider | | | |
| `kenjinx` | switch | saf | | | |
| `skyline` | switch | saf | | | |
| `azahar` | 3ds | provider | | | |
| `citra` | 3ds | provider | | | |
| `mandarine` | 3ds | provider | | | |
| `panda3ds` | 3ds | provider | | | |
| `melonds` | nds | provider | | | |
| `melonds-nightly` | nds | provider | | | |
| `drastic` | nds | saf | | | |
| `noods` | nds | path | | | |
| `m64plus-fz` | n64 | saf | | | |
| `mupen64plus-ae` | n64 | saf | | | |
| `nes-emu` | nes | provider | | | |
| `snes9x-ex` | snes | provider | | | |
| `gbc-emu` | gb, gbc | provider | | | |
| `gba-emu` | gba | provider | | | |
| `md-emu` | genesis | provider | | | |
| `saturn-emu` | saturn | saf | | | |
| `pizza-boy-gbc` | gb, gbc | saf | | | |
| `pizza-boy-sc` | genesis | saf | | | |
| `skyemu` | gb, gbc, gba | saf | | | |
| `linkboy` | gb, gbc | saf | | | |
| `my-boy` | gba | saf | | | |
| `yaba-sanshiro-2` | saturn | saf | | | |
| `flycast` | dreamcast | saf | | | |
| `redream` | dreamcast | saf | | | |
| `mame4droid-2024` | arcade | provider | | | |
| `mame4droid` | arcade | provider | | | |

## Desktop

One OS per desktop preset is enough: install the emulator the way its find
rules expect (on PATH, a flatpak, an AppImage in `~/Applications`, an `.app`
in `/Applications`, the Windows installer), press Play on a game, and note
the OS and pass or fail. Then quit the emulator right away with a missing
BIOS or a bad file: the page shows "<emulator> closed right away" with the
end of its error output.

Desktop presets: `retroarch`, `duckstation`, `pcsx2`, `ppsspp`, `dolphin`, `azahar`, `melonds`, `flycast`, `cemu`.
