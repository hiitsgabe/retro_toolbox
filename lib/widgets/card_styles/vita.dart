import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/widgets/card_styles/card_style_registry.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_card.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_game_list.dart';
import 'package:retro_toolbox/widgets/card_styles/styled_menu_card.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_list/game_boxart.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// PS Vita home screen: glossy bubbles in rows of 4 and 3, the label under
/// each, a column of page dots on the right.
const vitaKit = CardStyleKit(menuList: _menuList, gameList: _gameList);

Widget _menuList(BuildContext context, List<MenuTile> tiles, {required bool shrinkWrap, required bool autofocusFirst}) => _VitaRows(
      key: const ValueKey('vita-menu'),
      count: tiles.length,
      shrinkWrap: shrinkWrap,
      item: (context, i) => _VitaMenuCell(key: ValueKey(tiles[i].label), tile: tiles[i], autofocus: autofocusFirst && i == 0),
    );

Widget _gameList(BuildContext context) => StyledGameList(
      card: (context, game, {required autofocus}) => _VitaGameCell(game: game, autofocus: autofocus),
      layout: (context, count, card, onNearEnd, controller) =>
          _VitaRows(key: const ValueKey('vita-games'), count: count, item: card, controller: controller),
    );

/// Sizes of the bubbles in one layout, for the cells under it.
class _VitaMetrics extends InheritedWidget {
  const _VitaMetrics({required this.bubble, required super.child});

  /// Bubble diameter.
  final double bubble;

  double get labelSize => labelSizeFor(bubble);

  static double labelSizeFor(double bubble) => (bubble * 0.105).clamp(11.0, 15.0);

  /// Bubble, its focus growth, the gap and up to two label lines.
  static double rowHeightFor(double bubble) => bubble * 1.1 + 6 + labelSizeFor(bubble) * 2.9 + 10;

  static _VitaMetrics of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_VitaMetrics>()!;

  @override
  bool updateShouldNotify(_VitaMetrics old) => old.bubble != bubble;
}

/// Rows alternating 4 and 3 places, the 3-rows half a place in, scrolling
/// vertically; [controller] (or its own) also drives the page dots.
class _VitaRows extends StatefulWidget {
  const _VitaRows({super.key, required this.count, required this.item, this.controller, this.shrinkWrap = false});

  final int count;
  final Widget Function(BuildContext context, int index) item;
  final ScrollController? controller;
  final bool shrinkWrap;

  @override
  State<_VitaRows> createState() => _VitaRowsState();
}

class _VitaRowsState extends State<_VitaRows> {
  static const _dotsGutter = 32.0;
  ScrollController? _own;

  /// The page dots: how many, and which is lit (none before the first layout).
  (int, int) _dots = (0, 0);
  (int, int) _nextDots = (0, 0);

  void _showDots() {
    if (mounted && _nextDots != _dots) setState(() => _dots = _nextDots);
  }

  ScrollController get _controller => widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  /// Rows for [count] items: every pair of rows holds 7.
  static int _rows(int count) {
    final rest = count % 7;
    return count ~/ 7 * 2 + (rest == 0 ? 0 : (rest <= 4 ? 1 : 2));
  }

  static int _rowStart(int row) => row ~/ 2 * 7 + (row.isOdd ? 4 : 0);

  bool _onScroll(Notification n) {
    final metrics = switch (n) {
      ScrollNotification(:final metrics, :final depth) when depth == 0 => metrics,
      ScrollMetricsNotification(:final metrics, :final depth) when depth == 0 => metrics,
      _ => null,
    };
    if (metrics != null && metrics.axis == Axis.vertical) {
      _nextDots = _dotsFor(metrics);
      // A scroll during layout (focus scrolling into view) waits for the
      // frame's end; metrics changes already come after it.
      if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _showDots());
      } else {
        _showDots();
      }
    }
    return false; // StyledGameList loads more from the same notifications
  }

  /// One dot per screenful (at most 12), and the one the view is at; none
  /// when everything fits.
  static (int, int) _dotsFor(ScrollMetrics m) {
    final view = m.viewportDimension;
    if (view <= 0 || m.maxScrollExtent <= 1) return (0, 0);
    final pages = math.min(((m.maxScrollExtent + view) / view).ceil(), 12);
    final at = (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0);
    return (pages, (at * (pages - 1)).round());
  }

  Widget _row(BuildContext context, int row, double cell, double rowHeight) {
    final start = _rowStart(row);
    final end = math.min(start + (row.isOdd ? 3 : 4), widget.count);
    return SizedBox(
      height: rowHeight,
      child: Center(
        child: SizedBox(
          width: cell * 4,
          child: Row(
            key: ValueKey('vita-row-$row'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row.isOdd) SizedBox(width: cell / 2),
              for (var i = start; i < end; i++) SizedBox(width: cell, child: widget.item(context, i)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final gutter = widget.shrinkWrap ? 8.0 : _dotsGutter;
      final width = (box.maxWidth - gutter * 2).clamp(0.0, 1000.0);
      final cell = width / 4;
      final bubble = math.min((cell * 0.6).clamp(48.0, 150.0), cell);
      final rowHeight = _VitaMetrics.rowHeightFor(bubble);
      final rows = _rows(widget.count);
      const padding = EdgeInsets.symmetric(vertical: 16);

      final Widget list;
      if (widget.shrinkWrap) {
        // Inside another scroll view: all rows, no scrolling of its own.
        list = Padding(
          padding: padding,
          child: Column(mainAxisSize: MainAxisSize.min, children: [for (var r = 0; r < rows; r++) _row(context, r, cell, rowHeight)]),
        );
      } else {
        list = NotificationListener<Notification>(
          onNotification: _onScroll,
          child: ListView.builder(
            controller: _controller,
            padding: padding,
            itemExtent: rowHeight,
            itemCount: rows,
            itemBuilder: (context, r) => _row(context, r, cell, rowHeight),
          ),
        );
      }
      return _VitaMetrics(
        bubble: bubble,
        child: Stack(
          children: [
            list,
            if (!widget.shrinkWrap && _dots.$1 > 1)
              Positioned(right: 10, top: 0, bottom: 0, child: Center(child: _PageDots(count: _dots.$1, active: _dots.$2))),
          ],
        ),
      );
    });
  }
}

/// Where in the list the view is: [count] dots, the [active] one lit.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('vita-dots'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            key: ValueKey(i == active ? 'vita-dot-active' : 'vita-dot-$i'),
            duration: const Duration(milliseconds: 160),
            margin: const EdgeInsets.symmetric(vertical: 5),
            width: i == active ? 9 : 7,
            height: i == active ? 9 : 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: i == active ? 0.95 : 0.4),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 3),
                if (i == active) BoxShadow(color: Colors.white.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
      ],
    );
  }
}

/// A bubble over its label. The bubble alone takes taps and focus, so the ink
/// is round; it draws its own focus look instead of DpadScope's square.
class _VitaCell extends StatelessWidget {
  const _VitaCell({required this.bubble, required this.label, this.subtitle});

  final Widget bubble;
  final String label;
  final String? subtitle;

  static const _shadows = [
    Shadow(color: Color(0xCC000000), blurRadius: 3, offset: Offset(0, 1)),
    Shadow(color: Color(0x80000000), blurRadius: 10),
  ];

  @override
  Widget build(BuildContext context) {
    final m = _VitaMetrics.of(context);
    return DpadOwnOutline(
      child: Column(
        key: const ValueKey('vita-cell'),
        mainAxisSize: MainAxisSize.min,
        children: [
          // Room for the focused bubble to grow without touching the label.
          Padding(
            padding: EdgeInsets.symmetric(vertical: m.bubble * 0.04),
            child: SizedBox.square(dimension: m.bubble, child: bubble),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: subtitle == null ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: m.labelSize, height: 1.25, fontWeight: FontWeight.w600, color: Colors.white, shadows: _shadows),
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: m.labelSize * 0.8, color: Colors.white70, shadows: _shadows),
            ),
        ],
      ),
    );
  }
}

/// The glossy sphere: [art] clipped to a circle under a highlight on its upper
/// half, a rim and a soft shadow; [focused] grows it to 1.08 with a glow.
/// A game's bubble also wears the selected mark ([selected] not null).
class _Bubble extends StatelessWidget {
  const _Bubble({required this.art, required this.focused, this.corner, this.selected});

  final Widget art;
  final bool focused;

  /// Drawn over the top right, outside the clip (badges).
  final Widget? corner;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final d = _VitaMetrics.of(context).bubble;
    final bubble = _bubble(d);
    return AnimatedScale(
      key: const ValueKey('vita-focus-scale'),
      scale: focused ? 1.08 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: selected == null ? bubble : SelectedMark(selected: selected!, circle: true, size: (d * 0.2).clamp(18.0, 28.0), child: bubble),
    );
  }

  Widget _bubble(double d) => Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: d * 0.12, offset: Offset(0, d * 0.05)),
                if (focused) BoxShadow(color: Colors.white.withValues(alpha: 0.7), blurRadius: d * 0.16, spreadRadius: d * 0.02),
              ],
            ),
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  art,
                  // Shading: the edge falls off, as on a sphere lit from above.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(-0.15, -0.35),
                        radius: 0.95,
                        colors: [Color(0x00000000), Color(0x00000000), Color(0x59000000)],
                        stops: [0, 0.62, 1],
                      ),
                    ),
                  ),
                  // Light bouncing up into the bottom of the sphere.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, 1.05),
                        radius: 0.6,
                        colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                      ),
                    ),
                  ),
                  // The gloss: a white ellipse over the upper half, fading down.
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: d * 0.035),
                      child: Container(
                        width: d * 0.78,
                        height: d * 0.47,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.elliptical(d * 0.39, d * 0.235)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white.withValues(alpha: 0.72), Colors.white.withValues(alpha: 0.18), Colors.white.withValues(alpha: 0)],
                            stops: const [0, 0.55, 1],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // The rim.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: focused ? 0.95 : 0.45), width: focused ? 2.5 : 1.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (corner != null) Positioned(top: -d * 0.02, right: -d * 0.02, child: corner!),
        ],
      );
}

class _VitaMenuCell extends StatelessWidget {
  const _VitaMenuCell({super.key, required this.tile, required this.autofocus});

  final MenuTile tile;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return _VitaCell(
      label: tile.label,
      subtitle: tile.subtitle,
      bubble: StyledMenuCard(
        tile: tile,
        autofocus: autofocus,
        customBorder: const CircleBorder(),
        face: (context, focused) => _Bubble(
          focused: focused,
          art: _MenuArt(tile: tile),
          corner: tile.badge == null ? null : _Pill(tile.badge!),
        ),
      ),
    );
  }
}

/// A menu or console tile inside its bubble: its accent as a lit sphere, the
/// icon or brand logo in white.
class _MenuArt extends StatelessWidget {
  const _MenuArt({required this.tile});

  final MenuTile tile;

  static bool _loadable(String? path) => path != null && (path.startsWith('assets/') || File(path).existsSync());

  @override
  Widget build(BuildContext context) {
    final d = _VitaMetrics.of(context).bubble;
    final base = HSLColor.fromColor(tile.accentColor ?? Theme.of(context).colorScheme.surfaceContainerHighest);
    final icon = Icon(tile.icon, size: d * 0.42, color: Colors.white, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)]);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.25, -0.45),
          radius: 1.05,
          colors: [
            base.withLightness((base.lightness + 0.22).clamp(0.0, 0.72)).toColor(),
            base.withLightness(base.lightness.clamp(0.28, 0.5)).toColor(),
            base.withLightness((base.lightness * 0.45).clamp(0.08, 0.22)).toColor(),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_loadable(tile.bgAssetPath)) ...[
            _image(tile.bgAssetPath!, fit: BoxFit.cover, fallback: const SizedBox.shrink()),
            const ColoredBox(color: Color(0x59000000)),
          ],
          if (tile.brandLogo && _loadable(tile.assetPath))
            // The logos sit on a square canvas, ink a band across the middle:
            // a square near the full diameter keeps the band inside the circle.
            Center(child: SizedBox.square(dimension: d * 0.8, child: _logo(tile.assetPath!, icon)))
          else
            Padding(
              padding: EdgeInsets.all(d * 0.2),
              child: Center(child: _loadable(tile.assetPath) ? _logo(tile.assetPath!, icon) : icon),
            ),
        ],
      ),
    );
  }

  Widget _logo(String path, Widget fallback) {
    final tint = tile.brandLogo ? const ColorFilter.mode(Colors.white, BlendMode.srcIn) : null;
    final image = _image(path, fit: BoxFit.contain, tint: tint, fallback: fallback);
    // The bundled logos share one canvas: filling the box keeps them one size.
    return tile.brandLogo ? SizedBox.expand(child: image) : image;
  }

  static Widget _image(String path, {required BoxFit fit, ColorFilter? tint, required Widget fallback}) {
    final asset = path.startsWith('assets/');
    Widget error(BuildContext _, Object __, StackTrace? ___) => fallback;
    if (path.toLowerCase().endsWith('.svg')) {
      return asset
          ? SvgPicture.asset(path, fit: fit, colorFilter: tint, errorBuilder: error)
          : SvgPicture.file(File(path), fit: fit, colorFilter: tint, errorBuilder: error);
    }
    return asset ? Image.asset(path, fit: fit, errorBuilder: error) : Image.file(File(path), fit: fit, errorBuilder: error);
  }
}

/// A tile's corner tag ("ALPHA").
class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFF8F00)]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Text(text, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.black87)),
    );
  }
}

class _VitaGameCell extends StatelessWidget {
  const _VitaGameCell({required this.game, required this.autofocus});

  final Game game;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final d = _VitaMetrics.of(context).bubble;
    return _VitaCell(
      label: game.displayTitle,
      bubble: StyledGameCard(
        game: game,
        autofocus: autofocus,
        radius: d / 2,
        face: (context, state, selected, focused) => _gameFace(context, game, state, selected, focused),
      ),
    );
  }
}

/// A game's bubble: its box art cropped to the circle, its state badges on
/// the top right, the selected mark round it.
Widget _gameFace(BuildContext context, Game game, GameState state, bool selected, bool focused) {
  final d = _VitaMetrics.of(context).bubble;
  return _Bubble(
    focused: focused,
    art: GameBoxart(game: game, size: d, fill: true, placeholder: _Placeholder(game: game)),
    corner: GameStateBadges(state: state, size: (d * 0.2).clamp(18.0, 28.0)),
    selected: selected,
  );
}

/// No box art: a sphere in a colour of the title's own, with a pad.
class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.game});

  final Game game;

  @override
  Widget build(BuildContext context) {
    final d = _VitaMetrics.of(context).bubble;
    // Its own sum, not hashCode: the same title gets the same colour every run.
    final hue = (game.displayTitle.codeUnits.fold(0, (h, c) => h * 31 + c & 0xFFFFFF) % 360).toDouble();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.25, -0.45),
          radius: 1.05,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.55, 0.62).toColor(),
            HSLColor.fromAHSL(1, hue, 0.6, 0.4).toColor(),
            HSLColor.fromAHSL(1, hue, 0.65, 0.18).toColor(),
          ],
          stops: const [0, 0.55, 1],
        ),
      ),
      child: Icon(Icons.videogame_asset_rounded, size: d * 0.38, color: Colors.white, shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)]),
    );
  }
}
