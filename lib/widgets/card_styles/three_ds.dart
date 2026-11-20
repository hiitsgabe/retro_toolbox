import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/utils/image_memory.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_list.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_menu_card.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// The 3DS HOME Menu: square icons, each in a light slot, packed in a grid
/// that scrolls sideways, under a "top screen" strip that shows the focused
/// item large.
const threeDsKit = CardStyleKit(menuList: _menuList, gameList: _gameList);

/// The focused slot's border.
const _cyan = Color(0xFF3FC7F0);

/// Card sides the grid aims for; it fits as many rows as it can.
const _menuSide = 88.0;
const _gameSide = 96.0;
const _gap = 10.0;

/// Inside the grid's panel, so the focus border around an edge card shows.
const _panelPadding = 12.0;

/// Rows a menu gets inside another scroll view (no height to fill).
const _shrinkWrapRows = 2;

/// Within this of the end, the game list loads more (StyledGameList's own
/// threshold for scrolls).
const _nearEndPx = 500.0;

Widget _menuList(BuildContext context, List<MenuTile> tiles, {required bool shrinkWrap, required bool autofocusFirst}) =>
    _ThreeDsMenu(key: const ValueKey('3ds-menu'), tiles: tiles, shrinkWrap: shrinkWrap, autofocusFirst: autofocusFirst);

Widget _gameList(BuildContext context) => const _ThreeDsGames();

// ---------------------------------------------------------------------------
// Layout

/// The top strip over the grid. [shrinkWrap]: inside another scroll view, so
/// both get a fixed height. A [menu] of [count] tiles on a phone or a pixel
/// handheld takes the columns that give it the largest slots on one screen.
class _TopScreenLayout extends StatelessWidget {
  const _TopScreenLayout({super.key, required this.strip, required this.grid, required this.side, this.shrinkWrap = false, this.menu = false, this.count = 0});

  final Widget strip;
  final Widget Function(int rows, double side) grid;
  final double side;
  final bool shrinkWrap;
  final bool menu;
  final int count;

  /// The strip's share of the height: the grid is the menu, the strip a
  /// caption, so a low screen gives it less.
  static double stripHeight(DeviceClass device, double height) => switch (device) {
        DeviceClass.landscapeLow => (height * 0.22).clamp(56.0, 96.0),
        DeviceClass.pixel => (height * 0.2).clamp(56.0, 96.0),
        _ => (height * 0.26).clamp(96.0, 200.0),
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (shrinkWrap || !box.hasBoundedHeight) {
        const stripHeight = 104.0;
        final gridHeight = _shrinkWrapRows * side + (_shrinkWrapRows - 1) * _gap + 2 * _panelPadding;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(height: stripHeight, child: strip),
            const SizedBox(height: 12),
            SizedBox(height: gridHeight, child: _Panel(child: grid(_shrinkWrapRows, side))),
          ]),
        );
      }
      final device = DeviceClass.of(context);
      final stripHeight = _TopScreenLayout.stripHeight(device, box.maxHeight);
      final columns = switch (device) {
        DeviceClass.portrait when menu => const [2, 3],
        DeviceClass.pixel when menu => const [3, 4],
        _ => const <int>[],
      };
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          SizedBox(height: stripHeight, child: strip),
          const SizedBox(height: 12),
          Expanded(
            child: _Panel(
              child: LayoutBuilder(builder: (context, area) {
                // As many rows as fit, the cards a little larger to fill the
                // height, never past 1.2 times their size.
                final inner = area.maxHeight - 2 * _panelPadding;
                final fit = largestFit(count, Size(area.maxWidth - 2 * _panelPadding, inner), columns, aspect: 1, gap: _gap, minWidth: 48);
                if (fit != null) return grid((count / fit.columns).ceil(), fit.cell.width);
                final rows = max(1, ((inner + _gap) / (side + _gap)).floor());
                final fitted = min((inner - (rows - 1) * _gap) / rows, side * 1.2);
                return grid(rows, max(fitted, 24));
              }),
            ),
          ),
        ]),
      );
    });
  }
}

/// The 3DS lower screen's soft panel behind the grid.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.10), Colors.white.withValues(alpha: 0.04)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

/// [count] cards of [side] in [rows], column after column, scrolling sideways;
/// empty slots fill the rest of the screen as on the 3DS.
class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.rows, required this.side, required this.count, required this.card, this.controller});

  final int rows;
  final double side;
  final int count;
  final Widget Function(BuildContext context, int index) card;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      var side = this.side;
      final width = box.maxWidth - 2 * _panelPadding;
      final visibleColumns = max(1, ((width + _gap) / (side + _gap)).floor());
      final columns = max(visibleColumns, (count / rows).ceil());
      if (columns > visibleColumns) {
        // A shelf that scrolls shows whole slots at rest, none cut at the
        // edge: one more column, a little smaller, the next one starting
        // just past the edge.
        side = (box.maxWidth - _panelPadding) / (visibleColumns + 1) - _gap;
      }
      final height = rows * side + (rows - 1) * _gap + 2 * _panelPadding;
      // A grid that fits is centred; one that scrolls starts at the edge.
      final spare = columns == visibleColumns ? box.maxWidth - columns * side - (columns - 1) * _gap : 0.0;
      return Center(
        child: SizedBox(
          height: height,
          child: GridView.builder(
            controller: controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(vertical: _panelPadding, horizontal: max(_panelPadding, spare / 2)),
            clipBehavior: Clip.hardEdge,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: rows,
              mainAxisSpacing: _gap,
              crossAxisSpacing: _gap,
              mainAxisExtent: side,
            ),
            itemCount: columns * rows,
            itemBuilder: (context, i) => i < count ? card(context, i) : const _EmptySlot(),
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Menus

class _ThreeDsMenu extends StatefulWidget {
  const _ThreeDsMenu({super.key, required this.tiles, required this.shrinkWrap, required this.autofocusFirst});

  final List<MenuTile> tiles;
  final bool shrinkWrap;
  final bool autofocusFirst;

  @override
  State<_ThreeDsMenu> createState() => _ThreeDsMenuState();
}

class _ThreeDsMenuState extends State<_ThreeDsMenu> {
  /// The tile the strip shows: the focused one, the first before any.
  final _focused = ValueNotifier(0);

  @override
  void dispose() {
    _focused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiles = widget.tiles;
    return _TopScreenLayout(
      side: _menuSide,
      shrinkWrap: widget.shrinkWrap,
      menu: true,
      count: tiles.length,
      strip: ValueListenableBuilder<int>(
        valueListenable: _focused,
        builder: (context, i, _) => tiles.isEmpty ? const _TopStrip(name: '') : _MenuStrip(tile: tiles[min(i, tiles.length - 1)]),
      ),
      grid: (rows, side) => _SlotGrid(
        rows: rows,
        side: side,
        count: tiles.length,
        // The slot pulses its own border: no DpadScope outline over it.
        card: (context, i) => DpadOwnOutline(
          child: StyledMenuCard(
            key: ValueKey(tiles[i].label),
            tile: tiles[i],
            autofocus: widget.autofocusFirst && i == 0,
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(side * 0.12)),
            onFocusChange: (v) {
              if (v) _focused.value = i;
            },
            face: (context, focused) => _Slot(focused: focused, child: _MenuFace(tile: tiles[i])),
          ),
        ),
      ),
    );
  }
}

/// A menu tile's icon: its accent, glossy, with the white logo or icon.
class _MenuFace extends StatelessWidget {
  const _MenuFace({required this.tile});

  final MenuTile tile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: tile.label,
      child: LayoutBuilder(builder: (context, box) {
        final side = box.biggest.shortestSide;
        final bg = tile.bgAssetPath;
        return DecoratedBox(
          decoration: BoxDecoration(gradient: _accentGradient(tile.accentColor, scheme)),
          child: Stack(fit: StackFit.expand, children: [
            if (_loadable(bg)) ...[
              _image(bg!, fit: BoxFit.cover, fallback: const SizedBox.shrink()),
              const ColoredBox(color: Colors.black38),
            ],
            const _Gloss(),
            _art(side),
          ]),
        );
      }),
    );
  }

  /// The art takes the whole square: a logo's canvas is square with margins
  /// of its own, a picture is cropped to fit. Only the icon glyph gets a margin.
  Widget _art(double side) {
    final icon = Center(
      child: Icon(tile.icon, size: side * 0.46, color: Colors.white, shadows: const [Shadow(color: Colors.black38, blurRadius: 4)]),
    );
    final path = tile.assetPath;
    if (!_loadable(path)) return icon;
    final tint = tile.brandLogo ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null;
    return SizedBox.expand(child: _image(path!, fit: tile.brandLogo ? BoxFit.contain : BoxFit.cover, tint: tint, fallback: icon));
  }
}

/// The light sheen over the top of a 3DS icon.
class _Gloss extends StatelessWidget {
  const _Gloss();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.topCenter,
      child: FractionallySizedBox(
        heightFactor: 0.5,
        widthFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuStrip extends StatelessWidget {
  const _MenuStrip({required this.tile});

  final MenuTile tile;

  @override
  Widget build(BuildContext context) {
    return _TopStrip(
      art: _Slot(focused: false, child: _MenuFace(tile: tile)),
      name: tile.label,
      tint: tile.accentColor,
      lines: [
        if (tile.subtitle != null) Text(tile.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
      chip: tile.badge,
    );
  }
}

// ---------------------------------------------------------------------------
// Games

class _ThreeDsGames extends StatefulWidget {
  const _ThreeDsGames();

  @override
  State<_ThreeDsGames> createState() => _ThreeDsGamesState();
}

class _ThreeDsGamesState extends State<_ThreeDsGames> {
  /// The game the strip shows: the focused one, null before any.
  final _focused = ValueNotifier<Game?>(null);

  @override
  void dispose() {
    _focused.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StyledGameList(
      card: (context, game, {required autofocus}) => DpadOwnOutline(
        child: StyledGameCard(
          game: game,
          autofocus: autofocus,
          radius: 12,
          onFocusChange: (v) {
            if (v) _focused.value = game;
          },
          face: (context, state, selected, focused) => _Slot(
            focused: focused,
            selected: selected,
            child: _GameFace(game: game, state: state),
          ),
        ),
      ),
      layout: (context, count, card, onNearEnd, controller) => _TopScreenLayout(
        key: const ValueKey('3ds-games'),
        side: _gameSide,
        strip: ValueListenableBuilder<Game?>(
          valueListenable: _focused,
          builder: (context, game, _) => game == null ? _TopStrip(name: count == 0 ? 'No games' : '') : _GameStrip(game: game),
        ),
        grid: (rows, side) => _NearEnd(
          controller: controller,
          onNearEnd: onNearEnd,
          child: _SlotGrid(rows: rows, side: side, count: count, card: card, controller: controller),
        ),
      ),
    );
  }
}

/// Loads more when the cards end within reach without a scroll (a wide
/// screen holds a whole page): StyledGameList only hears scrolls.
class _NearEnd extends StatelessWidget {
  const _NearEnd({required this.controller, required this.onNearEnd, required this.child});

  final ScrollController controller;
  final VoidCallback? onNearEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final load = onNearEnd;
    if (load != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !controller.hasClients) return;
        final p = controller.position;
        if (p.hasContentDimensions && p.maxScrollExtent - p.pixels < _nearEndPx) load();
      });
    }
    return child;
  }
}

/// A game's icon: its box art cropped to the square, its state in the top
/// left corner (the top right one folds over when it is selected).
class _GameFace extends StatelessWidget {
  const _GameFace({required this.game, required this.state});

  final Game game;
  final GameState state;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: game.displayTitle,
      child: LayoutBuilder(builder: (context, box) {
        final side = box.biggest.shortestSide;
        return Stack(fit: StackFit.expand, children: [
          _Cover(game: game, side: side),
          Positioned(
            top: 3,
            left: 3,
            child: GameStateBadges(state: state, size: (side * 0.22).clamp(14.0, 24.0)),
          ),
        ]);
      }),
    );
  }
}

/// The box art cropped to fill the square; the placeholder while it loads,
/// when it fails and when there is none. Not GameBoxart: that one insets the
/// art inside an outline of its own and fails to a small icon, a card inside
/// the card.
class _Cover extends StatelessWidget {
  const _Cover({required this.game, required this.side});

  final Game game;
  final double side;

  @override
  Widget build(BuildContext context) {
    final url = game.boxart;
    final placeholder = _GamePlaceholder(game: game);
    if (url == null) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      width: side,
      height: side,
      fit: BoxFit.cover,
      // Decode at the on-screen size, as GameBoxart does.
      memCacheWidth: thumbnailDecodeWidth(side, side, MediaQuery.maybeDevicePixelRatioOf(context) ?? 1),
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
      errorListener: (e) => debugPrint('Error loading boxart: $e'),
    );
  }
}

/// A game without box art: its console's colour and logo, and its title.
class _GamePlaceholder extends StatelessWidget {
  const _GamePlaceholder({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final console = CatalogService.consoleByIdSync(game.consoleId);
    final logo = console == null ? null : consoleLogoAsset(console);
    return LayoutBuilder(builder: (context, box) {
      final side = box.biggest.shortestSide;
      return DecoratedBox(
        key: const ValueKey('3ds-placeholder'),
        decoration: BoxDecoration(
          gradient:
              _accentGradient(console == null ? const Color(0xFF5C6B8A) : consoleBrandColor(console) ?? const Color(0xFF5C6B8A), Theme.of(context).colorScheme),
        ),
        child: Stack(fit: StackFit.expand, children: [
          const _Gloss(),
          Positioned(
            left: side * 0.1,
            right: side * 0.1,
            top: side * 0.1,
            height: side * 0.38,
            child: logo != null
                ? SvgPicture.asset(logo, colorFilter: const ColorFilter.mode(Colors.white54, BlendMode.srcIn))
                : Icon(Icons.sports_esports_rounded, size: side * 0.34, color: Colors.white54),
          ),
          Positioned(
            left: side * 0.08,
            right: side * 0.08,
            bottom: side * 0.07,
            child: Text(
              game.displayTitle,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: (side * 0.11).clamp(8.0, 14.0),
                height: 1.1,
                fontWeight: FontWeight.w700,
                shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
              ),
            ),
          ),
        ]),
      );
    });
  }
}

class _GameStrip extends ConsumerWidget {
  const _GameStrip({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gameStateProvider(game));
    final selected = ref.watch(gameSelectionProvider(game.gameId));
    final console = CatalogService.consoleByIdSync(game.consoleId);
    final logo = console == null ? null : consoleLogoAsset(console);
    return _TopStrip(
      art: _Slot(focused: false, selected: selected, child: _GameFace(game: game, state: state)),
      name: game.displayTitle,
      tint: console == null ? null : consoleBrandColor(console),
      lines: [
        Row(children: [
          if (logo != null) ...[
            SizedBox(
              width: 28,
              height: 20,
              child: SvgPicture.asset(logo, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: Text(_consoleName(console, game), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (game.size > 0) ...[
            const Text('  ·  '),
            Text(formatBytes(game.size)),
          ],
        ]),
      ],
    );
  }

  static String _consoleName(Console? console, Game game) => console?.name ?? game.consoleId.toUpperCase();
}

// ---------------------------------------------------------------------------
// Shared pieces

/// The 3DS upper screen: the focused item's icon large, its name and details.
class _TopStrip extends StatelessWidget {
  const _TopStrip({required this.name, this.art, this.lines = const [], this.chip, this.tint});

  final String name;

  /// The item's colour, washed in from the left like a title banner.
  final Color? tint;
  final Widget? art;
  final List<Widget> lines;
  final String? chip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      // A low strip (Odin 2, the pixel handheld) has room for one name line.
      final low = box.maxHeight < 100 || DeviceClass.of(context) == DeviceClass.pixel;
      final pad = box.maxHeight < 72 ? 8.0 : 12.0;
      final artSide = max(0.0, box.maxHeight - 2 * pad);
      final nameStyle = box.maxHeight < 72 ? text.titleMedium : (box.maxHeight < 120 ? text.titleLarge : text.headlineSmall);
      return Container(
        key: const ValueKey('3ds-strip'),
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0, 0.6, 1],
            colors: [
              _shade(tint, 0.36, 0.9) ?? Colors.black.withValues(alpha: 0.38),
              _shade(tint, 0.2, 0.6) ?? Colors.black.withValues(alpha: 0.42),
              Colors.black.withValues(alpha: 0.5),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(children: [
          if (art != null) ...[
            SizedBox.square(dimension: artSide, child: art),
            const SizedBox(width: 20),
          ],
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        name,
                        key: const ValueKey('3ds-strip-name'),
                        maxLines: low ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: nameStyle?.copyWith(color: Colors.white, fontWeight: FontWeight.w700, height: 1.15),
                      ),
                    ),
                    if (chip != null) ...[const SizedBox(width: 10), _Chip(chip!)],
                  ]),
                  if (lines.isNotEmpty) SizedBox(height: low ? 2 : 6),
                  ...lines,
                ],
              ),
            ),
          ),
        ]),
      );
    });
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _cyan, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
    );
  }
}

/// A card in its slot: a light frame (white 85%, 1.5 px grey border, 3 px
/// padding) around the square icon, rounded 12%. Focused: the pulsing cyan
/// border. A game's slot wears the selected mark ([selected] not null).
class _Slot extends StatelessWidget {
  const _Slot({required this.focused, required this.child, this.selected});

  final bool focused;
  final Widget child;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = box.biggest.shortestSide;
      final outer = side * 0.12;
      const inset = 3 + 1.5;
      return Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
        // A soft cyan glow, under the frame so the icon stays clear.
        if (focused)
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(outer),
              boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.55), blurRadius: 14, spreadRadius: 2)],
            ),
          ),
        _mark(
          side,
          outer,
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(outer),
              border: Border.all(color: const Color(0xFFB4B9C2), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 4, offset: const Offset(0, 2)),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: ClipRRect(key: const ValueKey('3ds-art'), borderRadius: BorderRadius.circular((side - 2 * inset) * 0.12), child: child),
            ),
          ),
        ),
        if (focused) Positioned(left: -3, top: -3, right: -3, bottom: -3, child: _PulseBorder(radius: outer + 3)),
      ]);
    });
  }

  Widget _mark(double side, double radius, Widget frame) =>
      selected == null ? frame : SelectedMark(selected: selected!, radius: radius, size: (side * 0.22).clamp(14.0, 24.0), child: frame);
}

/// 3 px cyan, its opacity going 0.55 to 1 and back every 0.8 s.
class _PulseBorder extends StatefulWidget {
  const _PulseBorder({required this.radius});

  final double radius;

  @override
  State<_PulseBorder> createState() => _PulseBorderState();
}

class _PulseBorderState extends State<_PulseBorder> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400))..repeat(reverse: true);
  late final _opacity = Tween(begin: 0.55, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: IgnorePointer(
        key: const ValueKey('3ds-focus'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: _cyan, width: 3),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// A slot with nothing in it, as the 3DS shows past the last icon.
class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(box.biggest.shortestSide * 0.12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.13), width: 1.5),
        ),
      );
    });
  }
}

/// A 3DS icon's colour: the accent, bright at the top; neutral without one.
LinearGradient _accentGradient(Color? accent, ColorScheme scheme) {
  if (accent == null) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh],
    );
  }
  final hsl = HSLColor.fromColor(accent);
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      hsl.withLightness(0.52).withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0)).toColor(),
      hsl.withLightness(0.30).toColor(),
    ],
  );
}

/// [color] at [lightness] and [alpha]; null without a colour.
Color? _shade(Color? color, double lightness, double alpha) =>
    color == null ? null : HSLColor.fromColor(color).withLightness(lightness).toColor().withValues(alpha: alpha);

/// A bundled asset (assumed present, misses fall back at load) or an existing file.
bool _loadable(String? path) => path != null && (path.startsWith('assets/') || File(path).existsSync());

Widget _image(String path, {BoxFit? fit, ColorFilter? tint, required Widget fallback}) {
  final isAsset = path.startsWith('assets/');
  if (path.toLowerCase().endsWith('.svg')) {
    Widget error(BuildContext _, Object __, StackTrace ___) => fallback;
    return isAsset
        ? SvgPicture.asset(path, fit: fit ?? BoxFit.contain, colorFilter: tint, errorBuilder: error)
        : SvgPicture.file(File(path), fit: fit ?? BoxFit.contain, colorFilter: tint, errorBuilder: error);
  }
  final image =
      isAsset ? Image.asset(path, fit: fit, errorBuilder: (_, __, ___) => fallback) : Image.file(File(path), fit: fit, errorBuilder: (_, __, ___) => fallback);
  return tint == null ? image : ColorFiltered(colorFilter: tint, child: image);
}
