import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_list.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_menu_card.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// The Switch HOME menu: flat squares, one row for menus and consoles, a grid
/// of squares for the games ("All software"). The focused card wears a frame
/// pulsing cyan to blue and shows its name above it.
const switchKit = CardStyleKit(menuList: switchMenuList, gameList: switchGameList);

const _cyan = Color(0xFF00C3E3);
const _blue = Color(0xFF2E7DFF);

/// Corner radius of a card. The art is the card: it fills it edge to edge.
const _radius = 6.0;

/// The frame's stroke and its gap to the card. The frame is drawn outside the
/// card, [_margin] beyond its edges, so the layouts space cards for it.
const _frameWidth = 4.0;
const _frameGap = 3.0;
const _margin = _frameWidth + _frameGap;
const _frameRadius = _radius + _margin;

/// The ink's shape: the card's.
final _cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));

/// Room the focused card keeps from the edges of its list when focus moves.
const _rowEdge = 48.0;
const _gridTop = _GameName.height + _margin + 8;
const _gridEdge = 32.0;

Widget switchMenuList(BuildContext context, List<MenuTile> tiles, {required bool shrinkWrap, required bool autofocusFirst}) =>
    SwitchMenuRow(tiles: tiles, shrinkWrap: shrinkWrap, autofocusFirst: autofocusFirst);

Widget switchGameList(BuildContext context) => StyledGameList(
      card: (context, game, {required autofocus}) => DpadOwnOutline(
        child: Builder(
          builder: (card) => StyledGameCard(
            game: game,
            autofocus: autofocus,
            radius: _radius,
            tapFocus: TapFocus.focusAndRun,
            onFocusChange: (focused) {
              if (focused) _reveal(card, before: _gridTop, after: _gridEdge);
            },
            face: (context, state, selected, focused) => SwitchGameFace(game: game, state: state, selected: selected, focused: focused),
          ),
        ),
      ),
      layout: (context, count, card, onNearEnd, controller) {
        // The focused card's frame and name sit in the gap above it.
        const rowGap = _GameName.height + _margin + 6, columnGap = 2 * _margin + 6;
        // Its frames and names take room: one column fewer on a low screen.
        final device = DeviceClass.of(context);
        final columns = device == DeviceClass.landscapeLow ? 5 : device.gameColumns(MediaQuery.sizeOf(context).width);
        return GridView.builder(
          key: const ValueKey('switch-games'),
          controller: controller,
          // Room above the first row for its name.
          padding: const EdgeInsets.fromLTRB(_gridEdge, _gridTop, _gridEdge, _gridEdge),
          gridDelegate: columns == null
              ? const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 210, mainAxisSpacing: rowGap, crossAxisSpacing: columnGap)
              : SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: columns, mainAxisSpacing: rowGap, crossAxisSpacing: columnGap),
          itemCount: count,
          itemBuilder: card,
        );
      },
    );

/// Menus and consoles: one row of large squares, vertically centred; on a
/// handheld as many whole cards as fit, none cut at the edge (a low landscape
/// screen fits up to 6). A phone held upright gets two columns instead.
/// Inside another scroll view ([shrinkWrap]) the row has a fixed height.
class SwitchMenuRow extends StatelessWidget {
  const SwitchMenuRow({super.key, required this.tiles, this.shrinkWrap = false, this.autofocusFirst = true});

  final List<MenuTile> tiles;
  final bool shrinkWrap;
  final bool autofocusFirst;

  static const _menuKey = ValueKey('switch-menu');

  /// Card side inside another scroll view.
  static const shrinkWrapSize = 176.0;

  @override
  Widget build(BuildContext context) {
    if (shrinkWrap) return SizedBox(key: _menuKey, height: _rowHeight(shrinkWrapSize), child: _row(shrinkWrapSize));
    return LayoutBuilder(builder: (context, box) {
      final device = DeviceClass.of(context);
      if (device == DeviceClass.portrait) return _grid(box);
      // About the Switch's share of the screen: a 256 px icon on 720 px.
      var size = (box.maxHeight * 0.38).clamp(120.0, 280.0).clamp(0.0, box.maxWidth * 0.42).toDouble();
      if (device != DeviceClass.roomy) {
        // Whole cards at rest: the ones that fit grow until the next one
        // starts at the screen's edge, or one more shrinks in when growing
        // would leave the height.
        final width = box.maxWidth - 2 * _rowEdge;
        final fit = math.max(1, ((width + _gap) / (size + _gap)).floor());
        if (device == DeviceClass.landscapeLow && tiles.length <= 6) {
          // A short menu on a low screen: all of it in the row.
          size = math.min(size, (width - (tiles.length - 1) * _gap) / tiles.length);
        } else if (tiles.length > fit) {
          double sized(int k) => (box.maxWidth - _rowEdge - k * _gap) / k;
          size = _rowHeight(sized(fit)) <= box.maxHeight ? sized(fit) : sized(fit + 1);
        }
      }
      return SizedBox.expand(
        key: _menuKey,
        child: Center(child: SizedBox(height: _rowHeight(size), child: _row(size))),
      );
    });
  }

  /// Between two cards: room for both frames, plus the Switch's gap.
  static const _gap = 2 * _margin + 4;

  /// Two columns of squares, the focused name in the band above each row,
  /// the whole grid in the middle when it fits.
  Widget _grid(BoxConstraints box) {
    final size = (box.maxWidth - 2 * _gridEdge - _gap) / 2;
    final band = _MenuName.bandFor(size);
    final rows = (tiles.length / 2).ceil();
    final content = rows * (size + band);
    final top = math.max(band, (box.maxHeight - content) / 2 + band / 2);
    return GridView.builder(
      key: _menuKey,
      padding: EdgeInsets.fromLTRB(_gridEdge, top, _gridEdge, _gridEdge),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: band, crossAxisSpacing: _gap),
      itemCount: tiles.length,
      itemBuilder: (context, i) => _card(i, size, before: band + _margin, after: _gridEdge),
    );
  }

  /// The card, and the name's band above it mirrored below so the card is
  /// what sits in the middle.
  static double _rowHeight(double size) => size + 2 * _MenuName.bandFor(size);

  Widget _row(double size) {
    final band = _MenuName.bandFor(size);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _rowEdge),
      itemCount: tiles.length,
      itemBuilder: (context, i) => Padding(
        padding: EdgeInsets.only(top: band, bottom: band, right: i == tiles.length - 1 ? 0 : _gap),
        child: SizedBox.square(dimension: size, child: _card(i, size, before: _rowEdge, after: _rowEdge)),
      ),
    );
  }

  /// Tile [i] at [size]; focus scrolls it [before] and [after] clear of its
  /// list's edges.
  Widget _card(int i, double size, {required double before, required double after}) {
    final tile = tiles[i];
    return DpadOwnOutline(
      child: Builder(
        builder: (card) => StyledMenuCard(
          key: ValueKey(tile.label),
          tile: tile,
          autofocus: autofocusFirst && i == 0,
          customBorder: _cardShape,
          tapFocus: TapFocus.focusAndRun,
          onFocusChange: (focused) {
            if (focused) _reveal(card, before: before, after: after);
          },
          face: (context, focused) => SwitchMenuFace(tile: tile, focused: focused, size: size),
        ),
      ),
    );
  }
}

/// A menu or console tile: its accent colour, flat, with its white logo or
/// icon, edge to edge; the frame and the name above when [focused]. [size] is
/// the card's side.
class SwitchMenuFace extends StatelessWidget {
  const SwitchMenuFace({super.key, required this.tile, required this.focused, required this.size});

  final MenuTile tile;
  final bool focused;
  final double size;

  bool get _hasLogo => tile.assetPath != null && _loadable(tile.assetPath!);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final art = size;
    final logoOnly = tile.brandLogo && _hasLogo;
    // The logos are normalized onto a square canvas (ink at most its full
    // width, 45% of its height): nearly the whole card keeps them from
    // looking tiny. An icon leaves room for the name under it.
    final inset = logoOnly ? EdgeInsets.all(art * 0.06) : EdgeInsets.fromLTRB(art * 0.18, art * 0.18, art * 0.18, art * 0.26);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ClipRRect(
            key: ValueKey('switch-art-${tile.label}'),
            borderRadius: BorderRadius.circular(_radius),
            child: ColoredBox(
              color: tile.accentColor ?? scheme.surfaceContainerHighest,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(padding: inset, child: Center(child: _image(art))),
                  if (!logoOnly) _innerLabel(art, DeviceClass.of(context).textFloor),
                  if (tile.badge != null) Positioned(top: art * 0.06, right: art * 0.06, child: _badge(tile.badge!)),
                ],
              ),
            ),
          ),
        ),
        if (focused) const Positioned.fill(left: -_margin, top: -_margin, right: -_margin, bottom: -_margin, child: SwitchFocusFrame()),
        if (focused)
          Positioned(left: -80, right: -80, bottom: size + _margin + 4, child: Center(child: _MenuName(tile.label, size: size))),
      ],
    );
  }

  /// The logo filling its box (the bundled logos share one canvas), white; or
  /// the icon, also white.
  Widget _image(double art) {
    final icon = Icon(tile.icon, size: art * 0.36, color: Colors.white);
    final path = tile.assetPath;
    if (path == null || !_hasLogo) return icon;
    final tint = tile.brandLogo ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null;
    final asset = path.startsWith('assets/');
    final Widget image = path.toLowerCase().endsWith('.svg')
        ? (asset ? SvgPicture.asset(path, colorFilter: tint) : SvgPicture.file(File(path), colorFilter: tint))
        : (asset
            ? Image.asset(path, fit: BoxFit.contain, errorBuilder: (_, __, ___) => icon)
            : Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => icon));
    return tile.brandLogo ? SizedBox.expand(child: image) : image;
  }

  /// Plain tiles carry their name inside, for touch; it gives way to the name
  /// above while focused.
  Widget _innerLabel(double art, double floor) => Positioned(
        left: 10,
        right: 10,
        bottom: art * 0.07,
        child: AnimatedOpacity(
          opacity: focused ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tile.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: (art * 0.065).clamp(floor, math.max(16.0, floor))),
              ),
              if (tile.subtitle != null)
                Text(
                  tile.subtitle!,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white70, fontSize: (art * 0.05).clamp(floor, math.max(13.0, floor))),
                ),
            ],
          ),
        ),
      );

  Widget _badge(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: const Color(0xFFFFC23D), borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black87, letterSpacing: 1)),
      );

  /// A bundled asset (assumed present; a miss falls back via errorBuilder) or
  /// an existing file.
  static bool _loadable(String path) => path.startsWith('assets/') || File(path).existsSync();
}

/// A game: its box art covering the whole square (cropped to it), the state
/// badges in the top left corner, the selected mark over it; the frame and the
/// name above when [focused].
class SwitchGameFace extends StatelessWidget {
  const SwitchGameFace({super.key, required this.game, required this.state, required this.selected, required this.focused});

  final Game game;
  final GameState state;
  final bool selected;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final art = box.maxWidth;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GameBoxart(game: game, size: art, fill: true, placeholder: _GamePlaceholder(game: game, size: art)),
                  Positioned(top: 6, left: 6, child: GameStateBadges(state: state, size: 22)),
                ],
              ),
            ),
          ),
          Positioned.fill(child: SelectedMark(selected: selected, radius: _radius, size: 24, child: const SizedBox.expand())),
          if (focused) const Positioned.fill(left: -_margin, top: -_margin, right: -_margin, bottom: -_margin, child: SwitchFocusFrame()),
          if (focused)
            Positioned(left: -60, right: -60, bottom: box.maxHeight + _margin + 2, child: Center(child: _GameName(game.displayTitle))),
        ],
      );
    });
  }
}

/// The focus frame: [_frameWidth] wide, its colour swinging between cyan and
/// blue every second, for as long as it is on screen.
class SwitchFocusFrame extends StatefulWidget {
  const SwitchFocusFrame({super.key});

  @override
  State<SwitchFocusFrame> createState() => _SwitchFocusFrameState();
}

class _SwitchFocusFrameState extends State<SwitchFocusFrame> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => DecoratedBox(
          key: const ValueKey('switch-frame'),
          decoration: BoxDecoration(
            border: Border.all(color: Color.lerp(_cyan, _blue, Curves.easeInOut.transform(_pulse.value))!, width: _frameWidth),
            borderRadius: BorderRadius.circular(_frameRadius),
          ),
        ),
      ),
    );
  }
}

/// The focused menu card's name, in the band above the row.
class _MenuName extends StatelessWidget {
  const _MenuName(this.text, {required this.size});

  final String text;
  final double size;

  static double fontFor(double size) => (size * 0.072).clamp(14.0, 22.0);

  /// The band above (and below) the row: the frame, one line of the name, air.
  static double bandFor(double size) => _margin + fontFor(size) * 1.4 + 12;

  @override
  Widget build(BuildContext context) => Text(
        key: const ValueKey('switch-name'),
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _cyan,
          fontSize: fontFor(size),
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
        ),
      );
}

/// The focused game's name, on a dark pill over the gap above its card.
class _GameName extends StatelessWidget {
  const _GameName(this.text);

  final String text;
  static const height = 30.0;

  @override
  Widget build(BuildContext context) => Container(
        key: const ValueKey('switch-name'),
        height: height - 4,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(6)),
        // As wide as the name, not the space it may use.
        child: Center(
          widthFactor: 1,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _cyan, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

/// A game without box art: a flat square with a pad and its title.
class _GamePlaceholder extends StatelessWidget {
  const _GamePlaceholder({required this.game, required this.size});

  final Game game;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      key: const ValueKey('switch-placeholder'),
      color: scheme.surfaceContainerHighest,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: Icon(Icons.sports_esports, size: size * 0.34, color: Colors.white24)),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Text(
              game.displayTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Scrolls [card]'s list so the card sits at least [before] from its leading
/// edge and [after] from its trailing one: its frame and name stay on screen.
/// Focus traversal alone would leave it flush against the edge.
void _reveal(BuildContext card, {required double before, required double after}) {
  final box = card.findRenderObject();
  final position = Scrollable.maybeOf(card)?.position;
  if (box == null || !box.attached || position == null) return;
  final viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport == null) return;
  final leading = viewport.getOffsetToReveal(box, 0).offset - before;
  final trailing = viewport.getOffsetToReveal(box, 1).offset + after;
  var target = position.pixels;
  if (target > leading) target = leading;
  if (target < trailing) target = trailing.clamp(double.negativeInfinity, leading);
  target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
  if (target != position.pixels) position.jumpTo(target);
}
