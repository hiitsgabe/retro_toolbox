import 'launchbox_models.dart';

/// LaunchBox region names for an app region (No-Intro names); anything not
/// listed is compared as is.
const _regions = {
  'USA': {'North America', 'United States'},
  'Europe': {'Europe'},
  'Japan': {'Japan'},
  'World': {'World'},
};

/// Lower is better: the game's own region, North America, World, no region,
/// then any other.
int _rank(LaunchboxImage image, String gameRegion) {
  final region = image.region;
  if (region == null) return 3;
  if ((_regions[gameRegion] ?? {gameRegion}).contains(region)) return 0;
  if (region == 'North America') return 1;
  if (region == 'World') return 2;
  return 4;
}

/// The image of [type] best suited to a game from [gameRegion] (the app's
/// region names: "USA", "Europe", "Japan", "World", ...): the same region
/// first, then North America, then World, then one with no region, then any.
LaunchboxImage? pickLaunchboxImage(List<LaunchboxImage> images, LaunchboxImageType type, String gameRegion) =>
    launchboxImagesOf(images, type, gameRegion).firstOrNull;

/// All images of [type], in the order above (for the screenshot strip).
List<LaunchboxImage> launchboxImagesOf(List<LaunchboxImage> images, LaunchboxImageType type, String gameRegion) {
  // List.sort is not stable; the index keeps file order within a rank.
  final ranked = [
    for (final (n, i) in images.indexed)
      if (i.type == type) (rank: _rank(i, gameRegion), n: n, image: i),
  ]..sort((a, b) => a.rank != b.rank ? a.rank.compareTo(b.rank) : a.n.compareTo(b.n));
  return [for (final r in ranked) r.image];
}

/// What fills the hero's background: fanart, else a gameplay screenshot,
/// else the box art blurred, else nothing.
({String url, bool blur})? heroBackground(LaunchboxGame? lb, String gameRegion, String? boxart) {
  final images = lb?.images ?? const <LaunchboxImage>[];
  final art = pickLaunchboxImage(images, LaunchboxImageType.fanart, gameRegion) ?? pickLaunchboxImage(images, LaunchboxImageType.screenshot, gameRegion);
  if (art != null) return (url: art.url, blur: false);
  if (boxart != null) return (url: boxart, blur: true);
  return null;
}
