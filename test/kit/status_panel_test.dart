import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';

import 'kit_support.dart';

void main() {
  Future<void> show(WidgetTester t, Widget panel, {(Size, double) device = odin2}) =>
      pumpKit(t, Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: Column(children: [panel]))), device: device);

  testWidgets('hidden draws nothing', (t) async {
    await show(t, const StatusPanel.hidden());
    expect(find.byType(KitPanel), findsNothing);
  });

  testWidgets('a missing requirement names it and runs its fix and its link', (t) async {
    var fixed = 0, read = 0;
    await show(
      t,
      StatusPanel.missingRequirement(
        title: 'chdman not found',
        detail: 'Part of the MAME tools.',
        actionLabel: 'Locate chdman',
        onAction: () => fixed++,
        linkLabel: 'How to get it',
        onLink: () => read++,
      ),
    );
    expect(find.text('chdman not found'), findsOneWidget);
    expect(find.text('Part of the MAME tools.'), findsOneWidget);
    await t.tap(find.text('Locate chdman'));
    await t.tap(find.text('How to get it'));
    expect((fixed, read), (1, 1));
  });

  testWidgets('working: the running item has the bar, the rest say where they are', (t) async {
    await show(
      t,
      const StatusPanel.working(items: [
        WorkItem('Final Fantasy VII (Disc 1)', progress: 0.62),
        WorkItem('Final Fantasy VII (Disc 2)', state: WorkState.queued),
        WorkItem('Metal Gear Solid (Disc 1)', state: WorkState.done),
      ]),
    );
    expect(find.text('62%'), findsOneWidget);
    expect(t.widget<LinearProgressIndicator>(find.byKey(const ValueKey('kit-status-bar'))).value, 0.62);
    expect(find.text('queued'), findsOneWidget);
    expect(find.text('done'), findsOneWidget);
  });

  testWidgets('working on a phone is a strip: the running item and how many wait', (t) async {
    await show(
      t,
      const StatusPanel.working(items: [
        WorkItem('Disc 2', state: WorkState.queued),
        WorkItem('Disc 1', progress: 0.5),
        WorkItem('Disc 3', state: WorkState.queued),
      ]),
      device: phone,
    );
    expect(find.text('Disc 1'), findsOneWidget);
    expect(find.text('50% · +2 queued'), findsOneWidget);
    expect(find.text('Disc 2'), findsNothing);
  });

  testWidgets('a working list with nothing in it is hidden', (t) async {
    await show(t, const StatusPanel.working(items: []));
    expect(find.byType(KitPanel), findsNothing);
  });

  testWidgets('done lists what was skipped and failed, with the reason', (t) async {
    await show(
      t,
      const StatusPanel.done(summary: 'Renamed 7 files', problems: [
        Problem('Chrono Trigger (USA).sfc', 'A file with the new name already exists'),
        Problem('EarthBound.sfc', 'Permission denied', failed: true),
      ]),
    );
    expect(find.text('Renamed 7 files'), findsOneWidget);
    expect(find.text('A file with the new name already exists'), findsOneWidget);
    expect(find.text('Permission denied'), findsOneWidget);
    expect(find.text('SKIPPED'), findsOneWidget);
    expect(find.text('FAILED'), findsOneWidget);
  });

  testWidgets('done can offer a next step for the result', (t) async {
    var runs = 0;
    await show(t, StatusPanel.done(summary: 'Saved a.zip in Downloads', actionLabel: 'Extract here', onAction: () => runs++));
    await t.tap(find.text('Extract here'));
    expect(runs, 1);
    await show(t, const StatusPanel.done(summary: 'Saved a.txt in Downloads'));
    expect(find.byKey(const ValueKey('kit-status-action')), findsNothing);
  });

  testWidgets('an error is one line; the raw error opens on Details', (t) async {
    await show(t, const StatusPanel.error(line: 'Could not read the disc image', details: 'FileSystemException: Cannot open file'));
    expect(find.text('Could not read the disc image'), findsOneWidget);
    expect(find.text('FileSystemException: Cannot open file'), findsNothing);
    await t.tap(find.text('Details'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kit-status-details')), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kit-status-details')), findsNothing);
  });

  testWidgets('an error without details has no Details', (t) async {
    await show(t, const StatusPanel.error(line: 'Nothing to convert'));
    expect(find.text('Details'), findsNothing);
  });
}
