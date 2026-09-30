import 'package:flutter/material.dart';
import 'package:roms_downloader/screens/menu_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class RomsDownloaderApp extends StatelessWidget {
  const RomsDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Retro Toolbox',
      debugShowCheckedModeBanner: false,
      // Always dark: screens are designed for the dark palette and look broken
      // when a device's system theme is light.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DEF),
          brightness: Brightness.dark,
        ),
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
      home: const MenuScreen(),
    );
  }
}
