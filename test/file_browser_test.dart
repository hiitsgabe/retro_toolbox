import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/browser_layout_provider.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/file_browser.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const folder = BrowserItem(id: '/Saves', name: 'Saves', isDir: true, size: 0);
  const file = BrowserItem(id: '/notes.txt', name: 'notes.txt', isDir: false, size: 3);

  Future<({List<String> opened, Set<String> selected, List<String> calls})> pump(
    WidgetTester tester, {
    BrowserLayout? layout = BrowserLayout.list,
    bool selectable = true,
    bool busy = false,
    List<BrowserItem> items = const [folder, file],
    Set<String> initiallySelected = const {},
    bool defaultActions = false,
    List<BrowserAction>? selectionActions,
    List<BrowserAction> Function()? extraActions,
    BrowserTransfer? transfer,
    List<Crumb>? crumbs,
    String? error,
    String? errorLine,
    KitAction? emptyAction,
    Size? size,
  }) async {
    if (size != null) {
      tester.view.devicePixelRatio = 2.625;
      tester.view.physicalSize = size * 2.625;
      addTearDown(tester.view.reset);
    }
    final key = GlobalKey<NavigatorState>();
    final opened = <String>[];
    final calls = <String>[];
    final selected = {...initiallySelected};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [if (layout != null) browserLayoutProvider.overrideWith((ref) => BrowserLayoutNotifier()..state = layout)],
        child: MaterialApp(
          navigatorKey: key,
          builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => FileBrowserView(
                locationLabel: '/',
                crumbs: crumbs,
                busy: busy,
                error: error,
                errorLine: errorLine,
                emptyAction: emptyAction,
                items: items,
                selectedIds: selected,
                selectable: selectable,
                transfer: transfer,
                onDownload: defaultActions ? () => calls.add('download') : null,
                onZip: defaultActions ? () => calls.add('zip') : null,
                onDelete: defaultActions ? () => calls.add('delete') : null,
                selectionActions: selectionActions,
                extraActions: extraActions,
                onRefresh: () => calls.add('refresh'),
                onOpen: (e) => opened.add(e.id),
                onToggleSelect: (e) => setState(() => selected.contains(e.id) ? selected.remove(e.id) : selected.add(e.id)),
                onClearSelection: () => setState(selected.clear),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return (opened: opened, selected: selected, calls: calls);
  }

  Future<void> key(WidgetTester tester, LogicalKeyboardKey k) async {
    await tester.sendKeyEvent(k);
    await tester.pump();
  }

  // The actions sheet is the kit's row menu.
  List<String> sheetLabels(WidgetTester tester) => [for (final i in tester.widget<RowMenuSheet>(find.byType(RowMenuSheet)).items) i.label];
  Finder inSheet(String label) => find.descendant(of: find.byType(RowMenuSheet), matching: find.text(label));
  bool focusedOn(String label) =>
      find.descendant(of: find.byWidget(FocusManager.instance.primaryFocus!.context!.widget), matching: find.text(label)).evaluate().isNotEmpty;

  for (final layout in BrowserLayout.values) {
    group('${layout.name} layout', () {
      testWidgets('first item is autofocused; Enter on a folder opens it', (tester) async {
        final r = await pump(tester, layout: layout);
        await key(tester, LogicalKeyboardKey.enter);
        expect(r.opened, ['/Saves']);
        expect(r.selected, isEmpty);
      });

      testWidgets('Enter on a file toggles selection', (tester) async {
        final r = await pump(tester, layout: layout);
        await key(tester, layout == BrowserLayout.list ? LogicalKeyboardKey.arrowDown : LogicalKeyboardKey.arrowRight);
        await key(tester, LogicalKeyboardKey.enter);
        expect(r.selected, {'/notes.txt'});
        expect(r.opened, isEmpty);
      });

      testWidgets('the checkbox is reachable by d-pad and selects a folder', (tester) async {
        final r = await pump(tester, layout: layout, items: const [folder]);
        // List: checkbox sits left of the row. Grid: it sits in a row above the tile.
        await key(tester, layout == BrowserLayout.list ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowUp);
        await key(tester, LogicalKeyboardKey.enter);
        expect(r.selected, {'/Saves'});
        expect(r.opened, isEmpty);
      });

      testWidgets('tapping a folder opens it, tapping a file selects it', (tester) async {
        final r = await pump(tester, layout: layout);
        await tester.tap(find.text('Saves'));
        await tester.pump();
        await tester.tap(find.text('notes.txt'));
        await tester.pump();
        expect(r.opened, ['/Saves']);
        expect(r.selected, {'/notes.txt'});
      });

      testWidgets('while busy, a folder keeps focus and cannot be opened', (tester) async {
        final r = await pump(tester, layout: layout, busy: true);
        final focus = FocusManager.instance.primaryFocus;
        expect(focus, isNotNull);
        // The tile's own focus node holds focus, not a surrounding scope (whose context also contains 'Saves').
        expect(focus, isNot(isA<FocusScopeNode>()));
        expect(find.descendant(of: find.byWidget(focus!.context!.widget), matching: find.text('Saves')), findsOneWidget);
        await tester.tap(find.text('Saves'));
        await key(tester, LogicalKeyboardKey.enter);
        expect(r.opened, isEmpty);
        expect(FocusManager.instance.primaryFocus, same(focus));
      });

      testWidgets('not selectable: no checkboxes, activating opens', (tester) async {
        final r = await pump(tester, layout: layout, selectable: false);
        expect(find.byType(Checkbox), findsNothing);
        await key(tester, LogicalKeyboardKey.enter);
        expect(r.opened, ['/Saves']);
      });
    });
  }

  group('gamepad buttons', () {
    final upload = BrowserAction(icon: Icons.upload_file, label: 'Upload', onPressed: () {});

    testWidgets('X marks and unmarks the focused row, folders included', (tester) async {
      final r = await pump(tester);
      await key(tester, LogicalKeyboardKey.f2);
      expect(r.selected, {'/Saves'});
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.f2);
      expect(r.selected, {'/Saves', '/notes.txt'});
      await key(tester, LogicalKeyboardKey.f2);
      expect(r.selected, {'/Saves'});
      expect(r.opened, isEmpty);
    });

    testWidgets('X does nothing where nothing is selectable', (tester) async {
      final r = await pump(tester, selectable: false);
      await key(tester, LogicalKeyboardKey.f2);
      expect(r.selected, isEmpty);
    });

    testWidgets('X marks the focused grid tile', (tester) async {
      final r = await pump(tester, layout: BrowserLayout.grid);
      await key(tester, LogicalKeyboardKey.arrowRight);
      await key(tester, LogicalKeyboardKey.f2);
      expect(r.selected, {'/notes.txt'});
    });

    testWidgets('Y with nothing selected selects the focused row and lists the default actions', (tester) async {
      final r = await pump(tester, defaultActions: true, extraActions: () => [upload]);
      await key(tester, LogicalKeyboardKey.arrowDown);
      await key(tester, LogicalKeyboardKey.f3);
      await tester.pump();
      expect(r.selected, {'/notes.txt'});
      expect(sheetLabels(tester), ['Download', 'Zip', 'Delete', 'Clear selection', 'Upload']);
      expect(focusedOn('Download'), isTrue);
    });

    testWidgets('Y with a selection lists selectionActions, omits disabled ones, and runs the chosen one', (tester) async {
      final ran = <String>[];
      final r = await pump(
        tester,
        initiallySelected: {'/notes.txt'},
        selectionActions: [
          BrowserAction(icon: Icons.copy, label: 'Copy', onPressed: () => ran.add('copy')),
          const BrowserAction(icon: Icons.drive_file_rename_outline, label: 'Rename', onPressed: null),
        ],
      );
      await key(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(sheetLabels(tester), ['Copy', 'Clear selection']);
      await tester.tap(inSheet('Copy'));
      await tester.pumpAndSettle();
      expect(ran, ['copy']);
      expect(r.selected, {'/notes.txt'});
      expect(find.byType(RowMenuSheet), findsNothing); // sheet closed
    });

    testWidgets('a fast double Y opens one sheet and leaves the entry selected', (tester) async {
      final r = await pump(tester, defaultActions: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      expect(find.byType(RowMenuSheet), findsOneWidget);
      expect(r.selected, {'/Saves'});
    });

    testWidgets('Clear selection in the sheet clears', (tester) async {
      final r = await pump(tester, initiallySelected: {'/notes.txt'}, defaultActions: true);
      await key(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Clear selection'));
      await tester.pumpAndSettle();
      expect(r.selected, isEmpty);
    });

    testWidgets('while a transfer runs the selection actions are omitted', (tester) async {
      await pump(
        tester,
        initiallySelected: {'/notes.txt'},
        defaultActions: true,
        extraActions: () => [const BrowserAction(icon: Icons.upload_file, label: 'Upload', onPressed: null)],
        transfer: const BrowserTransfer(name: 'x', done: 1, total: 2, upload: false),
      );
      await key(tester, LogicalKeyboardKey.f3);
      await tester.pump();
      expect(sheetLabels(tester), ['Clear selection']);
    });

    testWidgets('Y where nothing is selectable shows just the extras', (tester) async {
      final r = await pump(tester, selectable: false, extraActions: () => [upload]);
      await key(tester, LogicalKeyboardKey.f3);
      await tester.pump();
      expect(r.selected, isEmpty);
      expect(sheetLabels(tester), ['Upload']);
    });

    testWidgets('Select opens the folder options: the view and Refresh', (tester) async {
      final r = await pump(tester);
      await key(tester, LogicalKeyboardKey.f4);
      await tester.pumpAndSettle();
      expect(sheetLabels(tester), ['Show as grid', 'Refresh']);
      await tester.tap(inSheet('Refresh'));
      await tester.pumpAndSettle();
      expect(r.calls, ['refresh']);
    });
  });

  group('touch', () {
    const zip = BrowserItem(id: '/game.zip', name: 'game.zip', isDir: false, size: 3);

    testWidgets('a long press marks a folder without opening it, and never unmarks', (tester) async {
      final r = await pump(tester);
      await tester.longPress(find.text('Saves'));
      await tester.pump();
      expect(r.selected, {'/Saves'});
      expect(r.opened, isEmpty);
      await tester.longPress(find.text('Saves'));
      await tester.pump();
      expect(r.selected, {'/Saves'});
    });

    testWidgets('a long press marks a grid tile too', (tester) async {
      final r = await pump(tester, layout: BrowserLayout.grid);
      await tester.longPress(find.text('Saves'));
      await tester.pump();
      expect(r.selected, {'/Saves'});
    });

    testWidgets('nothing is marked by a long press where nothing is selectable', (tester) async {
      final r = await pump(tester, selectable: false);
      await tester.longPress(find.text('Saves'));
      await tester.pump();
      expect(r.selected, isEmpty);
    });

    testWidgets('the selection bar names its actions, More holds the rest', (tester) async {
      final ran = <String>[];
      await pump(
        tester,
        items: const [folder, file, zip],
        initiallySelected: {'/notes.txt'},
        selectionActions: [
          BrowserAction(icon: Icons.copy, label: 'Copy', onPressed: () => ran.add('copy')),
          BrowserAction(icon: Icons.drive_file_rename_outline, label: 'Rename', onPressed: () => ran.add('rename'), inBar: false),
          const BrowserAction(icon: Icons.unarchive_outlined, label: 'Extract here', onPressed: null, inBar: false),
          BrowserAction(icon: Icons.delete_outline, label: 'Delete', onPressed: () => ran.add('delete'), destructive: true),
        ],
      );
      final bar = find.byKey(const ValueKey('browser-selection'));
      expect(find.descendant(of: bar, matching: find.text('1 selected')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Copy')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Delete')), findsOneWidget);
      expect(find.descendant(of: bar, matching: find.text('Rename')), findsNothing);
      await tester.tap(find.descendant(of: bar, matching: find.text('Copy')));
      expect(ran, ['copy']);
      await tester.tap(find.descendant(of: bar, matching: find.text('More')));
      await tester.pumpAndSettle();
      expect(sheetLabels(tester), ['Copy', 'Rename', 'Delete', 'Clear selection']);
      await tester.tap(inSheet('Rename'));
      await tester.pumpAndSettle();
      expect(ran, ['copy', 'rename']);
    });

    testWidgets('no More when every action is in the bar; a transfer disables them', (tester) async {
      await pump(tester, initiallySelected: {'/notes.txt'}, defaultActions: true, transfer: const BrowserTransfer(name: 'x', done: 1, total: 2, upload: false));
      final bar = find.byKey(const ValueKey('browser-selection'));
      expect(find.descendant(of: bar, matching: find.text('More')), findsNothing);
      expect(tester.widget<TextButton>(find.ancestor(of: find.text('Download'), matching: find.byType(TextButton))).onPressed, isNull);
    });

    testWidgets('on a phone the selection bar fits its labelled actions', (tester) async {
      await pump(tester, size: const Size(412, 915), initiallySelected: {'/notes.txt'}, selectionActions: [
        for (final l in ['Copy', 'Move', 'Delete']) BrowserAction(icon: Icons.copy, label: l, onPressed: () {}),
        BrowserAction(icon: Icons.copy, label: 'Zip', onPressed: () {}, inBar: false),
      ]);
      for (final l in ['Copy', 'Move', 'Delete', 'More']) {
        expect(tester.getRect(find.text(l)).right, lessThanOrEqualTo(412));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a crumb opens its folder, the current one does nothing, and none while busy', (tester) async {
      final went = <String>[];
      await pump(tester, crumbs: [Crumb('Internal', () => went.add('Internal')), Crumb('ROMs', () => went.add('ROMs')), Crumb('snes', () => went.add('snes'))]);
      await tester.tap(find.text('ROMs'));
      await tester.tap(find.text('snes'));
      expect(went, ['ROMs']);
      await pump(tester, busy: true, crumbs: [Crumb('Internal', () => went.add('Internal')), const Crumb('snes')]);
      await tester.tap(find.text('Internal'));
      expect(went, ['ROMs']);
    });

    testWidgets('the folder options button switches the view', (tester) async {
      await pump(tester);
      await tester.tap(find.byTooltip('Folder options'));
      await tester.pumpAndSettle();
      await tester.tap(inSheet('Show as grid'));
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
    });
  });

  testWidgets('with no choice made the browser is a list', (tester) async {
    await pump(tester, layout: null, size: const Size(412, 915));
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('an empty folder says so and offers its action', (tester) async {
    var made = 0;
    await pump(tester, items: const [], emptyAction: KitAction('New folder', () => made++));
    expect(find.text('This folder is empty'), findsOneWidget);
    await tester.tap(find.text('New folder'));
    expect(made, 1);
  });

  testWidgets('an error is one readable line, the raw text behind Details', (tester) async {
    const raw = "FileSystemException: Cannot open file, path = '/x/notes.txt' (OS Error: Permission denied, errno = 13)";
    await pump(tester, error: raw);
    expect(find.text('Permission denied'), findsOneWidget);
    expect(find.textContaining('errno'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text(raw), findsOneWidget);
  });

  testWidgets('a line from the screen wins over the derived one', (tester) async {
    await pump(tester, error: 'raw', errorLine: "Can't delete notes.txt: permission denied");
    expect(find.text("Can't delete notes.txt: permission denied"), findsOneWidget);
    expect(find.text('raw'), findsNothing);
  });

  group('errorReason', () {
    test('a file error gives the system reason', () {
      expect(errorReason(const FileSystemException('Cannot delete file', '/a', OSError('Permission denied', 13))), 'Permission denied');
      expect(errorReason(const FileSystemException('Cannot delete file', '/a')), 'Cannot delete file');
    });

    test('other errors lose their type and keep one short line', () {
      expect(errorReason(Exception('Login refused')), 'Login refused');
      expect(errorReason('SocketException: Connection timed out\nmore'), 'Connection timed out');
      expect(errorReason('x' * 200).length, 90);
      expect(errorReason(''), 'Unknown error');
    });
  });

  test('a remote trail is the root then each folder, each opening its own path', () {
    final went = <String>[];
    final crumbs = remoteCrumbs('Shares', '/Games/psx/Bios', went.add);
    expect([for (final c in crumbs) c.label], ['Shares', 'Games', 'psx', 'Bios']);
    for (final c in crumbs) {
      c.onTap!();
    }
    expect(went, ['', '/Games', '/Games/psx', '/Games/psx/Bios']);
    expect([for (final c in remoteCrumbs('/', '', went.add)) c.label], ['/']);
  });
}
