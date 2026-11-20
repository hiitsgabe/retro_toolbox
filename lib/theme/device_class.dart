import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:retro_toolbox/utils/handheld.dart';

/// The kinds of screen the menus and grids size for. The reference devices:
/// Odin 2 (731x411) is [landscapeLow], a phone (412x915) [portrait], the Linux
/// handheld (640x480 at dpr 1) [pixel].
enum DeviceClass {
  /// Landscape and at most 480 logical px tall.
  landscapeLow,

  /// A phone held upright.
  portrait,

  /// Few, large pixels: the framebuffer handheld build, or dpr 1 with the
  /// shortest side at most 480.
  pixel,

  /// Everything else: tablets, desktops, TVs.
  roomy;

  static DeviceClass from(Size size, double devicePixelRatio, {bool framebuffer = false}) {
    final shortest = size.shortestSide;
    if (framebuffer || (devicePixelRatio <= 1 && shortest <= 480)) return pixel;
    // A tablet held upright has room for the wide layouts.
    if (size.height > size.width) return shortest < 600 ? portrait : roomy;
    if (size.height <= 480) return landscapeLow;
    return roomy;
  }

  static DeviceClass of(BuildContext context) =>
      from(MediaQuery.sizeOf(context), MediaQuery.devicePixelRatioOf(context), framebuffer: Handheld.framebuffer);

  /// No theme text style goes below this.
  double get textFloor => this == pixel ? 13 : 12;

  /// Columns of the game grids, or null to size them by width.
  int? gameColumns(double width) => switch (this) {
        landscapeLow => width >= 700 ? 6 : 5,
        portrait => 3,
        pixel => 4,
        roomy => null,
      };

  /// How [count] menu tiles fit this class: [MenuFit.columns] across and
  /// [MenuFit.rows] on screen at once (the rest scrolls). Null for [roomy],
  /// which keeps each style's own layout.
  MenuFit? menuFit(int count) {
    final n = math.max(count, 1);
    int rows(int columns, int most) => math.min((n / columns).ceil(), most);
    return switch (this) {
      landscapeLow => n <= 6 ? MenuFit(n, 1) : (n <= 12 ? MenuFit((n / 2).ceil(), 2) : const MenuFit(6, 2)),
      portrait => MenuFit(2, rows(2, 5)),
      pixel => MenuFit(3, rows(3, 3)),
      roomy => null,
    };
  }
}

/// A menu's grid on a device class: [columns] across, [rows] on screen.
@immutable
class MenuFit {
  const MenuFit(this.columns, this.rows);

  final int columns;
  final int rows;

  /// The cell for [columns] by [rows] in [area] with [gap] between cells.
  Size cell(Size area, {double gap = 0}) =>
      Size(math.max(0, (area.width - (columns - 1) * gap) / columns), math.max(0, (area.height - (rows - 1) * gap) / rows));

  @override
  bool operator ==(Object other) => other is MenuFit && other.columns == columns && other.rows == rows;

  @override
  int get hashCode => Object.hash(columns, rows);

  @override
  String toString() => 'MenuFit($columns x $rows)';
}

/// The largest cells of [aspect] (width over height) that hold [count] tiles
/// in [area] without scrolling, over the column counts in [columns]; null
/// when none is at least [minWidth] wide.
({int columns, Size cell})? largestFit(int count, Size area, Iterable<int> columns, {required double aspect, double gap = 0, double minWidth = 0}) {
  final n = math.max(count, 1);
  ({int columns, Size cell})? best;
  for (final c in columns) {
    if (c < 1) continue;
    final rows = (n / c).ceil();
    final w = math.min((area.width - (c - 1) * gap) / c, (area.height - (rows - 1) * gap) / rows * aspect);
    if (w >= minWidth && (best == null || w > best.cell.width)) best = (columns: c, cell: Size(w, w / aspect));
  }
  return best;
}

/// [theme] with no text style under the device class's floor.
ThemeData withTextFloor(ThemeData theme, double floor) {
  TextTheme up(TextTheme t) => t.merge(TextTheme(
        displayLarge: _floor(t.displayLarge, floor),
        displayMedium: _floor(t.displayMedium, floor),
        displaySmall: _floor(t.displaySmall, floor),
        headlineLarge: _floor(t.headlineLarge, floor),
        headlineMedium: _floor(t.headlineMedium, floor),
        headlineSmall: _floor(t.headlineSmall, floor),
        titleLarge: _floor(t.titleLarge, floor),
        titleMedium: _floor(t.titleMedium, floor),
        titleSmall: _floor(t.titleSmall, floor),
        bodyLarge: _floor(t.bodyLarge, floor),
        bodyMedium: _floor(t.bodyMedium, floor),
        bodySmall: _floor(t.bodySmall, floor),
        labelLarge: _floor(t.labelLarge, floor),
        labelMedium: _floor(t.labelMedium, floor),
        labelSmall: _floor(t.labelSmall, floor),
      ));
  return theme.copyWith(textTheme: up(theme.textTheme), primaryTextTheme: up(theme.primaryTextTheme));
}

TextStyle? _floor(TextStyle? s, double floor) {
  final size = s?.fontSize;
  return size == null || size >= floor ? null : TextStyle(fontSize: floor);
}

/// The theme above with its text clamped to the device class's floor; goes
/// under MaterialApp (in its builder), where the screen size is known.
class TextFloor extends StatelessWidget {
  const TextFloor({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(data: withTextFloor(theme, DeviceClass.of(context).textFloor), child: child);
  }
}
