import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/file_explorer_screen.dart';
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

  Future<ProviderContainer> open(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: FileExplorerScreen(initialPath: root.path)),
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
      // Double tap opens a folder (single tap selects), as in the SMB/FTP browsers.
      tester
          .widget<GestureDetector>(find
              .ancestor(of: find.text('Saves'), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onDoubleTap != null))
              .first)
          .onDoubleTap!();
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
}
