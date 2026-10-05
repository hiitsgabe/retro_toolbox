import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/screens/about_screen.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';

Widget _app(Widget home) => ProviderScope(child: MaterialApp(home: home));

void main() {
  late bool saved;
  setUp(() => saved = Handheld.current);
  tearDown(() => Handheld.current = saved);

  Future<void> pumpMenu(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_app(const MenuScreen()));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('handheld: no Servers tile, no unsupported tools', (t) async {
    Handheld.current = true;
    await pumpMenu(t);
    expect(find.text('Servers'), findsNothing);
    // Cover flow: first tap centres the card, second opens it.
    await t.tap(find.text('Tools'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tools'));
    await t.pumpAndSettle();
    expect(find.text('NSZ Decompress'), findsOneWidget);
    for (final l in ['Steam Shortcuts', 'CHD Converter']) {
      expect(find.text(l), findsNothing, reason: l);
    }
    // Shown only where RAR works (on Linux: when librar_native.so loaded).
    expect(find.text('Rar Decompress'), ArchiveExtractService.rarSupported() ? findsOneWidget : findsNothing);
  });

  testWidgets('non-handheld: Servers tile present', (t) async {
    Handheld.current = false;
    await pumpMenu(t);
    expect(find.text('Servers'), findsOneWidget);
  });

  testWidgets('handheld: About has no open/copy controls', (t) async {
    Handheld.current = true;
    await t.pumpWidget(_app(AboutScreen()));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Open Source'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    expect(find.byIcon(Icons.copy_rounded), findsNothing);
  });

  testWidgets('non-handheld: About shows open/copy controls', (t) async {
    Handheld.current = false;
    await t.pumpWidget(_app(AboutScreen()));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.open_in_new_rounded), findsWidgets);
    expect(find.byIcon(Icons.copy_rounded), findsWidgets);
  });
}
