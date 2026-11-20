import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/models/app_style.dart';
import 'package:retro_toolbox/screens/m3u_screen.dart';

import 'kit/kit_support.dart';

/// The native picker, answering every folder pick with [dir].
class _Picker extends FilePicker with MockPlatformInterfaceMixin {
  _Picker(this.dir);
  final String dir;
  @override
  Future<String?> getDirectoryPath({String? dialogTitle, bool lockParentWindow = false, String? initialDirectory}) async => dir;
}

void main() {
  testWidgets('renders the empty state until a folder is chosen', (tester) async {
    await pumpKit(tester, const M3uScreen(), style: CardStyle.switchStyle);
    expect(find.text('M3U Playlists'), findsOneWidget);
    expect(find.text('Choose the folder with the discs'), findsOneWidget);
    expect(find.text('Pick the folder with the discs'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('kit-primary'))).onPressed, isNull);
  });

  testWidgets('picking a folder scans it; Start writes the marked playlists, which then read as Exists', (t) async {
    final dir = Directory.systemTemp.createTempSync('m3u_screen');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final f in ['FF7 (Disc 1).chd', 'FF7 (Disc 2).chd', 'FF7 (Disc 3).chd', 'MGS (Disc 1).cue', 'MGS (Disc 2).cue']) {
      File(p.join(dir.path, f)).writeAsStringSync('x');
    }
    // MGS already has its playlist, as this tool would write it.
    File(p.join(dir.path, 'MGS.m3u')).writeAsStringSync('MGS (Disc 1).cue\nMGS (Disc 2).cue\n');
    FilePicker.platform = _Picker(dir.path);

    await pumpKit(t, const M3uScreen(), style: CardStyle.switchStyle);
    await t.tap(find.text('Choose the folder with the discs'));
    await t.pumpAndSettle();
    expect(find.text('FF7.m3u'), findsOneWidget);
    expect(find.text('MGS.m3u'), findsOneWidget);
    expect(find.text('Exists'), findsOneWidget);
    expect(find.text('Create 1 playlist'), findsOneWidget, reason: 'the set already written is not marked');

    await t.sendKeyEvent(LogicalKeyboardKey.gameButtonStart);
    await t.pumpAndSettle();
    expect(File(p.join(dir.path, 'FF7.m3u')).readAsLinesSync(), ['FF7 (Disc 1).chd', 'FF7 (Disc 2).chd', 'FF7 (Disc 3).chd']);
    expect(find.byKey(const ValueKey('kit-status-done')), findsOneWidget);
    expect(find.textContaining('Created 1 playlist'), findsOneWidget);
    expect(find.text('Exists'), findsNWidgets(2));
    expect(find.text('Create playlists'), findsOneWidget);
  });

  testWidgets('a playlist with other discs is offered as a replacement', (t) async {
    final dir = Directory.systemTemp.createTempSync('m3u_replace');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final f in ['MGS (Disc 1).cue', 'MGS (Disc 2).cue']) {
      File(p.join(dir.path, f)).writeAsStringSync('x');
    }
    File(p.join(dir.path, 'MGS.m3u')).writeAsStringSync('MGS (Disc 1).cue\n');
    FilePicker.platform = _Picker(dir.path);

    await pumpKit(t, const M3uScreen(), style: CardStyle.switchStyle);
    await t.tap(find.text('Choose the folder with the discs'));
    await t.pumpAndSettle();
    expect(find.text('Replace'), findsOneWidget);
    expect(find.text('Create 1 playlist'), findsOneWidget);
  });

  testWidgets('a folder with no disc sets says so, and that subfolders are not scanned', (t) async {
    final dir = Directory.systemTemp.createTempSync('m3u_empty');
    addTearDown(() => dir.deleteSync(recursive: true));
    FilePicker.platform = _Picker(dir.path);
    await pumpKit(t, const M3uScreen(), style: CardStyle.switchStyle);
    await t.tap(find.text('Choose the folder with the discs'));
    await t.pumpAndSettle();
    expect(find.text('No multi-disc games in this folder. Subfolders are not scanned.'), findsOneWidget);
  });
}
