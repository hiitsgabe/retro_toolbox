import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/app_style.dart';

/// The app's areas, each with its own colour in the area palette (Classic
/// paints its menu tiles with them).
enum AppArea { games, saves, servers, tools, sports, settings, info, tasks }

/// How a style draws keyboard/gamepad focus. Data only: the widgets that draw
/// focus read it.
@immutable
class FocusLook {
  const FocusLook({required this.color, this.color2, this.width = 3, this.gap = 0, this.glow = false, this.zoom = 1, this.lift = false, this.pulse = false});

  final Color color;

  /// The second colour of an animated two-colour frame (Switch).
  final Color? color2;

  /// Ring or border width, and the gap between it and the focused widget.
  final double width;
  final double gap;
  final bool glow;

  /// Scale of the focused widget (1 = none).
  final double zoom;

  /// The focused widget rises (Classic cartridges).
  final bool lift;

  /// The border breathes (3DS).
  final bool pulse;

  bool get animated => pulse || color2 != null;

  static FocusLook lerp(FocusLook a, FocusLook b, double t) {
    final pick = t < 0.5 ? a : b;
    return FocusLook(
      color: Color.lerp(a.color, b.color, t)!,
      color2: pick.color2,
      width: lerpDouble(a.width, b.width, t)!,
      gap: lerpDouble(a.gap, b.gap, t)!,
      glow: pick.glow,
      zoom: lerpDouble(a.zoom, b.zoom, t)!,
      lift: pick.lift,
      pulse: pick.pulse,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FocusLook &&
      other.color == color &&
      other.color2 == color2 &&
      other.width == width &&
      other.gap == gap &&
      other.glow == glow &&
      other.zoom == zoom &&
      other.lift == lift &&
      other.pulse == pulse;

  @override
  int get hashCode => Object.hash(color, color2, width, gap, glow, zoom, lift, pulse);
}

/// Where and how a style marks a selected game.
enum SelectedMarker {
  /// Check badge in a corner plus an inner border (Classic).
  badgeAndBorder,

  /// Dashed ring round the card plus a check (Vita).
  dashedRing,

  /// Folded corner with a check (3DS).
  foldedCorner,

  /// The card tints and a pill shows under it (Wii).
  tintAndPill,

  /// Check in a corner plus a bar along the bottom (Switch).
  checkAndBar,
}

@immutable
class SelectedLook {
  const SelectedLook({required this.marker, required this.color, required this.onColor, required this.corner, this.border = 0, this.bar = 0});

  final SelectedMarker marker;
  final Color color;

  /// The check glyph on [color].
  final Color onColor;

  /// Where the check sits.
  final Alignment corner;

  /// Inner border width (0 = none).
  final double border;

  /// Bottom bar height (0 = none).
  final double bar;

  SelectedLook copyWithColor(Color color, Color onColor) =>
      SelectedLook(marker: marker, color: color, onColor: onColor, corner: corner, border: border, bar: bar);

  static SelectedLook lerp(SelectedLook a, SelectedLook b, double t) {
    final pick = t < 0.5 ? a : b;
    return SelectedLook(
      marker: pick.marker,
      color: Color.lerp(a.color, b.color, t)!,
      onColor: Color.lerp(a.onColor, b.onColor, t)!,
      corner: pick.corner,
      border: lerpDouble(a.border, b.border, t)!,
      bar: lerpDouble(a.bar, b.bar, t)!,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SelectedLook &&
      other.marker == marker &&
      other.color == color &&
      other.onColor == onColor &&
      other.corner == corner &&
      other.border == border &&
      other.bar == bar;

  @override
  int get hashCode => Object.hash(marker, color, onColor, corner, border, bar);
}

/// What a card style says about colour, shape and focus for the whole app.
/// Screens read these instead of asking which style is active.
@immutable
class StyleTokens extends ThemeExtension<StyleTokens> {
  const StyleTokens({
    required this.accent,
    required this.onAccent,
    required this.surface,
    required this.panel,
    required this.panelLine,
    required this.cardRadius,
    required this.panelRadius,
    required this.buttonRadius,
    required this.focus,
    required this.selected,
    required this.backdrop,
    this.success = const Color(0xFF5EE3A1),
    this.warning = const Color(0xFFFFB547),
    this.error = const Color(0xFFFF6B81),
    this.areas = areaPalette,
    this.titleFont = displayFont,
    this.pixelIcons = false,
    this.areaAccent = false,
    this.titleCaps = false,
  });

  /// Body text in every style: made for reading on small screens.
  static const bodyFont = 'AtkinsonHyperlegible';

  /// The app name and numbers.
  static const displayFont = 'ChakraPetch';

  final Color accent;
  final Color onAccent;

  /// What is behind the panels (the scaffold until the backdrop shows there).
  final Color surface;

  /// The material of cards, sheets and dialogs, and its edge.
  final Color panel;
  final Color panelLine;

  /// 99 reads as a pill.
  final double cardRadius;
  final double panelRadius;
  final double buttonRadius;

  final Color success;
  final Color warning;
  final Color error;

  final Map<AppArea, Color> areas;

  /// Titles and labels.
  final String titleFont;

  /// Icons from the pixel set (PixelIcons) where a screen has one.
  final bool pixelIcons;

  /// A screen that belongs to an app area takes the area's colour as its
  /// accent ([inArea]).
  final bool areaAccent;

  /// Screen titles in capitals.
  final bool titleCaps;
  final FocusLook focus;
  final SelectedLook selected;

  /// What is behind every screen: the style's own until one is picked in
  /// Style (appTheme puts the picked one here).
  final BackdropStyle backdrop;

  static const areaPalette = <AppArea, Color>{
    AppArea.games: Color(0xFFE8443A),
    AppArea.saves: Color(0xFFF2B632),
    AppArea.servers: Color(0xFF2FB7A6),
    AppArea.tools: Color(0xFF4A7BF0),
    AppArea.sports: Color(0xFF8BC34A),
    AppArea.settings: Color(0xFFA98BD9),
    AppArea.info: Color(0xFF7FC8FF),
    AppArea.tasks: Color(0xFFFF8A3D),
  };

  Color area(AppArea a) => areas[a]!;

  /// The tokens for a screen of [a]: the area's colour as the accent where
  /// the style says so, else these.
  StyleTokens inArea(AppArea? a) {
    if (a == null || !areaAccent) return this;
    final c = area(a);
    // Dark ink on the light area colours, white on the deep ones.
    final ink = c.computeLuminance() > 0.3 ? Color.lerp(c, const Color(0xFF000000), 0.82)! : const Color(0xFFFFFFFF);
    return copyWith(accent: c, onAccent: ink, panelLine: c.withValues(alpha: 0.16), selected: selected.copyWithColor(c, ink));
  }

  /// [panel] laid on [surface]: for sheets and dialogs, which cover content
  /// and cannot be see-through.
  Color get solidPanel => Color.alphaBlend(panel, surface);

  /// [panel] for bars that sit on the backdrop all the time (the game list's
  /// header and footer): never more than 85% opaque, so the backdrop shows
  /// through in the styles whose panel is solid too.
  Color get bar => panel.a <= 0.85 ? panel : panel.withValues(alpha: 0.85);

  static const classic = StyleTokens(
    accent: Color(0xFFB8A1FF),
    onAccent: Color(0xFF1D0F4A),
    surface: Color(0xFF1B1830),
    panel: Color(0xB81E163A),
    panelLine: Color(0x29B8A1FF),
    cardRadius: 8,
    panelRadius: 12,
    buttonRadius: 4,
    focus: FocusLook(color: Color(0xFFFFFFFF), lift: true),
    selected: SelectedLook(marker: SelectedMarker.badgeAndBorder, color: Color(0xFFB8A1FF), onColor: Color(0xFF1D0F4A), corner: Alignment.topLeft, border: 2),
    // In the Retro Toolbox colours, so Style shows that swatch as the one picked.
    backdrop: BackdropStyle(kind: BackdropKind.dots, top: Color(0xFF7C4DEF), bottom: Color(0xFF17102B)),
    titleFont: 'SairaCondensed',
    pixelIcons: true,
    areaAccent: true,
    titleCaps: true,
  );

  static const vita = StyleTokens(
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF1B3A6B),
    surface: Color(0xFF0F1A33),
    panel: Color(0x1AFFFFFF),
    panelLine: Color(0x2EFFFFFF),
    cardRadius: 20,
    panelRadius: 20,
    buttonRadius: 99,
    focus: FocusLook(color: Color(0xFFFFFFFF), width: 0, glow: true, zoom: 1.08),
    // Bottom right: the state badges hold the top right of the bubble.
    selected: SelectedLook(marker: SelectedMarker.dashedRing, color: Color(0xFFFFFFFF), onColor: Color(0xFF1B3A6B), corner: Alignment.bottomRight, border: 2),
    backdrop: BackdropStyle(top: Color(0xFF3B78D8), bottom: Color(0xFF0F1A33)),
  );

  static const threeDs = StyleTokens(
    accent: Color(0xFF3FC7F0),
    onAccent: Color(0xFF04232A),
    surface: Color(0xFF2A2D33),
    panel: Color(0xFF33373F),
    panelLine: Color(0x383FC7F0),
    cardRadius: 6,
    panelRadius: 6,
    buttonRadius: 6,
    focus: FocusLook(color: Color(0xFF3FC7F0), pulse: true),
    selected: SelectedLook(marker: SelectedMarker.foldedCorner, color: Color(0xFF3FC7F0), onColor: Color(0xFF04232A), corner: Alignment.topRight),
    backdrop: BackdropStyle(top: Color(0xFF4A4F58), bottom: Color(0xFF2A2D33)),
  );

  static const wii = StyleTokens(
    accent: Color(0xFF34BEED),
    // Dark ink: white on Wii blue is about 2.2:1, too faint for a label.
    onAccent: Color(0xFF06283A),
    surface: Color(0xFF1F2A33),
    panel: Color(0x1FF2F4F6),
    panelLine: Color(0x4DD3D8DE),
    cardRadius: 12,
    panelRadius: 14,
    buttonRadius: 99,
    focus: FocusLook(color: Color(0xFF34BEED), glow: true),
    selected: SelectedLook(marker: SelectedMarker.tintAndPill, color: Color(0xFF34BEED), onColor: Color(0xFF06283A), corner: Alignment.bottomCenter),
    backdrop: BackdropStyle(top: Color(0xFFF2F4F6), bottom: Color(0xFF1F2A33)),
  );

  static const switchStyle = StyleTokens(
    accent: Color(0xFF00C3E3),
    onAccent: Color(0xFF04232A),
    surface: Color(0xFF15171A),
    panel: Color(0xFF282B30),
    panelLine: Color(0x14FFFFFF),
    cardRadius: 4,
    panelRadius: 8,
    buttonRadius: 8,
    focus: FocusLook(color: Color(0xFF00C3E3), color2: Color(0xFF2E7DFF), gap: 4),
    selected: SelectedLook(marker: SelectedMarker.checkAndBar, color: Color(0xFF00C3E3), onColor: Color(0xFF04232A), corner: Alignment.topRight, bar: 4),
    backdrop: BackdropStyle(top: Color(0xFF3A3D42), bottom: Color(0xFF15171A)),
  );

  static StyleTokens forStyle(CardStyle style) => switch (style) {
        CardStyle.classic => classic,
        CardStyle.vita => vita,
        CardStyle.threeDs => threeDs,
        CardStyle.wii => wii,
        CardStyle.switchStyle => switchStyle,
      };

  /// The active style's tokens; Classic where no app theme is up (bare test
  /// apps).
  static StyleTokens of(BuildContext context) => Theme.of(context).extension<StyleTokens>() ?? classic;

  @override
  StyleTokens copyWith({
    Color? accent,
    Color? onAccent,
    Color? surface,
    Color? panel,
    Color? panelLine,
    double? cardRadius,
    double? panelRadius,
    double? buttonRadius,
    Color? success,
    Color? warning,
    Color? error,
    Map<AppArea, Color>? areas,
    String? titleFont,
    bool? pixelIcons,
    bool? areaAccent,
    bool? titleCaps,
    FocusLook? focus,
    SelectedLook? selected,
    BackdropStyle? backdrop,
  }) =>
      StyleTokens(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        surface: surface ?? this.surface,
        panel: panel ?? this.panel,
        panelLine: panelLine ?? this.panelLine,
        cardRadius: cardRadius ?? this.cardRadius,
        panelRadius: panelRadius ?? this.panelRadius,
        buttonRadius: buttonRadius ?? this.buttonRadius,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        error: error ?? this.error,
        areas: areas ?? this.areas,
        titleFont: titleFont ?? this.titleFont,
        pixelIcons: pixelIcons ?? this.pixelIcons,
        areaAccent: areaAccent ?? this.areaAccent,
        titleCaps: titleCaps ?? this.titleCaps,
        focus: focus ?? this.focus,
        selected: selected ?? this.selected,
        backdrop: backdrop ?? this.backdrop,
      );

  @override
  bool operator ==(Object other) =>
      other is StyleTokens &&
      other.accent == accent &&
      other.onAccent == onAccent &&
      other.surface == surface &&
      other.panel == panel &&
      other.panelLine == panelLine &&
      other.cardRadius == cardRadius &&
      other.panelRadius == panelRadius &&
      other.buttonRadius == buttonRadius &&
      other.success == success &&
      other.warning == warning &&
      other.error == error &&
      mapEquals(other.areas, areas) &&
      other.titleFont == titleFont &&
      other.pixelIcons == pixelIcons &&
      other.areaAccent == areaAccent &&
      other.titleCaps == titleCaps &&
      other.focus == focus &&
      other.selected == selected &&
      other.backdrop == backdrop;

  @override
  int get hashCode => Object.hash(
        accent,
        onAccent,
        surface,
        panel,
        panelLine,
        cardRadius,
        panelRadius,
        buttonRadius,
        success,
        warning,
        error,
        Object.hashAll(areas.values),
        titleFont,
        pixelIcons,
        areaAccent,
        titleCaps,
        focus,
        selected,
        backdrop,
      );

  @override
  StyleTokens lerp(StyleTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => lerpDouble(a, b, t)!;
    return StyleTokens(
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      surface: c(surface, other.surface),
      panel: c(panel, other.panel),
      panelLine: c(panelLine, other.panelLine),
      cardRadius: d(cardRadius, other.cardRadius),
      panelRadius: d(panelRadius, other.panelRadius),
      buttonRadius: d(buttonRadius, other.buttonRadius),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      error: c(error, other.error),
      areas: {for (final a in AppArea.values) a: c(area(a), other.area(a))},
      titleFont: t < 0.5 ? titleFont : other.titleFont,
      pixelIcons: t < 0.5 ? pixelIcons : other.pixelIcons,
      areaAccent: t < 0.5 ? areaAccent : other.areaAccent,
      titleCaps: t < 0.5 ? titleCaps : other.titleCaps,
      focus: FocusLook.lerp(focus, other.focus, t),
      selected: SelectedLook.lerp(selected, other.selected, t),
      backdrop: t < 0.5 ? backdrop : other.backdrop,
    );
  }
}

extension ShownBackdrop on AppStyle {
  /// The backdrop on screen: the picked one, else the card style's own.
  BackdropStyle get shownBackdrop => backdrop ?? StyleTokens.forStyle(cards).backdrop;
}
