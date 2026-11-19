import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/app_state_model.dart';
import 'package:retro_toolbox/models/catalog_filter_model.dart';
import 'package:retro_toolbox/models/catalog_model.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/download_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/widgets/header/header.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCatalog extends StateNotifier<CatalogState> implements CatalogNotifier {
  _FakeCatalog(CatalogFilter filter) : super(CatalogState(filter: filter));
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeDownloads extends StateNotifier<DownloadState> implements DownloadNotifier {
  _FakeDownloads() : super(const DownloadState());
  @override
  bool hasDownloadableSelectedGames() => false;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _FakeAppState extends StateNotifier<AppState> implements AppStateNotifier {
  _FakeAppState() : super(const AppState());
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

// What the filter modal's Clear button sets: every filter off.
const _cleared = CatalogFilter(regions: {}, dumpQualities: {}, romTypes: {}, modifications: {}, distributionTypes: {});

void main() {
  group('differsFromDefault', () {
    test('the default filter does not differ', () {
      expect(const CatalogFilter().differsFromDefault, isFalse);
      expect(const CatalogFilter().copyWith(regions: {'USA'}).differsFromDefault, isFalse);
    });

    test('a changed filter differs', () {
      expect(const CatalogFilter().copyWith(regions: {'USA', 'Europe'}).differsFromDefault, isTrue);
      expect(const CatalogFilter().copyWith(distributionTypes: {'standard'}).differsFromDefault, isTrue);
      expect(const CatalogFilter().copyWith(showFavoritesOnly: true).differsFromDefault, isTrue);
      expect(const CatalogFilter().copyWith(minRating: 3).differsFromDefault, isTrue);
    });

    test('the Clear result differs', () {
      expect(_cleared.differsFromDefault, isTrue);
    });

    test('sorting is not filtering', () {
      expect(const CatalogFilter().copyWith(sort: CatalogSort.newest).differsFromDefault, isFalse);
    });
  });

  group('header filter icon', () {
    Future<void> pump(WidgetTester t, CatalogFilter filter) async {
      SharedPreferences.setMockInitialValues({});
      await t.pumpWidget(ProviderScope(
        overrides: [
          catalogProvider.overrideWith((ref) => _FakeCatalog(filter)),
          downloadProvider.overrideWith((ref) => _FakeDownloads()),
          appStateProvider.overrideWith((ref) => _FakeAppState()),
        ],
        child: MaterialApp(home: Scaffold(body: Header(consoles: const [], selectedConsole: null, onConsoleSelect: (Console _) {}))),
      ));
    }

    testWidgets('is not lit on the default filter', (t) async {
      await pump(t, const CatalogFilter());
      expect(find.byIcon(Icons.filter_alt_outlined), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt), findsNothing);
    });

    testWidgets('is lit on a changed filter', (t) async {
      await pump(t, const CatalogFilter().copyWith(regions: {'Japan'}));
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
    });

    testWidgets('is lit after Clear', (t) async {
      await pump(t, _cleared);
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
    });
  });
}
