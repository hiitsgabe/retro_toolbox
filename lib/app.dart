import 'dart:io';

import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/widgets/dual_screen/companion_action_listener.dart';
import 'package:retro_toolbox/widgets/footer/task_panel_modal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/screens/home_screen.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
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

/// The app's theme for a card style: every colour, radius and Material
/// control comes from the style's [StyleTokens], so screens follow the style
/// without asking which one is active. Always dark: screens are designed for
/// a dark palette and look broken when a device's system theme is light.
/// Framebuffer mode drops page transitions.
ThemeData appTheme(CardStyle style) {
  final k = StyleTokens.forStyle(style);
  final scheme = _scheme(k);
  final panel = k.solidPanel;
  final muted = scheme.onSurfaceVariant;
  WidgetStateProperty<T> states<T>(T Function(Set<WidgetState> s) f) => WidgetStateProperty.resolveWith(f);
  bool on(Set<WidgetState> s) => s.contains(WidgetState.selected);
  bool off(Set<WidgetState> s) => s.contains(WidgetState.disabled);
  // Pills stay pills on buttons; boxes that hold text or a check stay boxes.
  final button = RoundedRectangleBorder(borderRadius: BorderRadius.circular(k.buttonRadius));
  final field = BorderRadius.circular(k.buttonRadius.clamp(0, 14).toDouble());
  final box = BorderRadius.circular(k.buttonRadius.clamp(2, 6).toDouble());
  final panelShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(k.panelRadius), side: BorderSide(color: k.panelLine));
  final disabledFg = scheme.onSurface.withValues(alpha: 0.38);
  final disabledBg = scheme.onSurface.withValues(alpha: 0.12);
  return ThemeData(
    colorScheme: scheme,
    focusColor: k.accent.withValues(alpha: 0.24),
    hoverColor: k.accent.withValues(alpha: 0.08),
    useMaterial3: true,
    fontFamily: 'ChakraPetch',
    scaffoldBackgroundColor: k.surface,
    canvasColor: k.surface,
    dividerColor: scheme.outlineVariant,
    extensions: [k],
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: states((s) => off(s) ? disabledFg : (on(s) ? k.onAccent : muted)),
      trackColor: states((s) => off(s) ? disabledBg : (on(s) ? k.accent : scheme.surfaceContainerHighest)),
      trackOutlineColor: states((s) => on(s) ? Colors.transparent : (off(s) ? disabledBg : scheme.outline)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: states((s) => on(s) ? (off(s) ? disabledFg : k.accent) : Colors.transparent),
      checkColor: WidgetStatePropertyAll(k.onAccent),
      side: WidgetStateBorderSide.resolveWith((s) => on(s) ? BorderSide.none : BorderSide(color: off(s) ? disabledFg : muted, width: 2)),
      shape: RoundedRectangleBorder(borderRadius: box),
    ),
    radioTheme: RadioThemeData(fillColor: states((s) => off(s) ? disabledFg : (on(s) ? k.accent : muted))),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: states((s) => off(s) ? disabledBg : k.accent),
        foregroundColor: states((s) => off(s) ? disabledFg : k.onAccent),
        overlayColor: WidgetStatePropertyAll(k.onAccent.withValues(alpha: 0.12)),
        shape: WidgetStatePropertyAll(button),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: states((s) => off(s) ? disabledFg : k.accent),
        side: states((s) => BorderSide(color: off(s) ? disabledBg : k.accent.withValues(alpha: 0.5))),
        overlayColor: WidgetStatePropertyAll(k.accent.withValues(alpha: 0.12)),
        shape: WidgetStatePropertyAll(button),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: states((s) => off(s) ? disabledFg : k.accent),
        overlayColor: WidgetStatePropertyAll(k.accent.withValues(alpha: 0.12)),
        shape: WidgetStatePropertyAll(button),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: k.panel,
      border: OutlineInputBorder(borderRadius: field, borderSide: BorderSide(color: k.panelLine)),
      enabledBorder: OutlineInputBorder(borderRadius: field, borderSide: BorderSide(color: k.panelLine)),
      focusedBorder: OutlineInputBorder(borderRadius: field, borderSide: BorderSide(color: k.accent, width: 2)),
      errorBorder: OutlineInputBorder(borderRadius: field, borderSide: BorderSide(color: k.error)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: field, borderSide: BorderSide(color: k.error, width: 2)),
      disabledBorder: OutlineInputBorder(borderRadius: field, borderSide: BorderSide(color: disabledBg)),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (s) => TextStyle(color: s.contains(WidgetState.error) ? k.error : (s.contains(WidgetState.focused) ? k.accent : muted)),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: k.accent,
      inactiveTrackColor: k.accent.withValues(alpha: 0.24),
      thumbColor: k.accent,
      overlayColor: k.accent.withValues(alpha: 0.12),
      valueIndicatorColor: k.accent,
      valueIndicatorTextStyle: TextStyle(color: k.onAccent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: k.panel,
      selectedColor: Color.alphaBlend(k.accent.withValues(alpha: 0.28), k.surface),
      checkmarkColor: k.accent,
      side: BorderSide(color: k.panelLine),
      shape: button,
    ),
    cardTheme: CardThemeData(color: k.panel, surfaceTintColor: Colors.transparent, elevation: 0, shape: panelShape),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      selectedColor: k.accent,
      selectedTileColor: k.accent.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(k.cardRadius.clamp(0, 12).toDouble())),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: panel,
      modalBackgroundColor: panel,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: muted,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(k.panelRadius))),
    ),
    dialogTheme: DialogThemeData(backgroundColor: panel, surfaceTintColor: Colors.transparent, shape: panelShape),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: scheme.onSurface, fontFamily: 'ChakraPetch'),
      actionTextColor: k.accent,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: k.accent,
      collapsedIconColor: muted,
      textColor: k.accent,
      shape: const Border(),
      collapsedShape: const Border(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: states((s) => on(s) ? k.accent : Colors.transparent),
        foregroundColor: states((s) => off(s) ? disabledFg : (on(s) ? k.onAccent : scheme.onSurface)),
        iconColor: states((s) => on(s) ? k.onAccent : muted),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        shape: WidgetStatePropertyAll(button),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: k.accent,
      foregroundColor: k.onAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 99).toDouble())),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: k.accent,
      linearTrackColor: k.accent.withValues(alpha: 0.2),
      circularTrackColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(color: panel, surfaceTintColor: Colors.transparent, shape: panelShape),
    textSelectionTheme: TextSelectionThemeData(cursorColor: k.accent, selectionColor: k.accent.withValues(alpha: 0.32), selectionHandleColor: k.accent),
    pageTransitionsTheme: Handheld.framebuffer ? PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: _NoOpPageTransitionsBuilder()}) : null,
  );
}

/// The Material colour roles from [k]. Built by hand rather than from a seed:
/// a seed's tonal palette brings in hues the style does not have (a cyan seed
/// gives violet tertiaries), and Switch has to stay grey and cyan.
ColorScheme _scheme(StyleTokens k) {
  // Text is near white with a breath of the accent, so it sits in the style.
  final onSurface = Color.lerp(const Color(0xFFEDEEF2), k.accent, 0.06)!;
  Color up(double t) => Color.lerp(k.surface, onSurface, t)!;
  Color wash(Color c, double a, Color over) => Color.alphaBlend(c.withValues(alpha: a), over);
  final onContainer = Color.lerp(k.accent, Colors.white, 0.6)!;
  return ColorScheme(
    brightness: Brightness.dark,
    primary: k.accent,
    onPrimary: k.onAccent,
    primaryContainer: wash(k.accent, 0.3, k.surface),
    onPrimaryContainer: onContainer,
    secondary: k.accent,
    onSecondary: k.onAccent,
    secondaryContainer: wash(k.accent, 0.22, up(0.08)),
    onSecondaryContainer: onContainer,
    tertiary: Color.lerp(k.accent, Colors.white, 0.35)!,
    onTertiary: k.onAccent,
    error: k.error,
    onError: const Color(0xFF3A0610),
    errorContainer: wash(k.error, 0.25, k.surface),
    onErrorContainer: Color.lerp(k.error, Colors.white, 0.6)!,
    surface: k.surface,
    onSurface: onSurface,
    onSurfaceVariant: Color.lerp(k.surface, onSurface, 0.72)!,
    surfaceDim: k.surface,
    surfaceBright: up(0.16),
    surfaceContainerLowest: Color.lerp(k.surface, Colors.black, 0.3)!,
    surfaceContainerLow: up(0.03),
    surfaceContainer: up(0.05),
    surfaceContainerHigh: up(0.08),
    surfaceContainerHighest: up(0.12),
    outline: up(0.4),
    outlineVariant: up(0.18),
    inverseSurface: onSurface,
    onInverseSurface: k.surface,
    inversePrimary: Color.lerp(k.accent, k.surface, 0.45)!,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
    scrim: Colors.black,
  );
}

class RetroToolboxApp extends ConsumerWidget {
  const RetroToolboxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final builtInKeyboard = ref.watch(settingsProvider.select((s) => s.useOnScreenKeyboard));
    final cards = ref.watch(styleProvider.select((s) => s.cards));
    final app = MaterialApp(
      navigatorKey: navigatorKey,
      navigatorObservers: [DpadScope.routeObserver, HomeScreen.routeObserver],
      title: 'Retro Toolbox',
      debugShowCheckedModeBanner: false,
      theme: appTheme(cards),
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
  Widget build(BuildContext context) => CompanionActionListener(
        navigatorContext: () => navigatorKey.currentContext,
        child: widget.child,
      );
}
