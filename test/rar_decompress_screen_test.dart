import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/screens/rar_decompress_screen.dart';

void main() {
  testWidgets('renders with extract disabled until a file and folder are picked', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RarDecompressScreen()));
    expect(find.text('Rar Decompress'), findsOneWidget);
    expect(find.text('Extract'), findsOneWidget);
    expect(find.text('No file selected'), findsOneWidget);

    // `find.byType` matches the exact runtime type, which misses the private
    // `_FilledButtonWithIcon` from `FilledButton.icon`; the predicate matches
    // by `is`.
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Extract'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
