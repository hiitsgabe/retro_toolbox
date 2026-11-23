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
