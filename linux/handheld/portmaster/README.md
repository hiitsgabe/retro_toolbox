## Notes

Retro Toolbox is open source (MIT): https://github.com/hiitsgabe/retro_toolbox

Thanks to ardera for [flutter-pi](https://github.com/ardera/flutter-pi), to rafaismyname for the framebuffer patch, to the Flutter team, and to the authors of the bundled libraries (see `retrotoolbox/licenses/`).

The app runs on flutter-pi straight on DRM/KMS, or on the framebuffer where DRM is missing. Everything it writes stays inside `ports/retrotoolbox/`; the launcher output goes to `ports/retrotoolbox/log.txt`.

The Games Library and downloads are off by default. Turn them on in Settings. Only download games you legally own, from your own sources.

The Tools tab also has Console Info (device info) and Download from link (type, paste or send a link from your phone; you confirm on the device before anything downloads).

## Controls

| Button | Action |
|--|--|
| D-pad | Move focus |
| A | Open / confirm |
| B | Back / close |
| X | Mark / unmark |
| Y | Actions for the focused item |
| Start | The screen's primary action |
| Select | Task manager (screen options where a screen has them) |
| L1 / R1 | Page up / page down |
| L2 / R2 | Top / bottom of the list |
| Select + Start | Quit |

## Compile

Built by the `Build Linux Handheld (PortMaster)` workflow in the repository (`.github/workflows/handheld.yml`): Flutter Linux arm64 release bundle, flutter-pi, and the flutter-pi engine binaries.
