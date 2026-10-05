import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

void main() {
  setUp(() {
    // Reset to defaults
    Handheld.current = false;
    Handheld.framebuffer = false;
  });

  tearDown(() {
    // Reset to defaults
    Handheld.current = false;
    Handheld.framebuffer = false;
  });

  testWidgets('framebuffer mode disables page transitions', (WidgetTester tester) async {
    Handheld.framebuffer = true;

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => nav.currentState!.push(
                MaterialPageRoute(builder: (c) => const _SecondPage()),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(),
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadePageTransitionsBuilder(),
              TargetPlatform.iOS: FadePageTransitionsBuilder(),
              TargetPlatform.linux: FadePageTransitionsBuilder(),
              TargetPlatform.macOS: FadePageTransitionsBuilder(),
              TargetPlatform.windows: FadePageTransitionsBuilder(),
              TargetPlatform.fuchsia: FadePageTransitionsBuilder(),
            },
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    // Push second page
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    // The button should not be visible anymore since transition is instant
    expect(find.text('Go'), findsNothing);
  });

  testWidgets('normal mode allows page transitions', (WidgetTester tester) async {
    Handheld.framebuffer = false;

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => nav.currentState!.push(
                MaterialPageRoute(builder: (c) => const _SecondPage()),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
        theme: ThemeData(
          colorScheme: const ColorScheme.dark(),
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              TargetPlatform.android: FadePageTransitionsBuilder(),
              TargetPlatform.iOS: FadePageTransitionsBuilder(),
              TargetPlatform.linux: FadePageTransitionsBuilder(),
              TargetPlatform.macOS: FadePageTransitionsBuilder(),
              TargetPlatform.windows: FadePageTransitionsBuilder(),
              TargetPlatform.fuchsia: FadePageTransitionsBuilder(),
            },
          ),
        ),
      ),
    );

    await tester.pump();
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    // Push second page
    await tester.tap(find.text('Go'));
    // Settles the full animation
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Go'), findsNothing);
  });

  testWidgets('app theme respects Handheld.framebuffer setting', (WidgetTester tester) async {
    Handheld.framebuffer = true;

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => nav.currentState!.push(
                MaterialPageRoute(builder: (c) => const _SecondPage()),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
        theme: _buildTheme(),
      ),
    );

    await tester.pump();
    expect(find.text('Go'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    // Push second page
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
    // The button should not be visible anymore
    expect(find.text('Go'), findsNothing);
  });
}

/// A simple PageTransitionsBuilder that fades in the new page.
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _SecondPage extends StatelessWidget {
  const _SecondPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Second')),
      body: const Center(child: Text('Second Page')),
    );
  }
}

ThemeData _buildTheme() {
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
    pageTransitionsTheme: Handheld.framebuffer
        ? PageTransitionsTheme(
            builders: {
              TargetPlatform.android: _NoOpPageTransitionsBuilder(),
              TargetPlatform.iOS: _NoOpPageTransitionsBuilder(),
              TargetPlatform.linux: _NoOpPageTransitionsBuilder(),
              TargetPlatform.macOS: _NoOpPageTransitionsBuilder(),
              TargetPlatform.windows: _NoOpPageTransitionsBuilder(),
              TargetPlatform.fuchsia: _NoOpPageTransitionsBuilder(),
            },
          )
        : null,
  );
}

/// A PageTransitionsBuilder that returns the child unchanged (no transition).
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
