import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/screens/add_catalog_source_screen.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

void main() {
  final key = GlobalKey<NavigatorState>();
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: key,
            builder: (c, child) => DpadScope(navigatorKey: key, child: child!),
            home: const AddCatalogSourceScreen(),
          ),
        ),
      );

  testWidgets('renders and the IA toggle swaps the URL field label', (tester) async {
    await pump(tester);
    expect(find.text('Directory listing URL'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(find.text('archive.org item ID or URL'), findsOneWidget);
  });

  testWidgets('Add with empty fields surfaces a validation snackbar', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester);
    await tester.tap(find.text('Add to catalog'));
    await tester.pump();
    expect(find.text('Enter a name.'), findsOneWidget);
  });

  testWidgets('Start runs Add (validation snackbar proves it ran)', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).first); // focus inside the screen
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pump();
    expect(find.text('Enter a name.'), findsOneWidget);
  });
}
