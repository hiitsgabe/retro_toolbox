import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';

import 'kit/kit_support.dart';

class _Picker extends FilePicker with MockPlatformInterfaceMixin {
  _Picker(this.dir);
  final String dir;
  @override
  Future<String?> getDirectoryPath({String? dialogTitle, bool lockParentWindow = false, String? initialDirectory}) async => dir;
}

void main() {
  testWidgets('applying asks first (with the count); Cancel keeps everything', (t) async {
    final dir = Directory.systemTemp.createTempSync('cc_confirm');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Clean names, so the only findings are the two duplicates of Sonic.
    File(p.join(dir.path, 'Sonic.md')).writeAsBytesSync([0, 0, 0]);
    for (final n in ['Sonic (1).md', 'Sonic (2).md']) {
      File(p.join(dir.path, n)).writeAsBytesSync([0]);
    }
    FilePicker.platform = _Picker(dir.path);
    await pumpKit(t, const CollectionCleanScreen(), style: CardStyle.switchStyle);
    await t.tap(find.text('Choose folder'));
    for (var i = 0; i < 150 && find.text('DEDUPE GAMES').evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    // Unmark the renames: only the duplicates go.
    final names = find.ancestor(of: find.text('CLEAN FILE NAMES'), matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: names, matching: find.text('None')));
    await t.pump();
    bool there(String n) => File(p.join(dir.path, n)).existsSync();

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(find.text('Delete 2 duplicates? This cannot be undone.'), findsOneWidget);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect([there('Sonic (1).md'), there('Sonic (2).md')], [true, true]);

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Apply'));
    await t.pump();
    expect([there('Sonic.md'), there('Sonic (1).md'), there('Sonic (2).md')], [true, false, false]);
    expect(find.text('Deleted 2 duplicates.'), findsOneWidget);
    for (var i = 0; i < 50; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
  });
}
