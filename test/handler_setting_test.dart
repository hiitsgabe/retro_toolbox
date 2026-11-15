import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/widgets/settings/handler_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('a disc console without a catalog handler can turn CHD on and off', (t) async {
    SharedPreferences.setMockInitialValues({});
    const console = Console(id: 'disc', name: 'Disc', urls: [], gameFilesFormat: ['.bin', '.cue', '.iso']);
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: HandlerSetting(console: console))),
    ));

    Switch chd() => t.widget<Switch>(find.descendant(of: find.widgetWithText(SwitchListTile, 'Convert to CHD'), matching: find.byType(Switch)));
    expect(find.text('Convert to CIA'), findsNothing);
    expect(chd().value, isFalse);

    await t.tap(find.text('Convert to CHD'));
    await t.pumpAndSettle();
    expect(chd().value, isTrue);

    await t.tap(find.text('Convert to CHD'));
    await t.pumpAndSettle();
    expect(chd().value, isFalse);
  });

  testWidgets('with CHD on, Advanced picks the CHD type for .iso, DVD by default', (t) async {
    SharedPreferences.setMockInitialValues({});
    const console = Console(id: 'disc', name: 'Disc', urls: [], gameFilesFormat: ['.iso']);
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: HandlerSetting(console: console)))),
    ));
    expect(find.text('Advanced'), findsNothing);

    await t.tap(find.text('Convert to CHD'));
    await t.pumpAndSettle();
    await t.tap(find.text('Advanced'));
    await t.pumpAndSettle();
    Set<bool> selected() => t.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>)).selected;
    expect(selected(), {false});

    await t.tap(find.text('CD (createcd)'));
    await t.pumpAndSettle();
    expect(selected(), {true});
  });
}
