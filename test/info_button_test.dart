import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/screens/chd_convert_screen.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';
import 'package:retro_toolbox/screens/tinfoil_server_screen.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

class _FakeSettings extends StateNotifier<AppSettings> implements SettingsNotifier {
  _FakeSettings() : super(const AppSettings());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeTinfoil extends StateNotifier<TinfoilServerState> implements TinfoilServerNotifier {
  _FakeTinfoil() : super(const TinfoilServerState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Widget _app(Widget home) {
  final nav = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith((ref) => _FakeSettings()),
      tinfoilServerProvider.overrideWith((ref) => _FakeTinfoil()),
    ],
    child: MaterialApp(
      navigatorKey: nav,
      builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
      home: home,
    ),
  );
}

// The CHD screen spins a loader while it looks for chdman, so the sheet's
// animation is pumped by time instead of pumpAndSettle.
Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  testWidgets('the (i) opens a sheet with the title and the text, and B closes it', (t) async {
    await t.pumpWidget(_app(Scaffold(
      appBar: AppBar(title: const Text('Tool'), actions: const [InfoButton(icon: Icons.compress, title: 'Tool', text: 'What the tool does.')]),
    )));
    expect(find.text('What the tool does.'), findsNothing);
    expect(find.byTooltip('About this screen'), findsOneWidget);

    await t.tap(find.byIcon(Icons.info_outline));
    await _settle(t);
    expect(find.text('What the tool does.'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Tool')), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.byIcon(Icons.compress)), findsOneWidget);
    expect(find.text('Learn more'), findsNothing);

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await _settle(t);
    expect(find.text('What the tool does.'), findsNothing);
    expect(find.text('Tool'), findsOneWidget, reason: 'B closes the sheet, not the screen under it');
  });

  testWidgets('A on the focused (i) opens the sheet too', (t) async {
    await t.pumpWidget(_app(Scaffold(
      appBar: AppBar(title: const Text('Tool'), actions: const [InfoButton(icon: Icons.compress, text: 'What the tool does.')]),
    )));
    final button = find.descendant(of: find.byType(InfoButton), matching: find.byType(IconButton));
    Focus.of(t.element(find.byIcon(Icons.info_outline))).requestFocus();
    await t.pump();
    expect(Focus.of(t.element(find.byIcon(Icons.info_outline))).hasFocus, isTrue, reason: 'the d-pad can reach it');
    expect(button, findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await _settle(t);
    expect(find.text('What the tool does.'), findsOneWidget);
  });

  testWidgets('a tap outside closes the sheet', (t) async {
    await t.pumpWidget(_app(Scaffold(
      appBar: AppBar(title: const Text('Tool'), actions: const [InfoButton(icon: Icons.compress, text: 'What the tool does.')]),
    )));
    await t.tap(find.byIcon(Icons.info_outline));
    await _settle(t);
    await t.tapAt(const Offset(20, 20));
    await _settle(t);
    expect(find.text('What the tool does.'), findsNothing);
  });

  testWidgets('learnMore adds a Learn more button, hidden on the Linux handheld', (t) async {
    final sheet = _app(Scaffold(
      appBar: AppBar(
        title: const Text('Tool'),
        actions: [InfoButton(icon: Icons.sync, text: 'What it does.', learnMore: Uri.parse('https://example.com/page.html'))],
      ),
    ));
    await t.pumpWidget(sheet);
    await t.tap(find.byIcon(Icons.info_outline));
    await _settle(t);
    expect(find.text('Learn more'), findsOneWidget);

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonB);
    await _settle(t);
    Handheld.current = true;
    addTearDown(() => Handheld.current = false);
    await t.tap(find.byIcon(Icons.info_outline));
    await _settle(t);
    expect(find.text('What it does.'), findsOneWidget);
    expect(find.text('Learn more'), findsNothing, reason: 'the handheld has no browser to open it in');
  });

  // The screen's explanation is out of the body until the (i) is pressed.
  final screens = <String, (Widget, String)>{
    'CHD Converter': (const ChdConvertScreen(), 'Convert disc images to CHD to save space'),
    'Tinfoil Server': (const TinfoilServerScreen(), 'Hosts your game library over the local network'),
    'Collection Clean': (const CollectionCleanScreen(), 'Tidy up a game folder'),
  };
  for (final MapEntry(key: title, value: (screen, text)) in screens.entries) {
    testWidgets('$title explains itself from the (i), not the body', (t) async {
      await t.pumpWidget(_app(screen));
      await t.pump();
      expect(find.textContaining(text), findsNothing);
      // In the header: the AppBar, or the kit's header row.
      final info = find.byIcon(Icons.info_outline);
      expect(info, findsOneWidget);

      await t.tap(info);
      await _settle(t);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining(text)), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(title)), findsOneWidget);
    });
  }
}
