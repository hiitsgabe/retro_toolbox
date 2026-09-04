import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/screens/collection_clean_screen.dart';

void main() {
  testWidgets('renders the empty state until a folder is chosen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CollectionCleanScreen()));
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.text('Pick a folder to enable cleanup.'), findsOneWidget);
    // Sections only appear after a folder is picked.
    expect(find.text('Dedupe Games'), findsNothing);
  });
}
