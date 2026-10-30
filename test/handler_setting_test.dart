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
}
