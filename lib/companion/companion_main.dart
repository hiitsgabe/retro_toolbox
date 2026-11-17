import 'package:flutter/widgets.dart';
import 'package:retro_toolbox/companion/companion_app.dart';

/// Started by the native side in a second engine on the other display.
@pragma('vm:entry-point')
void companionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  // A second engine has a second image cache (100 MB by default) on top of
  // the main one's, and the companion shows one game's pictures at a time.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 32 << 20;
  runApp(const CompanionApp());
}
