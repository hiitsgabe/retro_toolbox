import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/widgets/footer/selection_bar.dart';

Widget _host({required int count, VoidCallback? onClear, VoidCallback? onDownload}) {
  return MaterialApp(
    home: Scaffold(
      body: SelectionBar(
        count: count,
        onClear: onClear ?? () {},
        onDownload: onDownload ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('takes no height when the selection is empty', (tester) async {
    await tester.pumpWidget(_host(count: 0));

    expect(find.byIcon(Icons.close), findsNothing);
    expect(find.text('Download'), findsNothing);
    expect(tester.getSize(find.byType(SelectionBar)).height, 0);
  });

  testWidgets('singular count with one item', (tester) async {
    await tester.pumpWidget(_host(count: 1));

    expect(find.text('1 selected'), findsOneWidget);
  });

  testWidgets('plural count with more than one item', (tester) async {
    await tester.pumpWidget(_host(count: 3));

    expect(find.text('3 selected'), findsOneWidget);
  });

  testWidgets('is exactly 48 high with a selection', (tester) async {
    await tester.pumpWidget(_host(count: 3));

    // The IconButton and FilledButton are 48 on their own from the Material
    // touch target, so `SizedBox(height: 48)` has no slack; extra padding overflows.
    expect(tester.getSize(find.byType(SelectionBar)).height, 48);
  });

  testWidgets('the close icon calls onClear and the button calls onDownload', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(_host(
      count: 3,
      onClear: () => fired.add('clear'),
      onDownload: () => fired.add('download'),
    ));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.tap(find.text('Download'));
    await tester.pump();

    expect(fired, ['clear', 'download']);
  });
}
