import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/screens/setup_wizard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('a console uses the Internet Archive through an IA url or IA auth', () {
    expect(const Console(id: 'a', name: 'A', urls: ['https://archive.org/download/item']).usesInternetArchive, isTrue);
    expect(const Console(id: 'b', name: 'B', urls: ['https://example.com/list'], auth: {'type': 'ia_s3'}).usesInternetArchive, isTrue);
    expect(const Console(id: 'c', name: 'C', urls: ['https://example.com/list']).usesInternetArchive, isFalse);
  });

  testWidgets('the connections step hides the IA login when no console uses IA', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('setup');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);

    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: SetupWizardScreen(initialStep: 2))));
    await tester.pump();

    expect(find.text('Internet Archive'), findsNothing);
    expect(find.text('No accounts needed for this catalog.'), findsOneWidget);
  });
}
