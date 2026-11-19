import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/screens/collection_clean_screen.dart';
import 'package:retro_toolbox/services/collection_clean_service.dart';

/// The native picker, answering every folder pick with [dir].
class _Picker extends FilePicker with MockPlatformInterfaceMixin {
  _Picker(this.dir);
  final String dir;
  @override
  Future<String?> getDirectoryPath({String? dialogTitle, bool lockParentWindow = false, String? initialDirectory}) async => dir;
}

void main() {
  testWidgets('renders the empty state until a folder is chosen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CollectionCleanScreen()));
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.text('Pick a folder to enable cleanup.'), findsOneWidget);
    // Sections only appear after a folder is picked.
    expect(find.text('Dedupe Games'), findsNothing);
  });

  testWidgets('Clean File Names says how many renames were skipped and why', (t) async {
    final dir = Directory.systemTemp.createTempSync('cc_screen');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in ['Mario (USA).nes', 'Zelda.sfc', 'Zelda (USA).sfc', 'Metroid (USA).sfc', 'Metroid (Europe).sfc']) {
      File(p.join(dir.path, name)).writeAsBytesSync([0]);
    }
    FilePicker.platform = _Picker(dir.path);
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    // Scans run in an isolate (compute), so they need real time to finish.
    Future<void> waitFor(Finder f) async {
      for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await t.pump();
      }
    }

    await t.pumpWidget(const MaterialApp(home: CollectionCleanScreen()));
    await t.tap(find.text('Choose folder'));
    await t.pumpAndSettle();
    await t.tap(find.text('Scan').at(1)); // Clean File Names is the second section
    await waitFor(find.text('Rename selected (4)'));
    await t.tap(find.text('Rename selected (4)'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Rename selected'));
    await t.pump();

    expect(find.text('Clean File Names: Renamed 2, skipped 2 (name already exists).'), findsOneWidget);

    // Let the rescan after the apply finish before the test ends.
    await waitFor(find.text('Rename selected (2)'));
    expect(find.text('Rename selected (2)'), findsOneWidget);
  });

  testWidgets('each section explains itself from a small (i) in its header', (t) async {
    final dir = Directory.systemTemp.createTempSync('cc_info');
    addTearDown(() => dir.deleteSync(recursive: true));
    FilePicker.platform = _Picker(dir.path);
    t.view.physicalSize = const Size(1000, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    await t.pumpWidget(const MaterialApp(home: CollectionCleanScreen()));
    await t.tap(find.text('Choose folder'));
    await t.pumpAndSettle();
    const ghosts = 'Finds OS junk';
    expect(find.textContaining(ghosts), findsNothing);
    final card = find.ancestor(of: find.text('Ghost File Cleaner'), matching: find.byType(Card));
    await t.tap(find.descendant(of: card, matching: find.byIcon(Icons.info_outline)));
    await t.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.textContaining(ghosts)), findsOneWidget);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Ghost File Cleaner')), findsOneWidget);
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
