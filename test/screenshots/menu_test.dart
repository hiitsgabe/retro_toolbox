import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/sports_provider.dart';
import 'package:retro_toolbox/screens/menu_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';

import 'support.dart';
import 'fakes.dart';

void main() {
  screenshotSetUp();
  final overrides = [patchersProvider.overrideWith((ref) async => [])];

  // 3DS shows only the focused tile's name; its slots are keyed by label.
  // Switch on a phone is one row wider than the screen and builds lazily:
  // walk focus right until the tile is built, then bring it on screen.
  Future<void> open(WidgetTester t, String label) async {
    final text = find.text(label);
    final slot = find.byKey(ValueKey(label));
    for (var i = 0; i < 8 && text.evaluate().isEmpty && slot.evaluate().isEmpty; i++) {
      await key(t, LogicalKeyboardKey.arrowRight);
    }
    // The tile's own ink: a Vita label under its bubble takes no tap.
    final ink = find.descendant(of: slot, matching: find.byType(InkWell));
    final target = ink.evaluate().isNotEmpty ? ink.first : (text.evaluate().isEmpty ? slot : text);
    await t.ensureVisible(target);
    await frames(t, 4);
    await t.tap(target);
    await frames(t, 8);
    // 3DS: the first tap on a slot that is not selected only selects it.
    if (slot.evaluate().isNotEmpty && find.byKey(const ValueKey('3ds-menu')).evaluate().isNotEmpty) {
      await t.tap(target);
      await frames(t, 8);
    }
  }

  testWidgets('home menu', (t) async {
    await launch(t, const MenuScreen(), overrides: overrides);
    await snap(t, 'menu_home');
  }, skip: !screenshotsEnabled);

  // As on an Android device (Odin 2, phone): Save Sync is on the menu too.
  testWidgets('home menu android', (t) async {
    MenuScreen.saveSyncShownForTest = true;
    addTearDown(() => MenuScreen.saveSyncShownForTest = null);
    await launch(t, const MenuScreen(), overrides: overrides);
    await snap(t, 'menu_home_android');
  }, skip: !screenshotsEnabled);

  // Focus on the second tile: Classic lifts the cartridge.
  testWidgets('home menu focused', (t) async {
    await launch(t, const MenuScreen(), overrides: overrides);
    await key(t, LogicalKeyboardKey.arrowRight);
    await snap(t, 'menu_home_focused');
  }, skip: !screenshotsEnabled);

  // Holding A lifts a tile to move it: each style shows it its own way, and
  // the pad's hint row is over the menu.
  testWidgets('home menu moving a tile', (t) async {
    await launch(t, const MenuScreen(), overrides: overrides);
    await key(t, LogicalKeyboardKey.arrowRight);
    await t.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await frames(t, 7);
    await t.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await key(t, LogicalKeyboardKey.arrowRight);
    await snap(t, 'menu_home_moving');
  }, skip: !screenshotsEnabled);

  testWidgets('tools submenu', (t) async {
    await launch(t, const MenuScreen(), overrides: overrides);
    await open(t, 'Tools');
    await snap(t, 'menu_tools');
  }, skip: !screenshotsEnabled);

  testWidgets('servers submenu', (t) async {
    await launch(t, const MenuScreen(), overrides: overrides);
    await open(t, 'Servers');
    await snap(t, 'menu_servers');
  }, skip: !screenshotsEnabled);

  testWidgets('settings top', (t) async {
    final c = await launch(t, const SettingsScreen(), overrides: [...overrides, ...consolesOverrides()]);
    await realWait(t, 600);
    launchboxLoaded(c);
    await snap(t, 'menu_settings_top');
  }, skip: !screenshotsEnabled);

  // The L1/R1 hint shows only after gamepad input (any key), not after a tap.
  for (final pad in [false, true]) {
    testWidgets('settings hint ${pad ? 'gamepad' : 'touch'}', (t) async {
      final c = await launch(t, const SettingsScreen(showControllerHints: true), overrides: [...overrides, ...consolesOverrides()]);
      await realWait(t, 600);
      launchboxLoaded(c);
      if (pad) await key(t, LogicalKeyboardKey.shiftLeft);
      await snap(t, 'menu_settings_hint_${pad ? 'gamepad' : 'touch'}');
    }, skip: !screenshotsEnabled);
  }

  testWidgets('settings style', (t) async {
    await launch(t, const SettingsScreen(section: SettingsSection.style), overrides: [...overrides, ...consolesOverrides()]);
    await realWait(t, 600);
    await snap(t, 'menu_settings_style', keep: true);
    // The game layout row, under Cards, is below the fold on landscape screens.
    await t.ensureVisible(find.text('Game list'));
    await snap(t, 'menu_settings_style_game_list');
  }, skip: !screenshotsEnabled);
}
