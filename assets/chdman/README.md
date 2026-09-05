# Bundled chdman

CHD conversion (the **CHD Converter** tool) runs `chdman`, the MAME disc-image
tool (BSD-3-Clause, redistributable). How it's shipped per platform:

| Platform | Source | Where it lives |
|----------|--------|----------------|
| macOS    | Homebrew `rom-tools`, committed | `assets/chdman/macos/` |
| Linux    | built in release CI (`mame-tools`) | `assets/chdman/linux/` |
| Windows  | built in release CI (Chocolatey `mame`) | `assets/chdman/windows/` |
| Android  | **drop-in** (see below) | `android/app/src/main/jniLibs/<abi>/libchdman.so` |

## Desktop layout (macOS / Linux / Windows)

Each `<os>` folder has a `manifest.txt` listing the files to extract — the
binary (`chdman` / `chdman.exe`) first, then any bundled shared libraries. At
runtime `ChdService` copies them into the app support dir (libs load via
`@loader_path` on macOS / `$ORIGIN` on Linux, so they sit next to the binary)
and runs the binary. The Linux and Windows folders ship empty (`.gitkeep`) in
git; the release workflow fills them on each build.

Resolution order on desktop: user-set path → bundled folder → system `PATH`.

## Android

Android forbids executing binaries from writable app dirs, so chdman is shipped
as a **jniLib** named `libchdman.so` and run from the read-only
`nativeLibraryDir`. See `android/app/src/main/jniLibs/README.md`. Drop a
position-independent chdman built with the Android NDK for each ABI (the
[CHDroid](https://github.com/Ottavio97/CHDroid) project has a working recipe).
`ChdService` finds it via the `retrotoolbox/native` method channel.

## Verifying / updating a binary

Only ship binaries from a trusted source (a distro/Homebrew/Chocolatey package,
or your own build). The macOS binary here came from Homebrew `rom-tools`
(mamedev.org), with its dylib closure rewritten to `@loader_path` and ad-hoc
signed.
