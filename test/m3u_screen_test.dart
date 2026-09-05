import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/screens/m3u_screen.dart';

void main() {
  testWidgets('renders the empty state until a folder is chosen', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: M3uScreen()));
    expect(find.text('M3U Playlists'), findsOneWidget);
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.text('Scan'), findsNothing);
  });
}
