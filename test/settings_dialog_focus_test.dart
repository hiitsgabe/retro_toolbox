import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/settings/tools_setting.dart';

void main() {
  testWidgets('clear-cache dialog opens with Cancel focused', (t) async {
    await t.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: ToolsSetting(console: null))),
    ));
    await t.tap(find.byIcon(Icons.clear));
    await t.pumpAndSettle();
    var inCancel = false;
    FocusManager.instance.primaryFocus!.context!.visitAncestorElements((e) {
      inCancel = e.widget is TextButton && find.descendant(of: find.byWidget(e.widget), matching: find.text('Cancel')).evaluate().isNotEmpty;
      return !inCancel;
    });
    expect(inCancel, isTrue);
  });
}
