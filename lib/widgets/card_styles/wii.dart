import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_list.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_menu_card.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

const _wiiBlue = Color(0xFF34BEED);
const _frameGrey = Color(0xFFD3D8DE);
const _inset = 6.0;
const _bandHeight = 26.0;

/// The Wii style: white glossy channels in a grid, 4 columns (2 on narrow
/// screens), scrolling vertically.
CardStyleKit wiiKit() => CardStyleKit(
      menuList: _menuList,
      gameList: (context) => StyledGameList(
        card: (context, game, {required autofocus}) => _gameCard(game, autofocus),
        layout: (context, count, card, onNearEnd, controller) => _grid(
          key: const ValueKey('wii-games'),
          count: count,
          itemBuilder: card,
          controller: controller,
        ),
      ),
    );

Widget _menuList(BuildContext context, List<MenuTile> tiles, {required bool shrinkWrap, required bool autofocusFirst}) => _grid(
      key: const ValueKey('wii-menu'),
      count: tiles.length,
      shrinkWrap: shrinkWrap,
      itemBuilder: (context, i) => _menuCard(tiles[i], autofocusFirst && i == 0),
    );

Widget _grid({
  required Key key,
  required int count,
  required Widget Function(BuildContext, int) itemBuilder,
  ScrollController? controller,
  bool shrinkWrap = false,
}) =>
    LayoutBuilder(
      builder: (context, box) => GridView.builder(
        key: key,
        controller: controller,
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: box.maxWidth >= 800 ? 4 : 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 16 / 9,
        ),
        itemCount: count,
        itemBuilder: itemBuilder,
      ),
    );

// The channel draws its own focus (blue border and glow): no DpadScope
// outline over it.
Widget _menuCard(MenuTile tile, bool autofocus) => DpadOwnOutline(
      child: StyledMenuCard(
        key: ValueKey(tile.label),
        tile: tile,
        autofocus: autofocus,
        customBorder: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
        face: (context, focused) => _Channel(
          focused: focused,
          builder: (context, radius) => _MenuArt(tile: tile),
        ),
      ),
    );

Widget _gameCard(Game game, bool autofocus) => DpadOwnOutline(
      child: StyledGameCard(
        key: ValueKey('wii-${game.gameId}'),
        game: game,
        autofocus: autofocus,
        radius: 24,
        face: (context, state, selected, focused) => _Channel(
          focused: focused,
          selected: selected,
          builder: (context, radius) => _GameArt(game: game, badges: GameStateBadges(state: state)),
        ),
      ),
    );

/// The white glossy frame: a 16:9 rounded rectangle (radius 18% of its
/// height), a light grey border that turns blue under focus, its content
/// inset 6 px.
class _Channel extends StatelessWidget {
  const _Channel({required this.focused, required this.builder, this.selected});

  final bool focused;
  final Widget Function(BuildContext context, double radius) builder;

  /// A game's channel wears the selected mark (not null).
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final radius = box.maxHeight * 0.18;
      final channel = _channel(context, radius);
      return selected == null ? channel : SelectedMark(selected: selected!, radius: radius, size: (box.maxHeight * 0.14).clamp(18.0, 26.0), child: channel);
    });
  }

  Widget _channel(BuildContext context, double radius) {
    return AnimatedContainer(
      key: const ValueKey('wii-channel'),
      duration: const Duration(milliseconds: 120),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white, Color(0xFFEEF1F4)]),
        border: Border.all(color: focused ? _wiiBlue : _frameGrey, width: 3),
        boxShadow: [
          if (focused)
            BoxShadow(color: _wiiBlue.withValues(alpha: 0.55), blurRadius: 14)
          else
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(_inset),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 3 - _inset),
        child: builder(context, radius),
      ),
    );
  }
}

/// The glossy highlight over the top half of the art.
Widget _gloss() => Positioned.fill(
      child: FractionallySizedBox(
        heightFactor: 0.5,
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.white.withValues(alpha: 0.30), Colors.white.withValues(alpha: 0.04)]),
          ),
        ),
      ),
    );

/// The label on its white band, one line.
Widget _band(String text) => Container(
      height: _bandHeight,
      color: Colors.white,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF3A4048)),
      ),
    );

class _MenuArt extends StatelessWidget {
  const _MenuArt({required this.tile});

  final MenuTile tile;

  static bool _loadable(String? path) => path != null && (path.startsWith('assets/') || File(path).existsSync());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = tile.accentColor;
    final onAccent = accent != null;
    final logo = tile.brandLogo && _loadable(tile.assetPath);
    final hsl = accent == null ? null : HSLColor.fromColor(accent);
    final colors =
        hsl == null ? [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh] : [hsl.withLightness(0.52).toColor(), hsl.withLightness(0.30).toColor()];
    final fg = onAccent ? Colors.white : scheme.onSurface;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors))),
              if (_loadable(tile.bgAssetPath)) ...[
                _image(tile.bgAssetPath!, BoxFit.cover, null, const SizedBox()),
                DecoratedBox(decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35))),
              ],
              if (logo)
                // The logo's canvas is square with the ink on its middle band:
                // size it from the width and let the empty canvas spill past
                // the art box, the channel's clip trims it.
                LayoutBuilder(
                  builder: (context, box) {
                    final side = math.min(box.maxWidth * 0.86, box.maxHeight * 2.0);
                    return OverflowBox(
                      minWidth: side,
                      maxWidth: side,
                      minHeight: side,
                      maxHeight: side,
                      child: _content(fg, true),
                    );
                  },
                )
              else
                Padding(padding: const EdgeInsets.all(8), child: Center(child: _content(fg, false))),
              _gloss(),
            ],
          ),
        ),
        // The logo stands in for the label.
        if (!logo) _band(tile.label),
      ],
    );
  }

  Widget _content(Color fg, bool logo) {
    final icon = Icon(tile.icon, size: 40, color: fg);
    final path = tile.assetPath;
    if (!_loadable(path)) return icon;
    if (logo) return SizedBox.expand(child: _image(path!, BoxFit.contain, ColorFilter.mode(fg, BlendMode.srcIn), icon));
    return _image(path!, BoxFit.contain, null, icon);
  }

  Widget _image(String path, BoxFit fit, ColorFilter? tint, Widget fallback) {
    final asset = path.startsWith('assets/');
    if (path.toLowerCase().endsWith('.svg')) {
      return asset ? SvgPicture.asset(path, fit: fit, colorFilter: tint) : SvgPicture.file(File(path), fit: fit, colorFilter: tint);
    }
    return asset
        ? Image.asset(path, fit: fit, errorBuilder: (_, __, ___) => fallback)
        : Image.file(File(path), fit: fit, errorBuilder: (_, __, ___) => fallback);
  }
}

class _GameArt extends StatelessWidget {
  const _GameArt({required this.game, required this.badges});

  final Game game;
  final Widget badges;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.videogame_asset_outlined, color: scheme.outline));
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The art fills the channel (cover, the overflow cropped).
              SizedBox.expand(child: GameBoxart(game: game, fill: true, placeholder: placeholder)),
              _gloss(),
              Positioned(top: 4, left: 4, child: badges),
            ],
          ),
        ),
        _band(game.title),
      ],
    );
  }
}
