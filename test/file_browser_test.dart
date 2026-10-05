import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/browser_layout_provider.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/file_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const folder = BrowserItem(id: '/Saves', name: 'Saves', isDir: true, size: 0);
  const file = BrowserItem(id: '/notes.txt', name: 'notes.txt', isDir: false, size: 3);

  Future<({List<String> opened, Set<String> selected, List<String> calls})> pump(
    WidgetTester tester, {
    BrowserLayout layout = BrowserLayout.list,
    bool selectable = true,
    bool busy = false,
    List<BrowserItem> items = const [folder, file],
    Set<String> initiallySelected = const {},
    bool defaultActions = false,
    List<BrowserAction>? selectionActions,
    List<BrowserAction> Function()? extraActions,
    BrowserTransfer? transfer,
  }) async {
    final key = GlobalKey<NavigatorState>();
    final opened = <String>[];
    final calls = <String>[];
    final selected = {...initiallySelected};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [browserLayoutProvider.overrideWith((ref) => BrowserLayoutNotifier()..state = layout)],
        child: MaterialApp(
          navigatorKey: key,
          builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => FileBrowserView(
                locationLabel: '/',
                canGoUp: false,
                busy: busy,
                items: items,
                selectedIds: selected,
                selectable: selectable,
                transfer: transfer,
                onDownload: defaultActions ? () => calls.add('download') : null,
                onZip: defaultActions ? () => calls.add('zip') : null,
                onDelete: defaultActions ? () => calls.add('delete') : null,
                selectionActions: selectionActions,
                extraActions: extraActions,
                onRefresh: () {},
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
      expect([for (final t in tester.widgetList<ListTile>(find.byType(ListTile))) (t.title as Text).data].skip(2), [
        'Download',
        'Zip',
        'Delete',
        'Clear selection',
        'Upload',
      ]);
      expect(tester.widget<ListTile>(find.widgetWithText(ListTile, 'Download')).autofocus, isTrue);
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
      expect(find.widgetWithText(ListTile, 'Copy'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Rename'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Clear selection'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Copy'));
      await tester.pumpAndSettle();
      expect(ran, ['copy']);
      expect(r.selected, {'/notes.txt'});
      expect(find.widgetWithText(ListTile, 'Copy'), findsNothing); // sheet closed
    });

    testWidgets('Clear selection in the sheet clears', (tester) async {
      final r = await pump(tester, initiallySelected: {'/notes.txt'}, defaultActions: true);
      await key(tester, LogicalKeyboardKey.f3);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Clear selection'));
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
      expect(find.widgetWithText(ListTile, 'Download'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Upload'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Clear selection'), findsOneWidget);
    });

    testWidgets('Y where nothing is selectable shows just the extras', (tester) async {
      final r = await pump(tester, selectable: false, extraActions: () => [upload]);
      await key(tester, LogicalKeyboardKey.f3);
      await tester.pump();
      expect(r.selected, isEmpty);
      expect(find.widgetWithText(ListTile, 'Upload'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Clear selection'), findsNothing);
    });
  });
}
