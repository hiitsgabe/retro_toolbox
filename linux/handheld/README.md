# Retro Toolbox — Linux Handheld (PortMaster)

Flutter-based app for Linux ARM64 handheld devices via PortMaster + flutter-pi.

## Installation

1. Ensure PortMaster is installed on your device.
2. Copy `Retro Toolbox.sh` to `ports/` folder.
3. Copy the `retrotoolbox/` folder (containing flutter-pi binary, engine, data/flutter_assets, bundled_libs, etc.) into `ports/`.
4. Run `Retro Toolbox.sh` from your device's port launcher.

## Layout

```
ports/
  Retro Toolbox.sh
  retrotoolbox/
    flutter-pi              # flutter-pi binary
    data/
      flutter_assets/       # Flutter engine assets
    lib/                    # Runtime libraries
    bundled_libs/           # Fallback system libraries
    runtime_libs/           # System library overrides (created at runtime)
    config/                 # XDG config dir (runtime)
    cache/                  # XDG cache dir (runtime)
    data/home/              # XDG data home (runtime)
    Documents/              # Standard user folder (created at runtime)
    Downloads/              # Standard user folder (created at runtime)
    log.txt                 # launcher output
```

## Runtime Env

The launcher exports:
- `RETRO_TOOLBOX_HANDHELD=1`: Detected handheld mode
- `RETRO_TOOLBOX_FBDEV=1`: Framebuffer display (when DRM/KMS unavailable)

The app reads these to adapt UI and input handling.

## Display Modes

- **DRM/KMS** (preferred): Direct rendering to discrete display. Detected via `/dev/dri/card*`.
- **Framebuffer**: Fallback on systems without KMS support. Passes `--fbdev` to flutter-pi.

## Physical Dimensions

Adjust display pixel ratio via `RT_DISPLAY_MM` env var (format: `width,height` in mm; default: `71,53` for ~3.5" screens):

```bash
export RT_DISPLAY_MM="80,60"
```

## Logs

Runtime output written to `ports/retrotoolbox/log.txt`.

## Input

Key map in `retrotoolbox.gptk`:
- D-pad: Arrow keys
- A button: Enter
- B button: Escape
- X button: Space
- Y button: Tab
- L1/R1: PageUp / PageDown
- L2/R2: Home / End
- Start: Enter
- Back: Escape

Handled by gptokeyb (included in PortMaster).

## Flutter-Pi Framebuffer Patch

The bundled `flutter-pi-fbdev.patch` enables framebuffer rendering when DRM/KMS is unavailable. Patch origin: [rafaismyname](https://github.com/rafaismyname).

**Pin:** ardera/flutter-pi @ `c81869e033cd5b4c819c620e9124114a559b2067`

To apply to a flutter-pi source tree:
```bash
git clone https://github.com/ardera/flutter-pi.git
cd flutter-pi
git checkout c81869e033cd5b4c819c620e9124114a559b2067
patch -p1 -l < ../path/to/flutter-pi-fbdev.patch
```

Adjust the path to `flutter-pi-fbdev.patch` relative to the flutter-pi working directory.
