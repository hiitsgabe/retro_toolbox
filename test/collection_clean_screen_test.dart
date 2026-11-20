import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';
import 'package:retro_toolbox/services/collection_clean_service.dart';

import 'kit/kit_support.dart';

/// The native picker, answering every folder pick with [dir].
class _Picker extends FilePicker with MockPlatformInterfaceMixin {
  _Picker(this.dir);
  final String dir;
  @override
  Future<String?> getDirectoryPath({String? dialogTitle, bool lockParentWindow = false, String? initialDirectory}) async => dir;
}

void main() {
  /// Scans run in an isolate (compute), so they need real time to finish.
  Future<void> waitFor(WidgetTester t, Finder f) async {
    for (var i = 0; i < 150 && f.evaluate().isEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(f, findsWidgets);
  }

  Directory folder(List<String> names) {
    final dir = Directory.systemTemp.createTempSync('cc_screen');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in names) {
      File(p.join(dir.path, name)).writeAsBytesSync([0]);
    }
    FilePicker.platform = _Picker(dir.path);
    return dir;
  }

  // Tall, so every finding is built.
  Future<void> open(WidgetTester t) => pumpKit(t, const CollectionCleanScreen(), style: CardStyle.switchStyle, device: (const Size(1000, 1400), 1.0));

  testWidgets('renders the empty state until a folder is chosen', (tester) async {
    await open(tester);
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.text('Pick a folder to enable cleanup.'), findsOneWidget);
    // Findings only appear after a folder is picked.
    expect(find.text('DEDUPE GAMES'), findsNothing);
  });

  testWidgets('picking a folder scans it for every cleanup, grouped and all marked', (t) async {
    folder(['Mario (USA).sfc', 'Mario (Europe).sfc', 'Zelda [!].sfc', '.DS_Store']);
    await open(t);
    await t.tap(find.text('Choose folder'));
    await waitFor(t, find.text('DEDUPE GAMES'));
    expect(find.text('CLEAN FILE NAMES'), findsOneWidget);
    expect(find.text('GHOST FILE CLEANER'), findsOneWidget);
    expect(find.text('.DS_Store'), findsOneWidget);
    expect(find.text('→ Zelda.sfc'), findsOneWidget);
    // One duplicate, one junk file, three renames (both Marios and Zelda).
    expect(find.text('Apply 5 changes'), findsOneWidget);
  });

  testWidgets('Clean File Names says how many renames were skipped and why', (t) async {
    final dir = folder(['Mario (USA).nes', 'Zelda.sfc', 'Zelda (USA).sfc', 'Metroid (USA).sfc', 'Metroid (Europe).sfc']);
    await open(t);
    await t.tap(find.text('Choose folder'));
    await waitFor(t, find.text('CLEAN FILE NAMES'));
    // Only the renames: the duplicates group is unmarked from its header.
    final dedupe = find.ancestor(of: find.text('DEDUPE GAMES'), matching: find.byType(Row)).first;
    await t.tap(find.descendant(of: dedupe, matching: find.text('None')));
    await t.pump();
    expect(find.text('Apply 4 changes'), findsOneWidget);
    await t.tap(find.text('Apply 4 changes'));
    await t.pumpAndSettle();
    expect(find.text('Rename 4 files? This cannot be undone.'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Apply'));
    await t.pump();

    expect(find.text('Renamed 2, skipped 2 (name already exists).'), findsOneWidget);
    expect(find.text(CollectionCleanService.nameExists), findsNWidgets(2));
    expect(File(p.join(dir.path, 'Mario.nes')).existsSync(), isTrue);

    // The rescan after the apply lists what is left: the two skipped renames,
    // and the duplicates they are.
    for (var i = 0; i < 150 && find.text('Mario (USA).nes').evaluate().isNotEmpty; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump();
    }
    expect(find.text('Mario (USA).nes'), findsNothing);
    expect(find.text('Apply 4 changes'), findsOneWidget);
    expect(find.text('Renamed 2, skipped 2 (name already exists).'), findsOneWidget, reason: 'the result stays after the rescan');
  });

  testWidgets('the (i) explains each cleanup', (t) async {
    await open(t);
    const ghosts = 'Ghost File Cleaner finds OS junk';
    expect(find.textContaining(ghosts), findsNothing);
    await t.tap(find.byIcon(Icons.info_outline));
    await t.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.textContaining(ghosts)), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('Dedupe Games finds game files')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.textContaining('Clean File Names removes')), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
  });

  test('renameSummary groups skips by reason', () {
    RenameSkip skip(String reason) => (entry: (path: '/a', from: 'a', to: 'b'), reason: reason);
    expect(CollectionCleanScreen.renameSummary((renamed: 3, skipped: [])), 'Renamed 3.');
    expect(
      CollectionCleanScreen.renameSummary((renamed: 3, skipped: [skip(CollectionCleanService.nameExists), skip(CollectionCleanService.nameExists)])),
      'Renamed 3, skipped 2 (name already exists).',
    );
    expect(
      CollectionCleanScreen.renameSummary((renamed: 0, skipped: [skip(CollectionCleanService.nameExists), skip('rename failed'), skip('rename failed')])),
      'Renamed 0, skipped 3 (1 name already exists, 2 rename failed).',
    );
  });
}
