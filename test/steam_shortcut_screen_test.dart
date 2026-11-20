import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/screens/steam_shortcut_screen.dart';
import 'package:retro_toolbox/services/steam_service.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kit/kit_support.dart';

class _Picker extends FilePicker with MockPlatformInterfaceMixin {
  _Picker(this.dir);
  final String dir;
  var asked = 0;
  @override
  Future<String?> getDirectoryPath({String? dialogTitle, bool lockParentWindow = false, String? initialDirectory}) async {
    asked++;
    return dir;
  }
}

/// The store answers every search with [games]; writing fails for [failing].
class _Steam extends SteamService {
  _Steam(this.games, {this.failing = const {}});
  final List<SteamGame> games;
  final Set<String> failing;
  final written = <(String, String)>[];
  @override
  Future<SteamSearchPage> search(String query, {int start = 0}) async => SteamSearchPage(results: start == 0 ? games : const [], hasMore: false);
  @override
  Future<Map<String, String>> createShortcuts(List<SteamGame> games, String folder) async {
    final errors = <String, String>{};
    for (final g in games) {
      if (failing.contains(g.name)) {
        errors[g.name] = 'Permission denied';
      } else {
        written.add((g.name, folder));
      }
    }
    return errors;
  }
}

final _games = <SteamGame>[SteamGame(appid: 1, name: 'Celeste'), SteamGame(appid: 2, name: 'Hades'), SteamGame(appid: 3, name: 'Hollow Knight')];

void main() {
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, (_) async => '/tmp');
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(pathProvider, null));

  Future<void> search(WidgetTester t) async {
    await t.enterText(find.byType(TextField), 'h');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
  }

  testWidgets('the remembered folder shows in Save to; Start writes the marked games there', (t) async {
    SharedPreferences.setMockInitialValues({'steam_shortcut_last_dir': '/roms/steam'});
    final picker = _Picker('/elsewhere');
    FilePicker.platform = picker;
    final steam = _Steam(_games);
    await pumpKit(t, SteamShortcutScreen(service: steam), style: CardStyle.switchStyle);
    await t.pumpAndSettle();
    expect(find.descendant(of: find.widgetWithText(Slot, 'Save to'), matching: find.textContaining('steam')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNull);

    await search(t);
    await t.tap(find.text('Celeste'));
    await t.pump();
    await t.tap(find.text('Hades'));
    await t.pump();
    expect(find.text('Create 2 shortcuts'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();

    expect(steam.written, [('Celeste', '/roms/steam'), ('Hades', '/roms/steam')]);
    expect(picker.asked, 0, reason: 'the folder is already known');
    expect(find.byKey(const ValueKey('kit-status-done')), findsOneWidget);
    expect(find.textContaining('Created 2 shortcuts'), findsOneWidget);
    expect(find.text('Create shortcuts'), findsOneWidget, reason: 'written games leave the selection');
  });

  testWidgets('with no folder yet, Start asks for one first', (t) async {
    SharedPreferences.setMockInitialValues({});
    final picker = _Picker('/roms/steam');
    FilePicker.platform = picker;
    final steam = _Steam(_games);
    await pumpKit(t, SteamShortcutScreen(service: steam), style: CardStyle.switchStyle);
    await search(t);
    await t.tap(find.text('Celeste'));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(picker.asked, 1);
    expect(steam.written, [('Celeste', '/roms/steam')]);
  });

  testWidgets('a failed game stays marked, and the status says which and why', (t) async {
    SharedPreferences.setMockInitialValues({'steam_shortcut_last_dir': '/roms/steam'});
    final steam = _Steam(_games, failing: {'Hades'});
    await pumpKit(t, SteamShortcutScreen(service: steam), style: CardStyle.switchStyle);
    await search(t);
    await t.tap(find.text('Celeste'));
    await t.pump();
    await t.tap(find.text('Hades'));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    final status = find.byKey(const ValueKey('kit-status-done'));
    expect(find.descendant(of: status, matching: find.textContaining('1 failed')), findsOneWidget);
    expect(find.descendant(of: status, matching: find.text('Hades')), findsOneWidget);
    expect(find.descendant(of: status, matching: find.text('Permission denied')), findsOneWidget);
    expect(find.text('Create 1 shortcut'), findsOneWidget);
  });

  testWidgets('a game marked in an earlier search stays listed and marked', (t) async {
    SharedPreferences.setMockInitialValues({});
    final steam = _Steam(_games);
    await pumpKit(t, SteamShortcutScreen(service: steam), style: CardStyle.switchStyle);
    await search(t);
    await t.tap(find.text('Celeste'));
    await t.pump();
    steam.games
      ..clear()
      ..add(const SteamGame(appid: 9, name: 'Portal'));
    await search(t);
    expect(find.text('MARKED EARLIER'), findsOneWidget);
    expect(find.text('Celeste'), findsOneWidget);
    expect(find.text('Create 1 shortcut'), findsOneWidget);
  });
}
