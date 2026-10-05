import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/file_explorer_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('explorer');
    File(p.join(root.path, 'game.zip')).writeAsStringSync('zip');
    File(p.join(root.path, 'notes.txt')).writeAsStringSync('txt');
    Directory(p.join(root.path, 'Saves')).createSync();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  final navKey = GlobalKey<NavigatorState>();

  Future<ProviderContainer> open(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          builder: (c, child) => DpadScope(navigatorKey: navKey, child: child!),
          home: FileExplorerScreen(initialPath: root.path),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    return container;
  }

  IconButton action(WidgetTester tester, String tooltip) =>
      tester.widget<IconButton>(find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)).first);

  testWidgets('selection actions follow the selection', (tester) async {
    await open(tester);
    expect(find.text('Saves'), findsOneWidget);

    await tester.tap(find.text('game.zip'));
    await tester.pump();
    expect(action(tester, 'Rename').onPressed, isNotNull);
    expect(action(tester, 'Extract here').onPressed, isNotNull);

    await tester.tap(find.text('notes.txt'));
    await tester.pump();
    expect(action(tester, 'Rename').onPressed, isNull); // two selected
    expect(action(tester, 'Extract here').onPressed, isNull);
  });

  testWidgets('copy then paste inside a folder queues a copy into it', (tester) async {
    final container = await open(tester);

    await tester.tap(find.text('notes.txt'));
    await tester.pump();
    await tester.tap(find.byTooltip('Copy'));
    await tester.pump();
    expect(find.textContaining('open the destination and paste'), findsOneWidget);

    await tester.runAsync(() async {
      // Tapping a folder opens it (a file's tap selects), as in the SMB/FTP browsers.
      await tester.tap(find.text('Saves'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text(p.join(root.path, 'Saves')), findsOneWidget);

    await tester.tap(find.text('Paste here'));
    await tester.pump();

    final task = container.read(taskQueueProvider).tasks.single;
    expect(task.type, TaskType.fileCopy);
    expect(task.params['destDir'], p.join(root.path, 'Saves'));
    expect(task.params['sources'], [p.join(root.path, 'notes.txt')]);
    expect(find.text('Paste here'), findsNothing);
  });

  testWidgets('the grid/list choice switches the view and is remembered', (tester) async {
    await open(tester);
    expect(find.byType(ListView), findsOneWidget); // short test screen: list by default

    await tester.tap(find.byTooltip('Show as grid'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('file_browser_layout'), 'grid');
  });

  Future<void> press(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  // Sorted: Saves, game.zip, notes.txt. Focus starts on Saves.
  testWidgets('Y marks the focused entry and lists the explorer actions; Delete asks with Cancel focused', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown); // game.zip
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    final labels = [for (final t in tester.widgetList<ListTile>(find.descendant(of: find.byType(BottomSheet), matching: find.byType(ListTile)))) (t.title as Text).data];
    expect(labels, ['Copy', 'Move', 'Rename', 'Zip', 'Extract here', 'Delete', 'Clear selection', 'New folder']);

    await tester.tap(find.widgetWithText(ListTile, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete?'), findsOneWidget);
    final focus = FocusManager.instance.primaryFocus!;
    expect(find.descendant(of: find.byWidget(focus.context!.widget), matching: find.text('Cancel')), findsOneWidget);
    expect(File(p.join(root.path, 'game.zip')).existsSync(), isTrue);
  });

  testWidgets('X marks, so Y lists Rename only for one item and not Extract for a plain file', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown); // notes.txt
    await press(tester, LogicalKeyboardKey.f2);
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Rename'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Extract here'), findsNothing);
  });

  testWidgets('with a clipboard, Y offers Paste here and Cancel paste', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown); // notes.txt
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('open the destination and paste'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.f3); // nothing selected: acts on the focused entry
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Paste here'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Cancel paste'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ListTile, 'Cancel paste'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ListTile, 'Cancel paste'));
    await tester.pumpAndSettle();
    expect(find.textContaining('open the destination and paste'), findsNothing);
    expect(container.read(taskQueueProvider).tasks, isEmpty);
  });

  testWidgets('Start pastes the clipboard into the current folder', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Copy'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.f5);
    final task = container.read(taskQueueProvider).tasks.single;
    expect(task.type, TaskType.fileCopy);
    expect(task.params['destDir'], root.path);
    expect(task.params['sources'], [p.join(root.path, 'notes.txt')]);
    expect(find.textContaining('open the destination and paste'), findsNothing);
  });

  testWidgets('Start without a clipboard activates the focused row as before', (tester) async {
    await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown); // game.zip: activating selects it
    await press(tester, LogicalKeyboardKey.f5);
    expect(action(tester, 'Extract here').onPressed, isNotNull);
  });

  testWidgets('Start pastes into an empty folder just opened with A', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown); // notes.txt
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Copy'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp); // Saves (empty)
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('Empty'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.f5);
    expect(container.read(taskQueueProvider).tasks.single.params['destDir'], p.join(root.path, 'Saves'));
  });

  testWidgets('at the storage list Y offers no New folder or Paste here', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navKey,
          builder: (c, child) => DpadScope(navigatorKey: navKey, child: child!),
          home: const FileExplorerScreen(),
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing); // nothing to offer at the roots
    expect(find.text('New folder'), findsNothing);
    expect(find.text('Paste here'), findsNothing);
  });
}
