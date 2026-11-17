import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/widgets/settings/handler_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  GameHandler? chosen(WidgetTester t) => t.widget<SettingsSegmentedRow<GameHandler?>>(find.byType(SettingsSegmentedRow<GameHandler?>)).selected;

  testWidgets('a disc console without a catalog handler can turn CHD on and off', (t) async {
    SharedPreferences.setMockInitialValues({});
    const console = Console(id: 'disc', name: 'Disc', urls: [], gameFilesFormat: ['.bin', '.cue', '.iso']);
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: HandlerSetting(console: console))),
    ));

    expect(find.text('Make CIA'), findsNothing);
    expect(chosen(t), isNull);
    expect(find.text('Leave the files as they are'), findsOneWidget);

    await t.tap(find.text('Make CHD'));
    await t.pumpAndSettle();
    expect(chosen(t), GameHandler.chdCompress);
    expect(find.text('.cue / .gdi / .iso to .chd'), findsOneWidget);

    await t.tap(find.text('Keep files'));
    await t.pumpAndSettle();
    expect(chosen(t), isNull);
  });

  testWidgets('left and right on the focused row step through the choices', (t) async {
    SharedPreferences.setMockInitialValues({});
    const console = Console(id: 'disc', name: 'Disc', urls: [], gameFilesFormat: ['.iso']);
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: HandlerSetting(console: console))),
    ));
    Focus.of(t.element(find.text('After extraction'))).requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await t.pumpAndSettle();
    expect(chosen(t), GameHandler.chdCompress);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await t.pumpAndSettle();
    expect(chosen(t), isNull);
  });

  testWidgets('with CHD on, the CHD type for .iso shows, DVD by default, and a sheet picks CD', (t) async {
    SharedPreferences.setMockInitialValues({});
    const console = Console(id: 'disc', name: 'Disc', urls: [], gameFilesFormat: ['.iso']);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HandlerSetting(console: console)))),
    ));
    expect(find.text('CHD type for .iso'), findsNothing);

    await t.tap(find.text('Make CHD'));
    await t.pumpAndSettle();
    expect(find.text('DVD (createdvd)'), findsOneWidget);

    await t.tap(find.text('CHD type for .iso'));
    await t.pumpAndSettle();
    await t.tap(find.text('CD (createcd)'));
    await t.pumpAndSettle();
    expect(c.read(settingsProvider.notifier).chdIsoAsCd('disc'), isTrue);
    expect(find.text('CD (createcd)'), findsOneWidget); // the row's value, the sheet is gone
  });

  testWidgets('NSZ with no Switch keys links to Keys; with keys the row goes', (t) async {
    SharedPreferences.setMockInitialValues({
      'app_settings': jsonEncode({
        'libraryEnabled': true,
        'generalSettings': {'downloadDir': '/roms'},
        'consoleSettings': {
          'nx': {'additionalHandler': 'nsz_decompress'},
        },
      }),
    });
    const console = Console(id: 'nx', name: 'Switch', urls: [], gameFilesFormat: ['.nsz'], additionalHandler: GameHandler.nszDecompress);
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await t.runAsync(() => c.read(settingsProvider.notifier).loaded);
    var opened = 0;
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(home: Scaffold(body: HandlerSetting(console: console, onOpenKeys: () => opened++))),
    ));
    await t.tap(find.text('Switch keys missing'));
    expect(opened, 1);

    await t.runAsync(() => c.read(settingsProvider.notifier).setNszKeysPath('/keys/prod.keys'));
    await t.pump();
    expect(find.text('Switch keys missing'), findsNothing);
  });
}
