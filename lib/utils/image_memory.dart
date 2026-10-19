import 'package:flutter/painting.dart';

/// Pixel width to decode a thumbnail at: the larger side of its box in device
/// pixels, rounded up to 64 so nearby sizes share a cache entry. Width only,
/// so the aspect ratio is kept and BoxFit.cover doesn't upscale portrait art.
int thumbnailDecodeWidth(double width, double height, double devicePixelRatio) {
  final px = (width > height ? width : height) * devicePixelRatio;
  return (px / 64).ceil().clamp(1, 1 << 16) * 64;
}

/// Phones and handhelds have 1-2 GB of RAM: keep fewer decoded images than
/// Flutter's 100 MB / 1000 images default.
void capImageCache(ImageCache cache) {
  cache.maximumSizeBytes = 48 << 20;
  cache.maximumSize = 300;
}
