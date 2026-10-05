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
    Directory(p.join(tmp.path, 'gamma', 'sub')).createSync(recursive: true);
    File(p.join(tmp.path, 'file.txt')).writeAsStringSync('x');
  });
  tearDown(() {
    // Make anything a test locked deletable again.
    Process.runSync('chmod', ['-R', 'u+rwx', tmp.path]);
    tmp.deleteSync(recursive: true);
  });

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

  testWidgets('Enter enters the focused folder, "Use this folder" (one Up away) returns it', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.text('inner'), findsOneWidget);
    expect(focusedLabel(), 'inner');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // ".."
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp); // "Use this folder"
    expect(focusedLabel(), 'Use this folder');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, p.join(tmp.path, 'alpha'));
  });

  testWidgets('in a long list, "Use this folder" is two Ups (past "..") from the first entry', (t) async {
    for (var i = 0; i < 60; i++) {
      Directory(p.join(tmp.path, 'a${i.toString().padLeft(2, '0')}')).createSync();
    }
    await open(t);
    expect(focusedLabel(), 'a00');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(focusedLabel(), '..');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(focusedLabel(), 'Use this folder');
    expect(find.text(tmp.path), findsWidgets);
  });

  testWidgets('an empty folder focuses "Use this folder"', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.text('No subfolders'), findsOneWidget);
    expect(focusedLabel(), 'Use this folder');
  });

  testWidgets('going up focuses the folder you came from', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(find.text('..'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(focusedLabel(), 'beta');
  });

  testWidgets('going up from a folder with entries focuses that folder, not the first', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // beta
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // gamma
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(focusedLabel(), 'sub');
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(focusedLabel(), '..');
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(focusedLabel(), 'gamma');
  });

  testWidgets('going up focuses a folder that starts off-screen in a long list', (t) async {
    for (var i = 0; i < 60; i++) {
      Directory(p.join(tmp.path, 'z${i.toString().padLeft(2, '0')}')).createSync();
    }
    await open(t);
    await t.scrollUntilVisible(find.text('z59'), 200, scrollable: find.byType(Scrollable).last);
    await t.tap(find.text('z59'));
    await settle(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown); // empty folder: "Use this folder" -> ".."
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(t);
    expect(focusedLabel(), 'z59');
  });

  testWidgets('a folder that cannot be opened focuses Go up', (t) async {
    Directory(p.join(tmp.path, 'locked')).createSync();
    Process.runSync('chmod', ['000', p.join(tmp.path, 'locked')]);
    await open(t);
    await t.scrollUntilVisible(find.text('locked'), 50, scrollable: find.byType(Scrollable).last);
    await t.tap(find.text('locked'));
    await settle(t);
    expect(find.textContaining("Can't open"), findsOneWidget);
    final ctx = FocusManager.instance.primaryFocus?.context;
    expect(ctx?.findAncestorWidgetOfExactType<OutlinedButton>(), isNotNull);
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

  testWidgets('Start in directory mode returns the current folder', (t) async {
    await open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, tmp.path);
  });

  testWidgets('Start does nothing special in file mode', (t) async {
    await open(t, selectDirectory: false);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await t.pump();
    expect(closed, isFalse);
  });

  testWidgets('Start does not return a folder that failed to open', (t) async {
    Directory(p.join(tmp.path, 'locked')).createSync();
    Process.runSync('chmod', ['000', p.join(tmp.path, 'locked')]);
    await open(t);
    await t.scrollUntilVisible(find.text('locked'), 50, scrollable: find.byType(Scrollable).last);
    await t.tap(find.text('locked'));
    await settle(t);
    expect(find.textContaining("Can't open"), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.f5);
    await settle(t);
    expect(closed, isFalse);
  });
}
