import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// One tile in a [MenuGrid]. Shows [assetPath] (a PNG on disk or bundled) when
/// present and loadable, otherwise falls back to [icon].
class MenuTile {
  final String label;
  final IconData icon;

  /// Optional foreground image (logo) for the tile. Bundled asset path (e.g.
  /// `assets/foo.png`) or an absolute file path. Falls back to [icon] when null
  /// or missing.
  final String? assetPath;

  /// Optional full-bleed background image behind the tile content. Same path
  /// rules as [assetPath]; a dark scrim is drawn over it for legibility.
  final String? bgAssetPath;

  /// Optional brand accent. When set, the tile is a darkened gradient of this
  /// color (logo/label rendered light on top) instead of the neutral surface.
  final Color? accentColor;

  /// Optional smaller line under [label] (e.g. the console for a game tile).
  final String? subtitle;

  /// Optional corner badge (e.g. "ALPHA").
  final String? badge;
  final VoidCallback onTap;

  const MenuTile({
    required this.label,
    required this.icon,
    this.onTap = _noop,
    this.assetPath,
    this.bgAssetPath,
    this.accentColor,
    this.subtitle,
    this.badge,
  });

  static void _noop() {}
}

/// 3DS-inspired grid of square tiles. Responsive column count via a max tile
/// extent; scrolls when tiles overflow.
class MenuGrid extends StatelessWidget {
  final List<MenuTile> tiles;

  /// Set when embedding inside another scroll view (so the grid itself doesn't
  /// scroll and sizes to its content).
  final bool shrinkWrap;

  const MenuGrid({super.key, required this.tiles, this.shrinkWrap = false});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => _MenuTileCard(tile: tiles[i]),
    );
  }
}

class _MenuTileCard extends StatefulWidget {
  final MenuTile tile;
  const _MenuTileCard({required this.tile});

  @override
  State<_MenuTileCard> createState() => _MenuTileCardState();
}

class _MenuTileCardState extends State<_MenuTileCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.tile.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        child: MenuTileFace(tile: widget.tile),
      ),
    );
  }
}

/// The visual face of a [MenuTile]: accent gradient (or neutral surface),
/// optional background image, logo/icon and label. No interaction — wrap it in
/// a gesture detector (see [MenuGrid]) or reuse it standalone (e.g. CoverFlow).
class MenuTileFace extends StatelessWidget {
  final MenuTile tile;

  /// Hide the label to reuse the face as a compact thumbnail (e.g. list rows).
  final bool showLabel;
  const MenuTileFace({super.key, required this.tile, this.showLabel = true});

  bool get _hasBg => _loadable(tile.bgAssetPath);

  /// Light-on-dark content (accent gradient or bg image present).
  bool get _light => _hasBg || tile.accentColor != null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _gradientColors(scheme),
          ),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ..._background(scheme),
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, 18, 18, showLabel ? 6 : 18),
                    child: Center(child: _tileImage(scheme)),
                  ),
                ),
                if (showLabel)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          tile.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _light ? Colors.white : null,
                            shadows: _light ? const [Shadow(color: Colors.black87, blurRadius: 4)] : null,
                          ),
                        ),
                        if (tile.subtitle != null)
                          Text(
                            tile.subtitle!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: _light ? Colors.white70 : Theme.of(context).colorScheme.onSurfaceVariant,
                              shadows: _light ? const [Shadow(color: Colors.black87, blurRadius: 4)] : null,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            if (tile.badge != null)
              Positioned(
                top: 10,
                right: 10,
                child: Transform.rotate(
                  angle: 0.12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFFFD54F), Color(0xFFFF6F00)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
                      boxShadow: [
                        BoxShadow(color: const Color(0xFFFF6F00).withValues(alpha: 0.6), blurRadius: 8, spreadRadius: 0.5),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome, size: 11, color: Colors.black87),
                        const SizedBox(width: 3),
                        Text(
                          tile.badge!,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Color> _gradientColors(ColorScheme scheme) {
    final accent = tile.accentColor;
    if (accent == null) {
      return [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh];
    }
    final hsl = HSLColor.fromColor(accent);
    return [
      hsl.withLightness(0.30).withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0)).toColor(),
      hsl.withLightness(0.15).toColor(),
    ];
  }

  /// Background image (cover) plus a dark scrim, or nothing when absent.
  List<Widget> _background(ColorScheme scheme) {
    if (!_hasBg) return const [];
    return [
      Positioned.fill(child: _image(tile.bgAssetPath!, fit: BoxFit.cover, fallback: const SizedBox.shrink())),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.15), Colors.black.withValues(alpha: 0.6)],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _tileImage(ColorScheme scheme) {
    final path = tile.assetPath;
    if (path != null && _loadable(path)) {
      return _image(path, fit: BoxFit.contain, fallback: _fallbackIcon(scheme, 56));
    }
    return _fallbackIcon(scheme, 56);
  }

  /// True when [path] points at a bundled asset (assumed present) or an
  /// existing file. Bundled-asset misses still fall back via errorBuilder.
  bool _loadable(String? path) =>
      path != null && (path.startsWith('assets/') || File(path).existsSync());

  Widget _image(String path, {double? width, double? height, BoxFit? fit, required Widget fallback}) {
    final isAsset = path.startsWith('assets/');
    if (path.toLowerCase().endsWith('.svg')) {
      return isAsset
          ? SvgPicture.asset(path, width: width, height: height, fit: fit ?? BoxFit.contain)
          : SvgPicture.file(File(path), width: width, height: height, fit: fit ?? BoxFit.contain);
    }
    return isAsset
        ? Image.asset(path, width: width, height: height, fit: fit, errorBuilder: (_, __, ___) => fallback)
        : Image.file(File(path), width: width, height: height, fit: fit, errorBuilder: (_, __, ___) => fallback);
  }

  Widget _fallbackIcon(ColorScheme scheme, double size) =>
      Icon(tile.icon, size: size, color: _light ? Colors.white : scheme.primary);
}
