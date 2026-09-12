import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/screens/rar_decompress_screen.dart';

void main() {
  testWidgets('renders with extract disabled until a file and folder are picked', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RarDecompressScreen()));
    expect(find.text('Rar Decompress'), findsOneWidget);
    expect(find.text('Extract'), findsOneWidget);
    expect(find.text('No file selected'), findsOneWidget);

    // `FilledButton.icon` é factory e devolve `_FilledButtonWithIcon`, uma
    // subclasse privada. `find.byType` casa por tipo exato
    // (`finders.dart`: `candidate.widget.runtimeType == widgetType`), então o
    // `widgetWithText(FilledButton, ...)` que estava aqui não achava o botão e
    // o teste morria em `Bad state: No element` antes de afirmar coisa alguma.
    // O predicado casa por `is`, que é o que a asserção sempre quis dizer.
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Extract'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}
