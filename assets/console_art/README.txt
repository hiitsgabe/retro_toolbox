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
- ps4/switch2 logos: official marks vectorized on Wikimedia Commons.
- xbox360 wordmark ("X Box 360 logo.svg"), the Xbox sphere ("Xbox one
  logo.svg") and ps5 ("PlayStation 5 logo and wordmark.svg"): Wikimedia
  Commons, public domain.
- xboxone wordmark: "Art Book Next" theme (as above), CC-BY-NC-SA.
- android_games/android_apps: drawn for this app (a gamepad or an app grid
  over block letters), no third-party mark.
- xboxseries: the XBOX letters of the xboxone wordmark plus "SERIES" set in
  Selawik Semilight (Microsoft, SIL OFL 1.1), converted to outlines.

All logos are drawn in one color by the app (white on the brand tile), so each
file was edited for that: backing boxes, (R) and TM marks and small taglines
removed, the PS2/PS3/PS4/PSP family given the same stroke weight and no PS
symbol, and the Xbox sphere added to both Xbox logos. Every file is cropped to
a square canvas sized so the logos read the same size (same area, at most the
full width and 45% of the height; Wii/Wii U, Game Boy, DS, PlayStation and
Xbox families share one letter height). A new logo needs the same treatment.
These are third-party trademarked marks bundled for personal use; review before
any commercial distribution.
