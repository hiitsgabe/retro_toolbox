import 'package:flutter/widgets.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/widgets/card_styles/wii.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// What a card style draws. Classic has none: its lists are today's widgets.
class CardStyleKit {
  const CardStyleKit({required this.menuList, required this.gameList});

  /// Menu tiles and console tiles. [shrinkWrap] as in MenuGrid (inside another scroll view).
  final Widget Function(BuildContext context, List<MenuTile> tiles, {required bool shrinkWrap, required bool autofocusFirst}) menuList;

  /// The game list body (HomeScreen), built from the catalog by StyledGameList.
  final Widget Function(BuildContext context) gameList;
}

/// Replaces [cardStyleKit] in tests: a fake kit without a real style.
@visibleForTesting
CardStyleKit? Function(CardStyle style)? debugCardStyleKitOverride;

CardStyleKit? cardStyleKit(CardStyle style) {
  if (debugCardStyleKitOverride case final override?) return override(style);
  return switch (style) {
    CardStyle.classic => null,
    CardStyle.vita => null, // Task 6
    CardStyle.threeDs => null, // Task 7
    CardStyle.wii => wiiKit(),
    CardStyle.switchStyle => null, // Task 9
  };
}
