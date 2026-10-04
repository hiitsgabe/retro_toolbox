import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:retro_toolbox/services/pick.dart';

class _FakePicker extends FilePicker with MockPlatformInterfaceMixin {
  FileType? type;
  List<String>? exts;
  String? title;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated('') bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.type = type;
    exts = allowedExtensions;
    title = dialogTitle;
    return FilePickerResult([PlatformFile(name: 'a.iso', size: 0, path: '/x/a.iso')]);
  }

  @override
  Future<String?> getDirectoryPath({String? dialogTitle, bool lockParentWindow = false, String? initialDirectory}) async {
    title = dialogTitle;
    return '/x/dir';
  }
}

Future<BuildContext> ctxOf(WidgetTester t) async {
  late BuildContext c;
  await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => TextButton(onPressed: () => c = ctx, child: const Text('x')))));
  await t.tap(find.text('x'));
  return c;
}

void main() {
  late _FakePicker fake;
  setUp(() => FilePicker.platform = fake = _FakePicker());

  testWidgets('native: pickFile keeps custom + extensions', (t) async {
    final c = await ctxOf(t);
    expect(await pickFile(c, title: 'T', extensions: ['iso'], useBrowser: false), '/x/a.iso');
    expect(fake.type, FileType.custom);
    expect(fake.exts, ['iso']);
    expect(fake.title, 'T');
  });

  testWidgets('native: no extensions means any file; directory goes through getDirectoryPath', (t) async {
    final c = await ctxOf(t);
    await pickFile(c, title: 'T', useBrowser: false);
    expect(fake.type, FileType.any);
    expect(await pickDirectory(c, title: 'D', useBrowser: false), '/x/dir');
    expect(fake.title, 'D');
  });

  testWidgets('browser: pickDirectory shows the folder browser and returns its folder', (t) async {
    final tmp = Directory.systemTemp.createTempSync('pick_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final c = await ctxOf(t);
    String? out;
    var done = false;
    unawaited(pickDirectory(c, title: 'D', initialDir: tmp.path, useBrowser: true).then((v) {
      out = v;
      done = true;
    }));
    await t.pump();
    await t.pump();
    expect(find.text('Use this folder'), findsOneWidget);
    await t.tap(find.text('Use this folder'));
    await t.pumpAndSettle();
    expect(done, isTrue);
    expect(out, p.normalize(tmp.path));
    expect(fake.title, isNull);
  });
}
