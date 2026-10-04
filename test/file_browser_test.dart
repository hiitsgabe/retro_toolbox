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

  Future<({List<String> opened, Set<String> selected})> pump(
    WidgetTester tester, {
    BrowserLayout layout = BrowserLayout.list,
    bool selectable = true,
    bool busy = false,
    List<BrowserItem> items = const [folder, file],
  }) async {
    final key = GlobalKey<NavigatorState>();
    final opened = <String>[];
    final selected = <String>{};
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
    return (opened: opened, selected: selected);
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
        // List: checkbox sits left of the row. Grid: it overlays the tile's top-left corner.
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

      testWidgets('while busy, a folder cannot be opened', (tester) async {
        final r = await pump(tester, layout: layout, busy: true);
        await tester.tap(find.text('Saves'));
        await key(tester, LogicalKeyboardKey.enter);
        expect(r.opened, isEmpty);
      });

      testWidgets('not selectable: no checkboxes, activating opens', (tester) async {
        final r = await pump(tester, layout: layout, selectable: false);
        expect(find.byType(Checkbox), findsNothing);
        await key(tester, LogicalKeyboardKey.enter);
        expect(r.opened, ['/Saves']);
      });
    });
  }
}
