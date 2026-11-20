import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/screens/rar_decompress_screen.dart';

void main() {
  testWidgets('renders with extract disabled until a file and folder are picked', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: RarDecompressScreen())));
    // Classic's title and button labels are in caps.
    expect(find.text('RAR DECOMPRESS'), findsOneWidget);
    expect(find.text('EXTRACT'), findsOneWidget);
    expect(find.text('Choose a .zip or .rar'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byKey(const ValueKey('kit-primary')));
    expect(button.onPressed, isNull);
  });
}
