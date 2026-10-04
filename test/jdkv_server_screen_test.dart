import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/screens/jdkv_server_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SavePicker extends FilePicker with MockPlatformInterfaceMixin {
  _SavePicker(this.path);
  final String path;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async =>
      path;
}

class _RunningNotifier extends JdkvServerNotifier {
  _RunningNotifier() {
    state = const JdkvServerState(running: true, addresses: ['192.168.1.5']);
  }
}

Future<void> saveTo(WidgetTester t, String path) async {
  SharedPreferences.setMockInitialValues({});
  FilePicker.platform = _SavePicker(path);
  await t.pumpWidget(ProviderScope(
    overrides: [jdkvServerProvider.overrideWith((ref) => _RunningNotifier())],
    child: const MaterialApp(home: JdkvServerScreen()),
  ));
  await t.pump();
  await t.tap(find.byTooltip('Save webdav.json'));
  await t.pump();
  await t.pump();
}

void main() {
  testWidgets('saving webdav.json writes the file and says Saved', (t) async {
    final dir = Directory.systemTemp.createTempSync('jdkv');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = '${dir.path}/webdav.json';
    await t.runAsync(() => saveTo(t, file));
    expect(find.text('Saved webdav.json'), findsOneWidget);
    expect(File(file).readAsStringSync(), contains('192.168.1.5'));
  });

  testWidgets('a failed write shows the error, not Saved', (t) async {
    final dir = Directory.systemTemp.createTempSync('jdkv');
    addTearDown(() => dir.deleteSync(recursive: true));
    await t.runAsync(() => saveTo(t, '${dir.path}/missing/webdav.json'));
    expect(find.text('Saved webdav.json'), findsNothing);
    expect(find.textContaining('Could not save webdav.json'), findsOneWidget);
  });
}
