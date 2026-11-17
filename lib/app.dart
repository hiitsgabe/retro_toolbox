import 'dart:io';

import 'package:flutter/material.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
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
    final app = MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [DpadScope.routeObserver, HomeScreen.routeObserver],
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
    return Platform.isAndroid ? _DualScreenLifecycle(child: app) : app;
  }
}

/// Starts the second screen once the app is up and closes or reopens it as
/// the app goes to the background and comes back.
class _DualScreenLifecycle extends ConsumerStatefulWidget {
  const _DualScreenLifecycle({required this.child});

  final Widget child;

  @override
  ConsumerState<_DualScreenLifecycle> createState() => _DualScreenLifecycleState();
}

class _DualScreenLifecycleState extends ConsumerState<_DualScreenLifecycle> {
  late final DualScreenNotifier _dualScreen;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _dualScreen = ref.read(dualScreenProvider.notifier);
    _lifecycle = AppLifecycleListener(onStateChange: _dualScreen.onLifecycle);
    WidgetsBinding.instance.addPostFrameCallback((_) => _dualScreen.init());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
