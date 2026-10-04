import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';

late Directory tmp;
String? result;
bool closed = false;

Future<void> settle(WidgetTester t) async {
  // Directory.list is real async IO whose continuations run in the fake zone:
  // alternate real waits with pumps so each step can advance.
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }
}

Future<void> open(WidgetTester t, {bool selectDirectory = true}) async {
  final key = GlobalKey<NavigatorState>();
  result = null;
  closed = false;
  await t.pumpWidget(MaterialApp(
    navigatorKey: key,
    builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
    home: Builder(
      builder: (ctx) => TextButton(
        onPressed: () async {
          result = await PathBrowser.show(ctx, title: 'Pick', initialDir: tmp.path, selectDirectory: selectDirectory);
          closed = true;
        },
        child: const Text('open'),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await settle(t);
}

String? focusedLabel() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return null;
  final tile = ctx.findAncestorWidgetOfExactType<ListTile>() ?? (ctx.widget is ListTile ? ctx.widget as ListTile : null);
  final title = tile?.title;
  return title is Text ? title.data : null;
}

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pb_test');
    Directory(p.join(tmp.path, 'alpha', 'inner')).createSync(recursive: true);
    Directory(p.join(tmp.path, 'beta')).createSync();
    File(p.join(tmp.path, 'file.txt')).writeAsStringSync('x');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('directory mode lists only folders and autofocuses the first', (t) async {
    await open(t);
    expect(find.text('alpha'), findsOneWidget);
    expect(find.text('beta'), findsOneWidget);
    expect(find.text('file.txt'), findsNothing);
    expect(focusedLabel(), 'alpha');
  });

  testWidgets('file mode still lists files', (t) async {
    await open(t, selectDirectory: false);
    expect(find.text('file.txt'), findsOneWidget);
  });

  testWidgets('Enter enters the focused folder, "Use this folder" returns it', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.text('inner'), findsOneWidget);
    expect(focusedLabel(), 'inner');
    await t.tap(find.text('Use this folder'));
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, p.join(tmp.path, 'alpha'));
  });

  testWidgets('going up focuses the folder you came from', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.text('..'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(focusedLabel(), 'beta');
  });

  testWidgets('Cancel returns null', (t) async {
    await open(t);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });

  test('handheld roots keep only the ones that exist', () {
    final roots = handheldRoots(exists: (d) => d == '/userdata' || d == '/roms');
    expect(roots.keys, ['/userdata', '/roms']);
    expect(handheldRoots(exists: (_) => false), isEmpty);
  });
}
