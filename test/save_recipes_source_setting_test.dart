import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/catalog_source.dart';
import 'package:retro_toolbox/widgets/settings/save_recipes_source_setting.dart';

class FakeNotifier extends SaveSyncNotifier {
  String? stored;

  @override
  Future<void> refresh() async {}

  @override
  Future<String?> catalogSetting() async => stored;

  @override
  Future<String> catalogBase() async => resolveCatalogBase(setting: stored);

  @override
  Future<bool> setCatalogSetting(String? url) async {
    final n = url == null ? null : normalizeCatalogUrl(url);
    if (url != null && n == null) return false;
    stored = n;
    return true;
  }
}

/// A store that cannot be reached, as on a platform with no preferences
/// backend: every read and write throws.
class ThrowingNotifier extends FakeNotifier {
  @override
  Future<String?> catalogSetting() async => throw StateError('no store');

  @override
  Future<bool> setCatalogSetting(String? url) async => throw StateError('no store');
}

void main() {
  Future<FakeNotifier> pump(WidgetTester t, [FakeNotifier? notifier]) async {
    final fake = notifier ?? FakeNotifier();
    await t.pumpWidget(ProviderScope(
      overrides: [saveSyncProvider.overrideWith((ref) => fake)],
      child: const MaterialApp(home: Scaffold(body: SaveRecipesSourceSetting())),
    ));
    await t.pumpAndSettle();
    return fake;
  }

  testWidgets('shows the default source until one is set', (t) async {
    await pump(t);
    expect(find.text('Reading from: $defaultCatalogBase'), findsOneWidget);
  });

  testWidgets('an address that is not https is refused and nothing is stored', (t) async {
    final fake = await pump(t);
    await t.enterText(find.byType(TextField), 'http://plain.example/r');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(find.text('Use an https:// address'), findsOneWidget);
    expect(fake.stored, isNull);
  });

  testWidgets('a good address is stored and shown; reset goes back to the default', (t) async {
    final fake = await pump(t);
    await t.enterText(find.byType(TextField), 'https://example.com/r');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(fake.stored, 'https://example.com/r/');
    expect(find.text('Reading from: https://example.com/r/'), findsOneWidget);

    await t.tap(find.text('Reset to default'));
    await t.pumpAndSettle();
    expect(fake.stored, isNull);
    expect(find.text('Reading from: $defaultCatalogBase'), findsOneWidget);
  });

  testWidgets('a store that throws neither escapes nor leaves the buttons dead', (t) async {
    await pump(t, ThrowingNotifier());
    expect(t.takeException(), isNull);

    await t.enterText(find.byType(TextField), 'https://example.com/r');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.textContaining('no store'), findsOneWidget);
    expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);
    expect(t.widget<TextField>(find.byType(TextField)).enabled, isTrue);
  });
}
