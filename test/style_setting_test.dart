import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';
import 'package:retro_toolbox/widgets/settings/style_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder swatch(String name) => find.byKey(Key('swatch-$name'));

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester t, {Future<String?> Function()? pick}) async {
    SharedPreferences.setMockInitialValues({});
    await t.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    container = ProviderContainer();
    addTearDown(container.dispose);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: nav,
        builder: (c, child) => DpadScope(navigatorKey: nav, child: child!),
        home: Scaffold(body: SingleChildScrollView(child: StyleSettingRows(pickImage: pick))),
      ),
    ));
    await t.pump();
  }

  AppStyle style() => container.read(styleProvider);

  test('the section comes right after Library', () {
    final v = SettingsSection.values;
    expect(v[v.indexOf(SettingsSection.library) + 1], SettingsSection.style);
    expect(SettingsSection.style.label, 'Style');
    expect(SettingsSection.style.hint, 'Background and cards');
  });

  testWidgets('shows Background, Colours and Cards, not Picture', (t) async {
    await pump(t);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Colours'), findsOneWidget);
    expect(find.text('Cards'), findsOneWidget);
    expect(find.text('Picture'), findsNothing);
    for (final k in BackdropKind.values) {
      expect(find.text(k.label), findsOneWidget);
    }
    for (final c in CardStyle.values) {
      expect(find.text(c.label), findsOneWidget);
    }
    expect(swatch('Retro Toolbox'), findsOneWidget);
    expect(find.byType(Tooltip), findsNWidgets(backdropPresets.length));
  });

  testWidgets('each choice is named once: no group title repeats the row under it', (t) async {
    await pump(t);
    for (final label in ['BACKGROUND', 'CARDS', 'Background', 'Cards', 'Game list']) {
      expect(find.text(label), label == label.toUpperCase() ? findsNothing : findsOneWidget, reason: label);
    }
    expect(find.byType(SettingsHeader), findsNothing);
    // The style first, then what goes behind it.
    double top(String label) => t.getTopLeft(find.text(label)).dy;
    expect(top('Cards'), lessThan(top('Background')));
    expect(top('Background'), lessThan(top('Colours')));
  });

  testWidgets('tapping a background and a card style stores them', (t) async {
    await pump(t);
    await t.tap(find.text('Aurora'));
    await t.pump();
    expect(style().shownBackdrop.kind, BackdropKind.aurora);
    await t.tap(find.text('Wii'));
    await t.pump();
    expect(style().cards, CardStyle.wii);
  });

  testWidgets('a swatch sets top and bottom', (t) async {
    await pump(t);
    await t.tap(swatch('Teal on black'));
    await t.pump();
    final (top, bottom) = backdropPresets['Teal on black']!;
    expect(style().shownBackdrop.top, top);
    expect(style().shownBackdrop.bottom, bottom);
  });

  testWidgets('Image hides Colours and shows Picture; Choose stores the path', (t) async {
    await pump(t, pick: () async => '/pics/wall.png');
    await t.tap(find.text('Image'));
    await t.pump();
    expect(find.text('Colours'), findsNothing);
    expect(find.text('Picture'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    await t.tap(find.text('Picture'));
    await t.pump();
    expect(style().shownBackdrop.imagePath, '/pics/wall.png');
    expect(find.text('wall.png'), findsOneWidget);
  });

  testWidgets('a cancelled Choose keeps the path', (t) async {
    await pump(t, pick: () async => null);
    await t.tap(find.text('Image'));
    await t.pump();
    await t.tap(find.text('Picture'));
    await t.pump();
    expect(style().shownBackdrop.imagePath, isNull);
  });

  /// Tabs until focus is inside [row], then presses X (Reset) on it.
  Future<void> pressX(WidgetTester t, Finder row) async {
    bool inside() => find.descendant(of: row, matching: find.byElementPredicate((e) => e == FocusManager.instance.primaryFocus?.context)).evaluate().isNotEmpty;
    for (var i = 0; i < 30 && !inside(); i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(inside(), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonX);
    await t.pump();
  }

  testWidgets('the game list row sits under Cards; a tap stores the layout, X resets it', (t) async {
    await pump(t);
    final row = find.byType(SettingsSegmentedRow<GameLayout>);
    expect(t.getTopLeft(row).dy, greaterThan(t.getTopLeft(find.byType(SettingsSegmentedRow<CardStyle>)).dy));
    expect(find.descendant(of: row, matching: find.text('Game list')), findsOneWidget);
    for (final l in GameLayout.values) {
      expect(find.descendant(of: row, matching: find.text(l.label)), findsOneWidget);
    }
    await t.tap(find.text('Cover flow'));
    await t.pump();
    expect(style().gameLayout, GameLayout.coverFlow);
    await pressX(t, row);
    expect(style().gameLayout, GameLayout.styleDefault);
  });

  testWidgets('each row resets to its default', (t) async {
    await pump(t, pick: () async => '/pics/wall.png');
    await t.tap(find.text('Wii'));
    await t.pump();
    await pressX(t, find.byType(SettingsSegmentedRow<CardStyle>));
    expect(style().cards, CardStyle.classic);

    await t.tap(swatch('Ash'));
    await t.pump();
    expect(find.text('Reset'), findsOneWidget);
    await t.tap(find.text('Reset'));
    await t.pump();
    // Back to Classic's own colours, and with its own kind that is no pick at all.
    expect(style().shownBackdrop, StyleTokens.classic.backdrop);
    expect(style().backdrop, isNull);
    expect(find.text('Reset'), findsNothing);

    await t.tap(find.text('Image'));
    await t.pump();
    await t.tap(find.text('Picture'));
    await t.pump();
    expect(find.text('Reset'), findsOneWidget);
    await t.tap(find.text('Reset'));
    await t.pump();
    expect(style().shownBackdrop.imagePath, isNull);
    expect(style().shownBackdrop.kind, BackdropKind.image);
    expect(find.text('Reset'), findsNothing);

    await pressX(t, find.byType(SettingsSegmentedRow<BackdropKind>));
    expect(style().shownBackdrop.kind, StyleTokens.classic.backdrop.kind);
  });

  testWidgets('Reset goes back to the card style\'s own backdrop', (t) async {
    await pump(t);
    await t.tap(find.text('Switch'));
    await t.pump();
    expect(style().backdrop, isNull);
    expect(style().shownBackdrop, StyleTokens.switchStyle.backdrop);
    await t.tap(find.text('Drift'));
    await t.pump();
    expect(style().backdrop, StyleTokens.switchStyle.backdrop.copyWith(kind: BackdropKind.drift));
    await pressX(t, find.byType(SettingsSegmentedRow<BackdropKind>));
    expect(style().backdrop, isNull);
    expect(style().shownBackdrop.kind, BackdropKind.flat);
  });

  testWidgets('d-pad: one stop per swatch, right moves, A picks', (t) async {
    await pump(t);
    bool has(String n) => find
        .descendant(of: swatch(n), matching: find.byElementPredicate((e) => e == FocusManager.instance.primaryFocus?.context))
        .evaluate()
        .isNotEmpty;
    for (var i = 0; i < 30 && !has('Retro Toolbox'); i++) {
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
    }
    expect(has('Retro Toolbox'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pump();
    expect(has('Pink on black'), isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pump();
    expect(style().shownBackdrop.top, backdropPresets['Pink on black']!.$1);
  });
}
