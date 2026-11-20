import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  group('pathParts', () {
    test('from the nearest known root', () {
      expect(pathParts('/storage/emulated/0/ROMs/psx/Crash.cue', home: '/home/x'), ['ROMs', 'psx', 'Crash.cue']);
      expect(pathParts('/storage/emulated/0/ROMs', home: '/home/x'), ['Internal', 'ROMs']);
      expect(pathParts('/storage/emulated/0/Download/a.zip', home: '/home/x'), ['Downloads', 'a.zip']);
      expect(pathParts('/storage/emulated/0/Music/', home: '/home/x'), ['Internal', 'Music']);
      expect(pathParts('/storage/1A2B-3C4D/games/x.nsp', home: '/home/x'), ['SD card', 'games', 'x.nsp']);
      expect(pathParts('/home/x/Games/a.iso', home: '/home/x'), ['Home', 'Games', 'a.iso']);
      expect(pathParts('/userdata/roms/snes/smw.sfc', home: '/home/x'), ['ROMs', 'snes', 'smw.sfc']);
      expect(pathParts('/tmp/out', home: '/home/x'), ['/tmp', 'out']);
    });
  });

  group('fitPath', () {
    bool under(int n) => true;
    test('whole when it fits', () {
      expect(fitPath(['ROMs', 'psx', 'a.cue'], (_) => under(0)), 'ROMs › psx › a.cue');
    });

    test('parts after the root go first, then the name is cut in the middle, never at the end', () {
      final parts = ['Internal', 'one', 'two', 'three', 'Final Fantasy VII (USA) (Disc 1).cue'];
      final dropped = fitPath(parts, (s) => s.length <= 'Internal › … › three › Final Fantasy VII (USA) (Disc 1).cue'.length);
      expect(dropped, 'Internal › … › three › Final Fantasy VII (USA) (Disc 1).cue');
      final cut = fitPath(parts, (s) => s.length <= 30);
      expect(cut.length, lessThanOrEqualTo(30));
      expect(cut, startsWith('Internal › … › Final'));
      expect(cut, endsWith('1).cue'));
    });
  });

  testWidgets('an empty slot says what to choose, has no verb, and the row picks', (t) async {
    var picks = 0;
    await pumpKit(t, Scaffold(body: Slot(label: 'Disc image', emptyText: 'Choose a disc image', onPick: () => picks++)));
    expect(find.text('Choose a disc image'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
    await t.tap(find.text('Disc image'));
    expect(picks, 1);
  });

  testWidgets('a filled slot shows the shortened path and Change', (t) async {
    var picks = 0;
    await pumpKit(t, Scaffold(body: Slot(label: 'Output folder', folder: true, path: '/storage/emulated/0/ROMs/psx', onPick: () => picks++)));
    expect(find.text('ROMs › psx'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    await t.tap(find.text('Change'));
    expect(picks, 1);
  });

  testWidgets('a long path keeps its file name on a phone', (t) async {
    await pumpKit(
      t,
      const Scaffold(body: Slot(label: 'Disc image', path: '/storage/emulated/0/ROMs/psx/Final Fantasy VII (USA)/Final Fantasy VII (USA) (Disc 1).cue')),
      device: phone,
    );
    final shown = t.widget<Text>(find.descendant(of: find.byType(PathText), matching: find.byType(Text))).data!;
    expect(shown, contains('…'));
    expect(shown, endsWith('.cue'));
    expect(t.takeException(), isNull);
  });

  testWidgets('the shortened path is measured as it paints, so it is never cut at the edge', (t) async {
    await pumpKit(
      t,
      const Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            // Spacing from the surroundings that the path's own style does not set.
            child: DefaultTextStyle(style: TextStyle(letterSpacing: 3), child: PathText('/storage/emulated/0/ROMs/psx/Crash Bandicoot (USA).cue')),
          ),
        ),
      ),
    );
    final p = t.renderObject<RenderParagraph>(find.descendant(of: find.byType(PathText), matching: find.byType(RichText)));
    expect(p.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(300));
    // Cut in the middle: the end of the name stays.
    expect(p.text.toPlainText(), endsWith('ue'));
  });

  testWidgets('a locked slot says why and does not pick', (t) async {
    var picks = 0;
    await pumpKit(t, Scaffold(body: Slot(label: 'Folder', path: '/storage/emulated/0/ROMs', lockedReason: 'Stop the server to change', onPick: () => picks++)));
    expect(find.text('Stop the server to change'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
    await t.tap(find.text('Folder'));
    expect(picks, 0);
  });
}
