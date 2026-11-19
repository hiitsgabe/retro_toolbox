import 'package:flutter/foundation.dart';
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
  Future<void> open(WidgetTester t, String label) async {
    final text = find.text(label);
    await t.tap(text.evaluate().isEmpty ? find.byKey(ValueKey(label)) : text);
    await frames(t, 8);
  }

  testWidgets('home menu', (t) async {
    await launch(t, const MenuScreen(), overrides: overrides);
    await snap(t, 'menu_home');
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

  testWidgets('settings style', (t) async {
    await launch(t, const SettingsScreen(section: SettingsSection.style), overrides: [...overrides, ...consolesOverrides()]);
    await realWait(t, 600);
    await snap(t, 'menu_settings_style');
  }, skip: !screenshotsEnabled);
}
