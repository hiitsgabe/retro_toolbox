import 'package:flutter/material.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class RetroToolboxApp extends StatelessWidget {
  const RetroToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C4DEF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Retro Toolbox',
      debugShowCheckedModeBanner: false,
      // Always dark: screens are designed for the dark palette and look broken
      // when a device's system theme is light.
      theme: ThemeData(
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
      ),
      builder: (context, child) =>
          DpadScope(navigatorKey: navigatorKey, child: child!),
      home: const MenuScreen(),
    );
  }
}
