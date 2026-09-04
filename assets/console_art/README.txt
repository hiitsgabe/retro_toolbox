Console logos, pre-mapped in-app by platform slug (the catalog JSON has no art
data). The app resolves a console -> slug by keyword (see console_slug.dart),
then loads <slug>_logo.svg here. Missing files fall back to a generic icon.

To add art for another platform: drop <slug>_logo.svg and register the slug in
lib/widgets/menu_grid/console_slug.dart (_bundledLogos + a color).

Art credits / licenses (non-commercial use):
- Retro console logos: EmulationStation "Carbon" theme by Rookervik.
- switch/wiiu/3ds/ps3/xbox/xbox360 logos: "Art Book Next" theme by
  Anthony Caccese, licensed CC-BY-NC-SA
  (https://creativecommons.org/licenses/by-nc-sa/2.0/).
These are third-party trademarked marks bundled for personal use; review before
any commercial distribution.
