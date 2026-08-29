import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/utils/formatters.dart';

class GameBoxart extends StatelessWidget {
  final Game game;
  final double size;
  final Widget? placeholder;

  const GameBoxart({
    super.key,
    required this.game,
    this.size = 40,
    this.placeholder,
  });

  Widget _infoOverlay(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            game.displayTitle,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (game.size > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.sd_storage_outlined, size: 14, color: Colors.white70),
                const SizedBox(width: 6),
                Text(formatBytes(game.size), style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boxart = game.boxart;

    if (boxart == null) {
      return placeholder ?? _DefaultPlaceholder(size: size);
    }

    return Container(
      key: ValueKey('boxart_${game.gameId}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => Dialog(
              insetPadding: EdgeInsets.zero,
              backgroundColor: Colors.transparent,
              child: Stack(
                children: [
                  PhotoView(
                    imageProvider: CachedNetworkImageProvider(boxart),
                    backgroundDecoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4)),
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 3.0,
                    onTapUp: (context, details, controllerValue) => Navigator.of(context).pop(),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    // IgnorePointer so taps still reach PhotoView to dismiss.
                    child: IgnorePointer(child: _infoOverlay(context)),
                  ),
                ],
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(1),
          child: CachedNetworkImage(
            imageUrl: boxart,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) => _DefaultPlaceholder(size: size),
            errorListener: (value) => debugPrint('Error loading boxart: $value'),
            progressIndicatorBuilder: (context, url, downloadProgress) => Container(
              width: size,
              height: size,
              color: Theme.of(context).colorScheme.surface,
              child: Center(
                child: SizedBox(
                  width: size * 0.4,
                  height: size * 0.4,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: downloadProgress.progress,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DefaultPlaceholder extends StatelessWidget {
  final double size;

  const _DefaultPlaceholder({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: size * 0.5,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
