import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/app.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A status colour hardcoded in lib/ instead of read from the style.
final _hardcodedStatus = RegExp(r'Colors\.(green|orange|red|redAccent|amberAccent|greenAccent|orangeAccent)\b');

void main() {
  test('the five sets carry the spec values', () {
    expect(StyleTokens.forStyle(CardStyle.classic).accent, const Color(0xFFB8A1FF));
    expect(StyleTokens.forStyle(CardStyle.vita).accent, const Color(0xFFFFFFFF));
    expect(StyleTokens.forStyle(CardStyle.threeDs).surface, const Color(0xFF2A2D33));
    expect(StyleTokens.forStyle(CardStyle.wii).accent, const Color(0xFF34BEED));
    expect(StyleTokens.forStyle(CardStyle.switchStyle).surface, const Color(0xFF15171A));
    expect(StyleTokens.forStyle(CardStyle.switchStyle).buttonRadius, 8);
    for (final s in CardStyle.values) {
      final k = StyleTokens.forStyle(s);
      expect((k.success, k.warning, k.error), (const Color(0xFF5EE3A1), const Color(0xFFFFB547), const Color(0xFFFF6B81)), reason: s.name);
      expect(k.area(AppArea.tools), const Color(0xFF4A7BF0), reason: s.name);
    }
  });

  test('lerp lands on both ends', () {
    const a = StyleTokens.classic, b = StyleTokens.switchStyle;
    expect(a.lerp(b, 0), a);
    expect(a.lerp(b, 1), b);
    expect(a.lerp(b, 0.5).accent, Color.lerp(a.accent, b.accent, 0.5));
    expect(a.copyWith(accent: b.accent).accent, b.accent);
  });

  for (final style in CardStyle.values) {
    final k = StyleTokens.forStyle(style);

    test('${style.name}: the theme is built from its tokens', () {
      final t = appTheme(style);
      expect(t.extension<StyleTokens>(), k);
      expect(t.colorScheme.primary, k.accent);
      expect(t.colorScheme.onPrimary, k.onAccent);
      expect(t.colorScheme.surface, k.surface);
      expect(t.colorScheme.error, k.error);
      expect(t.scaffoldBackgroundColor, k.surface);
    });

    testWidgets('${style.name}: a Switch and a FilledButton take the accent', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: appTheme(style),
        home: Scaffold(
          body: Column(children: [
            Switch(value: true, onChanged: (_) {}),
            FilledButton(onPressed: () {}, child: const Text('Go')),
          ]),
        ),
      ));
      expect(StyleTokens.of(t.element(find.byType(Switch))), k);
      // The track is the first rounded rect the switch paints.
      expect(Material.of(t.element(find.byType(Switch))), paints..rrect(color: k.accent));
      final button = t.widget<Material>(find.descendant(of: find.byType(FilledButton), matching: find.byType(Material)));
      expect(button.color, k.accent);
      expect(button.textStyle?.color, k.onAccent);
    });
  }

  testWidgets('StyleTokens.of is Classic without the app theme', (t) async {
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(StyleTokens.of(t.element(find.byType(SizedBox))), StyleTokens.classic);
  });

  testWidgets('the app restyles when the card style changes', (t) async {
    SharedPreferences.setMockInitialValues({'setup_wizard_seen': true});
    final c = ProviderContainer(overrides: [patchersProvider.overrideWith((ref) async => [])]);
    addTearDown(c.dispose);
    await t.runAsync(() => c.read(styleProvider.notifier).loaded);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const RetroToolboxApp()));
    await t.pump();
    ThemeData theme() => Theme.of(t.element(find.byType(Scaffold).first));
    expect(theme().colorScheme.primary, StyleTokens.classic.accent);
    await t.runAsync(() => c.read(styleProvider.notifier).setCards(CardStyle.switchStyle));
    await t.pumpAndSettle();
    expect(theme().colorScheme.primary, StyleTokens.switchStyle.accent);
  });

  test('no status colour is hardcoded in lib/ outside the card styles', () {
    // The pattern must catch what it is meant to catch.
    expect(_hardcodedStatus.hasMatch('color: Colors.green,'), isTrue);
    expect(_hardcodedStatus.hasMatch('Colors.red.shade600'), isTrue);
    expect(_hardcodedStatus.hasMatch('Colors.greenery'), isFalse);
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')).toList();
    expect(files.length, greaterThan(100));
    final hits = <String>[];
    for (final f in files) {
      if (f.path.contains('${Platform.pathSeparator}card_styles${Platform.pathSeparator}')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (_hardcodedStatus.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(hits, isEmpty);
  });
}
