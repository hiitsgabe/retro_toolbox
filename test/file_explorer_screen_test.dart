import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/file_explorer_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
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

  // The actions sheet (Y, or More in the selection bar) is the kit's row menu.
  List<String> sheetLabels(WidgetTester tester) => [for (final i in tester.widget<RowMenuSheet>(find.byType(RowMenuSheet)).items) i.label];
  Finder inSheet(String label) => find.descendant(of: find.byType(RowMenuSheet), matching: find.text(label));
  Finder inBar(String label) => find.descendant(of: find.byKey(const ValueKey('browser-selection')), matching: find.text(label));
  Finder inTrail(String label) => find.descendant(of: find.byType(BrowserBar), matching: find.text(label));

  Future<void> more(WidgetTester tester) async {
    await tester.tap(inBar('More'));
    await tester.pumpAndSettle();
  }

  Future<void> closeSheet(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  testWidgets('selection actions follow the selection: Copy, Move, Delete by name, the rest under More', (tester) async {
    await open(tester);
    expect(find.text('Saves'), findsOneWidget);

    await tester.tap(find.text('game.zip'));
    await tester.pump();
    expect(inBar('Copy'), findsOneWidget);
    expect(inBar('Move'), findsOneWidget);
    expect(inBar('Delete'), findsOneWidget);
    await more(tester);
    expect(sheetLabels(tester), ['Copy', 'Move', 'Rename', 'Zip', 'Extract here', 'Delete', 'Clear selection', 'New folder']);
    await closeSheet(tester);

    await tester.tap(find.text('notes.txt'));
    await tester.pump();
    await more(tester);
    expect(inSheet('Rename'), findsNothing); // two selected
    expect(inSheet('Extract here'), findsNothing);
    expect(inSheet('Zip'), findsOneWidget);
  });

  testWidgets('copy then paste inside a folder queues a copy into it', (tester) async {
    final container = await open(tester);

    await tester.tap(find.text('notes.txt'));
    await tester.pump();
    await tester.tap(inBar('Copy'));
    await tester.pump();
    expect(find.text('Copy notes.txt: open the folder and paste'), findsOneWidget);

    await tester.runAsync(() async {
      // Tapping a folder opens it (a file's tap selects), as in the SMB/FTP browsers.
      await tester.tap(find.text('Saves'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(inTrail('Saves'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('kit-primary')));
    await tester.pump();

    final task = container.read(taskQueueProvider).tasks.single;
    expect(task.type, TaskType.fileCopy);
    expect(task.params['destDir'], p.join(root.path, 'Saves'));
    expect(task.params['sources'], [p.join(root.path, 'notes.txt')]);
    expect(find.byKey(const ValueKey('kit-primary')), findsNothing);
    container.dispose(); // stops the queue's timer, started in fake time by the queued copy
  });

  testWidgets('the grid/list choice switches the view and is remembered', (tester) async {
    await open(tester);
    expect(find.byType(ListView), findsOneWidget); // list by default

    await tester.tap(find.byTooltip('Folder options'));
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Show as grid'));
    await tester.pumpAndSettle();
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
    expect(sheetLabels(tester), ['Copy', 'Move', 'Rename', 'Zip', 'Extract here', 'Delete', 'Clear selection', 'New folder']);

    await tester.tap(inSheet('Delete'));
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
    expect(inSheet('Rename'), findsOneWidget);
    expect(inSheet('Extract here'), findsNothing);
  });

  testWidgets('with a clipboard, Y offers Paste here and Cancel paste', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown); // notes.txt
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Copy'));
    await tester.pumpAndSettle();
    expect(find.textContaining('open the folder and paste'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.f3); // nothing selected: acts on the focused entry
    await tester.pumpAndSettle();
    expect(inSheet('Paste here'), findsOneWidget);
    expect(inSheet('Cancel paste'), findsOneWidget);
    await tester.ensureVisible(inSheet('Cancel paste'));
    await tester.pump();
    await tester.tap(inSheet('Cancel paste'));
    await tester.pumpAndSettle();
    expect(find.textContaining('open the folder and paste'), findsNothing);
    expect(container.read(taskQueueProvider).tasks, isEmpty);
  });

  testWidgets('Start pastes the clipboard into the current folder', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Copy'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.f5);
    final task = container.read(taskQueueProvider).tasks.single;
    expect(task.type, TaskType.fileCopy);
    expect(task.params['destDir'], root.path);
    expect(task.params['sources'], [p.join(root.path, 'notes.txt')]);
    expect(find.textContaining('open the folder and paste'), findsNothing);
    container.dispose(); // stops the queue's timer, started in fake time by the queued copy
  });

  // The kit's rule: Start runs the screen's primary or nothing; it never
  // presses whatever has focus (here that would mark game.zip).
  testWidgets('Start without a clipboard does nothing', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown); // game.zip
    await press(tester, LogicalKeyboardKey.f5);
    expect(find.byKey(const ValueKey('browser-selection')), findsNothing);
    expect(container.read(taskQueueProvider).tasks, isEmpty);
  });

  testWidgets('Start pastes into an empty folder just opened with A', (tester) async {
    final container = await open(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown); // notes.txt
    await press(tester, LogicalKeyboardKey.f3);
    await tester.pumpAndSettle();
    await tester.tap(inSheet('Copy'));
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp); // Saves (empty)
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('This folder is empty'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.f5);
    expect(container.read(taskQueueProvider).tasks.single.params['destDir'], p.join(root.path, 'Saves'));
    container.dispose(); // stops the queue's timer, started in fake time by the queued copy
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
    expect(find.byType(RowMenuSheet), findsNothing); // nothing to offer at the roots
    expect(find.text('New folder'), findsNothing);
    expect(find.text('Paste here'), findsNothing);
  });

  /// Marks [file] (unless it is) and picks [action] under More.
  Future<void> openDialog(WidgetTester tester, String file, String action) async {
    if (!tester.widget<ListTile>(find.widgetWithText(ListTile, file)).selected) {
      await tester.tap(find.text(file));
      await tester.pump();
    }
    await more(tester);
    await tester.tap(inSheet(action));
    await tester.pumpAndSettle();
  }

  /// Lets the queued job really run until it completes or fails.
  Future<void> settleTask(WidgetTester tester, ProviderContainer container) async {
    // Real IO between fake-time pumps, which flush the job's own awaits.
    for (var i = 0; i < 100 && container.read(taskQueueProvider).tasks.any((t) => t.status == TaskQueueStatus.waiting || t.status == TaskQueueStatus.running); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300))); // the folder refresh after it
    await tester.pump();
  }

  bool focusedOn(String label) =>
      find.descendant(of: find.byWidget(FocusManager.instance.primaryFocus!.context!.widget), matching: find.text(label)).evaluate().isNotEmpty;

  testWidgets('Zip asks first: Cancel and Back queue nothing, Compress queues the zip and shows its bar', (tester) async {
    final container = await open(tester);

    await openDialog(tester, 'notes.txt', 'Zip');
    expect(find.text('Compress?'), findsOneWidget);
    expect(find.textContaining(p.join(root.path, 'notes.zip')), findsOneWidget);
    expect(focusedOn('Compress'), isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(taskQueueProvider).tasks, isEmpty);

    await openDialog(tester, 'notes.txt', 'Zip');
    await press(tester, LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Compress?'), findsNothing);
    expect(container.read(taskQueueProvider).tasks, isEmpty);

    await openDialog(tester, 'notes.txt', 'Zip');
    await press(tester, LogicalKeyboardKey.enter); // A on the focused Compress
    await tester.pump(const Duration(milliseconds: 500)); // dialog closed; the bar's animation never settles
    final task = container.read(taskQueueProvider).tasks.single;
    expect(task.type, TaskType.fileZip);
    expect(task.params['outZip'], p.join(root.path, 'notes.zip'));
    expect(task.params['sources'], [p.join(root.path, 'notes.txt')]);
    expect(find.text('Zipping notes.zip'), findsOneWidget);

    await settleTask(tester, container);
    expect(container.read(taskQueueProvider).tasks.single.status, TaskQueueStatus.completed);
    expect(find.text('Zipping notes.zip'), findsNothing);
    expect(File(p.join(root.path, 'notes.zip')).existsSync(), isTrue);
    container.dispose(); // stops the queue's timer, started in fake time by the queued zip
  });

  testWidgets('Extract here asks first: Cancel queues nothing, Extract queues the extraction', (tester) async {
    final container = await open(tester);

    await openDialog(tester, 'game.zip', 'Extract here');
    expect(find.text('Extract?'), findsOneWidget);
    expect(find.textContaining(p.join(root.path, 'game')), findsOneWidget);
    expect(focusedOn('Extract'), isTrue);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(taskQueueProvider).tasks, isEmpty);

    await openDialog(tester, 'game.zip', 'Extract here');
    await tester.tap(find.widgetWithText(FilledButton, 'Extract'));
    await tester.pump(const Duration(milliseconds: 500));
    final task = container.read(taskQueueProvider).tasks.single;
    expect(task.type, TaskType.archiveExtraction);
    expect(task.params['archivePath'], p.join(root.path, 'game.zip'));
    expect(task.params['outputDir'], p.join(root.path, 'game'));
    expect(task.params['deleteOriginals'], isFalse);
    expect(find.text('Extracting game.zip'), findsOneWidget);

    await settleTask(tester, container);
    expect(find.text('Extracting game.zip'), findsNothing);
    expect(File(p.join(root.path, 'game.zip')).existsSync(), isTrue);
    container.dispose(); // stops the queue's timer, started in fake time by the queued extraction
  });

  testWidgets('Extract here with Delete original when done removes the archive once it is out', (tester) async {
    File(p.join(root.path, 'game.zip')).writeAsBytesSync(ZipEncoder().encode(Archive()..addFile(ArchiveFile.string('game.iso', 'iso'))));
    final container = await open(tester);

    await openDialog(tester, 'game.zip', 'Extract here');
    final box = find.widgetWithText(CheckboxListTile, 'Delete original when done');
    expect(tester.widget<CheckboxListTile>(box).value, isFalse); // off by default
    expect(focusedOn('Extract'), isTrue);
    await tester.tap(box);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(box).value, isTrue);
    await tester.tap(find.widgetWithText(FilledButton, 'Extract'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(taskQueueProvider).tasks.single.params['deleteOriginals'], isTrue);

    await settleTask(tester, container);
    expect(container.read(taskQueueProvider).tasks.single.status, TaskQueueStatus.completed);
    expect(File(p.join(root.path, 'game', 'game.iso')).readAsStringSync(), 'iso');
    expect(File(p.join(root.path, 'game.zip')).existsSync(), isFalse);
    container.dispose(); // stops the queue's timer, started in fake time by the queued extraction
  });

  testWidgets('the trail names the storage root and goes back up on a tap', (tester) async {
    await open(tester);
    // The test folder is the Downloads root (path_provider answers it).
    expect(inTrail('Downloads'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Saves'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(inTrail('Saves'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    await tester.runAsync(() async {
      await tester.tap(inTrail('Downloads'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(find.text('notes.txt'), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape); // Back from a root: the storage list
    expect(find.text('notes.txt'), findsNothing);
    expect(find.widgetWithText(ListTile, 'Downloads'), findsOneWidget);
    expect(inTrail('Storage'), findsOneWidget);
  });

  testWidgets('Storage lists the roots, the current one checked', (tester) async {
    await open(tester);
    await tester.tap(find.text('Storage'));
    await tester.pumpAndSettle();
    final sheet = tester.widget<RowMenuSheet>(find.byType(RowMenuSheet));
    final downloads = sheet.items.singleWhere((i) => i.label == 'Downloads');
    expect(downloads.subtitle, root.path);
    expect(downloads.icon, Icons.check);
  });

  testWidgets('no action bar on touch with nothing to paste; a paste waiting is the bar, Cancel drops it', (tester) async {
    await open(tester);
    expect(find.byType(ActionBar), findsNothing);
    await tester.tap(find.text('notes.txt'));
    await tester.pump();
    await tester.tap(inBar('Move'));
    await tester.pump();
    expect(find.descendant(of: find.byType(ActionBar), matching: find.text('Move notes.txt: open the folder and paste')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kit-secondary')));
    await tester.pump();
    expect(find.byType(ActionBar), findsNothing);
  });

  testWidgets('a long press marks a folder', (tester) async {
    await open(tester);
    await tester.longPress(find.text('Saves'));
    await tester.pump();
    expect(inBar('1 selected'), findsOneWidget);
    expect(find.text('notes.txt'), findsOneWidget, reason: 'still in the same folder');
  });

  group('a refused change', () {
    late Directory locked;
    setUp(() {
      locked = Directory(p.join(root.path, 'Saves'));
      File(p.join(locked.path, 'save.dat')).writeAsStringSync('dat');
      Process.runSync('chmod', ['555', locked.path]);
    });
    tearDown(() => Process.runSync('chmod', ['755', locked.path]));

    /// The dialog closes, then the change and the reload do real IO.
    Future<void> realIo(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      }
      await tester.pump();
    }

    Future<void> openLocked(WidgetTester tester) async {
      await open(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text('Saves'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.tap(find.text('save.dat'));
      await tester.pump();
    }

    testWidgets('a failed delete says what and why in one line, the raw error behind Details', (tester) async {
      await openLocked(tester);
      await tester.tap(inBar('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await realIo(tester);
      expect(File(p.join(locked.path, 'save.dat')).existsSync(), isTrue);
      expect(find.text("Can't delete save.dat: permission denied"), findsOneWidget);
      expect(find.textContaining('errno'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('errno = 13'), findsOneWidget);
    });

    testWidgets('a failed rename stays on screen after the folder reloads', (tester) async {
      await openLocked(tester);
      await more(tester);
      await tester.tap(inSheet('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'other.dat');
      await tester.tap(find.widgetWithText(FilledButton, 'OK'));
      await realIo(tester);
      expect(find.text("Can't rename save.dat: permission denied"), findsOneWidget);
    });
  });
}
