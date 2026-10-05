import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// A PageTransitionsBuilder that returns the child unchanged (no animation).
/// Used in framebuffer mode where every frame is a CPU readback.
class _NoOpPageTransitionsBuilder extends PageTransitionsBuilder {
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// The app's theme. Always dark: screens are designed for the dark palette and
/// look broken when a device's system theme is light. Framebuffer mode drops
/// page transitions.
ThemeData appTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF7C4DEF),
    brightness: Brightness.dark,
  );
  return ThemeData(
    colorScheme: colorScheme,
    focusColor: colorScheme.primary.withValues(alpha: 0.24),
    useMaterial3: true,
    fontFamily: 'ChakraPetch',
    scaffoldBackgroundColor: const Color(0xFF17102B),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    pageTransitionsTheme: Handheld.framebuffer ? PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: _NoOpPageTransitionsBuilder()}) : null,
  );
}

class RetroToolboxApp extends ConsumerWidget {
  const RetroToolboxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builtInKeyboard = ref.watch(settingsProvider.select((s) => s.useOnScreenKeyboard));
    return MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [DpadScope.routeObserver],
      title: 'Retro Toolbox',
      debugShowCheckedModeBanner: false,
      theme: appTheme(),
      builder: (context, child) => DpadScope(
        navigatorKey: navigatorKey,
        onScreenKeyboard: Handheld.current || builtInKeyboard,
        // Select opens the task manager anywhere.
        onOptions: () {
          final c = navigatorKey.currentContext;
          if (c != null) TaskPanelModal.show(c);
        },
        child: child!,
      ),
      home: const MenuScreen(),
    );
  }
}
