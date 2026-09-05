# Bundled chdman binaries (optional)

CHD conversion (the **CHD Converter** tool) shells out to `chdman`, the MAME
disc-image tool. The app resolves it in this order:

1. A path the user set in the tool (**Select chdman binary**).
2. A binary bundled here, for the current platform (this folder).
3. `chdman` on the system `PATH` (Batocera, Knulli, and desktops with
   `mame-tools` usually have it).

Steps 1 and 3 work out of the box. Step 2 lets the app be self-contained on
platforms that have no system `chdman` — most importantly **Android**.

## How to enable a bundled binary

1. Obtain a **trusted** `chdman` built for the target platform/ABI. Verify it
   yourself — do not ship an unverified binary. `chdman` is part of MAME
   (BSD-3-Clause), so redistribution is allowed. The open-source
   [CHDroid](https://github.com/Ottavio97/CHDroid) project shows how the
   Android arm64 binary is built.
2. Drop it at `assets/chdman/<os>/chdman` (add `.exe` on Windows), where
   `<os>` is one of `android`, `macos`, `linux`, `windows` — matching
   `Platform.operatingSystem`.
3. Declare the folder in `pubspec.yaml` under `flutter: assets:` — e.g.
   `- assets/chdman/android/` — and rebuild.

At runtime `ChdService` copies the bundled binary into the app support
directory, marks it executable, and runs it. No code change is needed once the
binary and the `pubspec.yaml` line are in place.
