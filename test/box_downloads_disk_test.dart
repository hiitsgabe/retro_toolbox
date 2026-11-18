import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/widgets/game_list/game_action_buttons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'game_groups_support.dart';

class _FakeCatalogService extends CatalogService {
  _FakeCatalogService(this.games);
  final List<Game> games;
  @override
  Future<List<Game>> loadCatalog(String consoleId,
          {String? iaAccessKey, String? iaSecretKey, String? authToken, void Function(int done, int total)? onProgress, void Function(String status)? onStatus}) async =>
      games;
}

/// The real catalog, settings and disk: gamesToDownload only reads, through a WidgetRef over the container.
class _Ref implements WidgetRef {
  _Ref(this.c);
  final ProviderContainer c;
  @override
  T read<T>(ProviderListenable<T> p) => c.read(p);
  @override
  BuildContext get context => throw UnimplementedError();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _psx = Console(id: 'psx', name: 'PSX', urls: []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tmp = Directory.systemTemp.createTempSync('t7scratch');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => tmp.path,
  );
  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<(ProviderContainer, List<Game>)> setUp(List<Game> games, List<String> onDisk, {Set<String>? regions}) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('t7dir');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final f in onDisk) {
      File('${dir.path}/$f').writeAsStringSync('x');
    }
    final c = ProviderContainer(overrides: [
      catalogProvider.overrideWith((ref) => CatalogNotifier(ref, _FakeCatalogService(games))),
    ]);
    addTearDown(c.dispose);
    final settings = c.read(settingsProvider.notifier);
    await settings.loaded;
    await settings.setSetting<String>(AppSettings.downloadDir, dir.path, 'psx');
    c.read(gameStateManagerProvider); // the manager exists before the catalog loads, as in the app
    final catalog = c.read(catalogProvider.notifier);
    await catalog.loadCatalog(_psx);
    catalog.clearFilters();
    if (regions != null) catalog.updateFilter(c.read(catalogProvider).filter.copyWith(regions: regions));
    await catalog.updateFilteredGames(immediate: true);
    final shown = c.read(catalogProvider).paginatedFilteredGames;
    // The list rows watch each shown entry's state; that is what resolves it.
    final subs = [for (final e in shown) c.listen(gameStateProvider(e), (_, __) {})];
    addTearDown(() {
      for (final s in subs) {
        s.close();
      }
    });
    for (var i = 0; i < 200; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final st = c.read(gameStateManagerProvider);
      if (shown.every((e) => st[e.gameId]?.status != GameStatus.init && st[e.gameId]?.status != GameStatus.loading)) break;
    }
    return (c, shown);
  }

  test('a box member on disk is not downloaded again, though its state is still init', () async {
    final files = psxGamesStartingWith('Arc the Lad Collection - ');
    const ii = 'Arc the Lad Collection - Arc the Lad II (USA).zip';
    final (c, shown) = await setUp(files, [ii]);
    final box = shown.single;
    final out = await gamesToDownload(_Ref(c), box, catalog: files);
    expect(out.map((g) => g.title), isNot(contains(ii)));
  });

  test('a member on disk in Europe is not downloaded a second time in USA', () async {
    final foo = [for (final n in ['Foo Collection - Bar (USA)', 'Foo Collection - Bar (Europe)', 'Foo Collection - Baz (USA)', 'Foo Collection - Baz (Europe)']) psxGame(n)];
    final (c, shown) = await setUp(foo, ['Foo Collection - Bar (Europe).zip']);
    final box = shown.single;
    final out = await gamesToDownload(_Ref(c), box, catalog: foo);
    expect(out.map((g) => g.title), ['Foo Collection - Baz (USA).zip']);
  });

  test('the second member on disk in Europe: the first gets its USA version', () async {
    final foo = [for (final n in ['Foo Collection - Bar (USA)', 'Foo Collection - Bar (Europe)', 'Foo Collection - Baz (USA)', 'Foo Collection - Baz (Europe)']) psxGame(n)];
    final (c, shown) = await setUp(foo, ['Foo Collection - Baz (Europe).zip']);
    final box = shown.single;
    final out = await gamesToDownload(_Ref(c), box, catalog: foo);
    expect(out.map((g) => g.title), ['Foo Collection - Bar (USA).zip']);
  });

  test('with a Europe filter the list shows the Europe versions, and Download gets those', () async {
    final foo = [for (final n in ['Foo Collection - Bar (USA)', 'Foo Collection - Bar (Europe)', 'Foo Collection - Baz (USA)', 'Foo Collection - Baz (Europe)']) psxGame(n)];
    final (c, shown) = await setUp(foo, [], regions: {'Europe'});
    final box = shown.single;
    expect(box.title, 'Foo Collection - Bar (Europe).zip');
    final out = await gamesToDownload(_Ref(c), box, catalog: foo);
    expect(out.map((g) => g.title), ['Foo Collection - Bar (Europe).zip', 'Foo Collection - Baz (Europe).zip']);
  });
}
