import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// The PACK MODE tile: it represents a **game**, not a file.
class PackGridItem extends StatelessWidget {
  final String title;

  /// Pack cover URL. Null falls back to the missing-cover placeholder.
  final String? coverUrl;

  /// Whether any addon has a file for this game. It is the only axis that
  /// changes how the tile is drawn.
  final bool hasSource;

  /// Whether some version of this game is already on disk. Comes `false` until
  /// the scan finishes, because a wrong border is worse than no border.
  final bool isOwned;

  final bool isSelected;

  /// Whether a selection is active. With an empty selection the checkbox is
  /// hidden on every tile so the cover stays clean.
  final bool selectionActive;

  final double aspectRatio;

  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleSelection;

  const PackGridItem({
    super.key,
    required this.title,
    required this.hasSource,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleSelection,
    this.coverUrl,
    this.isOwned = false,
    this.isSelected = false,
    this.selectionActive = false,
    this.aspectRatio = 0.75,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color? borderColor = isSelected
        ? scheme.primary
        : isOwned
            ? scheme.secondaryContainer
            : null;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        key: const ValueKey('pack-tile-border'),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: borderColor ?? Theme.of(context).dividerColor.withValues(alpha: 0.2),
            width: borderColor != null ? 3 : 1,
          ),
        ),
        child: Tooltip(
          message: title,
          // Do not change to `longPress`: the tooltip's own recognizer wins the
          // gesture arena and swallows the outer long press that drives
          // selection. `manual` keeps only the desktop hover.
          triggerMode: TooltipTriggerMode.manual,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: aspectRatio,
                  child: _cover(context),
                ),
                if (selectionActive)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => onToggleSelection(),
                        shape: const CircleBorder(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                // Two redundant "no source" signals: the desaturated cover and
                // this icon. Grey alone reads as "loading", and many period
                // covers are already nearly monochrome.
                if (!hasSource)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.cloud_off_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.9),
                      shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 8, offset: Offset(0, 1)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final url = coverUrl;
    final cover = url == null
        ? _placeholder(context)
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (context, _, __) => _placeholder(context),
            errorListener: (_) {},
          );
    if (hasSource) return cover;
    // Zero-saturation matrix: greys the art while preserving its brightness.
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: cover,
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.3),
            scheme.secondaryContainer.withValues(alpha: 0.2),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.videogame_asset_rounded,
          size: 32,
          color: scheme.primary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
