import 'package:flutter/widgets.dart';
import 'package:retro_toolbox/companion/companion_app.dart';

/// Started by the native side in a second engine on the other display.
@pragma('vm:entry-point')
void companionMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CompanionApp());
}
