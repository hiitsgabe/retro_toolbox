import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/source_pick_model.dart';
import 'package:roms_downloader/widgets/game_grid/batch_confirm_sheet.dart';

SourcePick _pick(String name, int size, {bool uncertain = false}) => SourcePick(
      gameId: 'snes/$name',
      title: name,
      filename: name,
      size: size,
      sourceId: 'listing',
      reason: 'chosen by your preferred region',
      uncertain: uncertain,
      game: Game(title: name, url: 'https://example/$name', size: size, consoleId: 'snes'),
    );

Widget _host(BatchPlan plan, {ValueChanged<BatchPlan>? onConfirm, ValueChanged<String>? onRemove}) {
  return MaterialApp(
    home: Scaffold(
      body: BatchConfirmSheet(
        plan: plan,
        onConfirm: onConfirm ?? (_) {},
        onRemove: onRemove ?? (_) {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows the count and total in the header', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('a.zip', 1024 * 1024),
      _pick('b.zip', 1024 * 1024),
    ])));

    expect(find.text('2 games, 2.0 MB'), findsOneWidget);
  });

  testWidgets('uses singular with a single game', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('a.zip', 1024)])));

    expect(find.text('1 game, 1.0 KB'), findsOneWidget);
  });

  testWidgets('lists the filename and the reason for each pick', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('Crystal.zip', 1024)])));

    expect(find.text('Crystal.zip'), findsOneWidget);
    expect(find.text('chosen by your preferred region'), findsOneWidget);
  });

  testWidgets('badges only the uncertain picks', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certain.zip', 1024),
      _pick('doubt.zip', 1024, uncertain: true),
    ])));

    expect(find.byIcon(Icons.help_outline), findsOneWidget);
  });

  testWidgets('separates the ones not entering the queue, with the reason', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'No source', reason: 'no addon has this game')],
    )));

    expect(find.text('Not going to the queue'), findsOneWidget);
    expect(find.text('No source'), findsOneWidget);
    expect(find.text('no addon has this game'), findsOneWidget);
  });

  testWidgets('the remove button returns that row\'s gameId', (tester) async {
    final removed = <String>[];
    await tester.pumpWidget(_host(
      BatchPlan(picks: [_pick('a.zip', 1024), _pick('b.zip', 1024)]),
      onRemove: removed.add,
    ));

    await tester.tap(find.byKey(const ValueKey('remove-snes/b.zip')));
    await tester.pump();

    expect(removed, ['snes/b.zip']);
  });

  testWidgets('confirming returns the whole plan', (tester) async {
    BatchPlan? confirmed;
    final plan = BatchPlan(picks: [_pick('a.zip', 1024)]);
    await tester.pumpWidget(_host(plan, onConfirm: (p) => confirmed = p));

    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(confirmed, same(plan));
  });

  testWidgets('with no pick the download button is disabled', (tester) async {
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    )));

    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Download'));
    expect(button.onPressed, isNull);
  });

  testWidgets('the header counts the uncertain picks and drops when there are none', (tester) async {
    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certain.zip', 1024),
      _pick('doubt.zip', 1024, uncertain: true),
      _pick('other.zip', 1024, uncertain: true),
    ])));
    expect(find.text('2 uncertain'), findsOneWidget);

    await tester.pumpWidget(_host(BatchPlan(picks: [
      _pick('certain.zip', 1024),
      _pick('doubt.zip', 1024, uncertain: true),
    ])));
    expect(find.text('1 uncertain'), findsOneWidget);

    await tester.pumpWidget(_host(BatchPlan(picks: [_pick('certain.zip', 1024)])));
    expect(find.textContaining('uncertain'), findsNothing);
  });

  testWidgets('Cancel closes the sheet without confirming anything', (tester) async {
    // Needs a real modal route the way `_confirmBatch` mounts it: the sheet
    // calls `maybePop`, so mounted straight in `body` it has nothing to pop and
    // the test would prove nothing.
    var confirmedCount = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showModalBottomSheet<BatchPlan>(
              context: context,
              builder: (_) => BatchConfirmSheet(
                plan: BatchPlan(picks: [_pick('a.zip', 1024)]),
                onConfirm: (_) => confirmedCount++,
                onRemove: (_) {},
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(BatchConfirmSheet), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(BatchConfirmSheet), findsNothing);
    expect(confirmedCount, 0);
  });

  testWidgets('failures-only header says zero games and the sheet stays open', (tester) async {
    // The sheet does not close itself when nothing can be downloaded: it exists
    // to show the reason. The header must tell the truth, and zero pluralizes to
    // "games".
    await tester.pumpWidget(_host(const BatchPlan(
      failures: [PickFailure(gameId: 'snes/c', title: 'C', reason: 'no source')],
    )));

    expect(find.text('0 games, 0 B'), findsOneWidget);
    expect(find.text('no source'), findsOneWidget);
  });
}
