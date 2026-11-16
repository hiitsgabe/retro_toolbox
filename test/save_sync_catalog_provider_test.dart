import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/catalog_source.dart';
import 'package:retro_toolbox/services/save_sync/hub.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/hub_config.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

String shaOf(String s) => sha256.convert(utf8.encode(s)).toString();

/// A published catalog on a loopback server. [bodies] are the recipe files,
/// and the index always describes them.
class Catalog {
  Catalog(this.server);

  final HttpServer server;
  final bodies = <String, String>{};
  late final String base = 'http://${server.address.host}:${server.port}/';

  static Future<Catalog> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final c = Catalog(s);
    s.listen((r) async {
      final name = r.uri.pathSegments.isEmpty ? '' : r.uri.pathSegments.last;
      if (name == 'index.json') {
        r.response.write(jsonEncode({
          'format': 1,
          'recipes': [
            for (final e in c.bodies.entries)
              {'id': e.key, 'packages': (jsonDecode(e.value) as Map)['packages'], 'status': 'draft', 'sha256': shaOf(e.value)},
          ],
        }));
      } else if (name.endsWith('.json') && c.bodies.containsKey(name.substring(0, name.length - 5))) {
        r.response.write(c.bodies[name.substring(0, name.length - 5)]);
      } else {
        r.response.statusCode = HttpStatus.notFound;
      }
      await r.response.close();
    });
    return c;
  }
}

const stardewPkg = 'com.chucklefish.stardewvalley';

/// A package and id the APK bundles no recipe for.
const catalogOnlyPkg = 'com.example.catalogonly';

/// The Stardew recipe from the repo folder, renamed so a test can tell copies apart.
String recipe({String id = 'stardew-valley', required String name, List<String>? packages}) {
  final j = jsonDecode(File('save_recipes/stardew-valley.json').readAsStringSync()) as Map<String, dynamic>;
  return jsonEncode({...j, 'id': id, 'name': name, if (packages != null) 'packages': packages});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the test binding stubs HTTP with 400s; loopback only here
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tmp;
  late Catalog catalog;
  late String hubPath;

  /// The catalog served for a recipe source; a test that switches sources
  /// points this somewhere else.
  late Catalog Function(String base) serving;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt-catalog-');
    catalog = await Catalog.start();
    serving = (_) => catalog;
    hubPath = '${tmp.path}/hub';
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({'save_sync_hub_folder': hubPath});
    // No Shizuku and no root: rows come straight from the recipes, no engine.
    messenger.setMockMethodCallHandler(ShizukuShell.channel, (call) async => call.method == 'status' ? {'running': false, 'granted': false, 'uid': -1} : null);
    PackageInfo.setMockInitialValues(appName: 'Retro Toolbox', packageName: 'name.rafaismy.retrotoolbox', version: '0.6.0', buildNumber: '60', buildSignature: '');
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(ShizukuShell.channel, null);
    await catalog.server.close(force: true);
    await tmp.delete(recursive: true);
  });

  Future<Hub> seedHub(Map<String, String> packageToRecipe) async {
    final hub = Hub(FolderBackend(Directory(hubPath)));
    await hub.open(deviceId: 'odin-02c4', create: true);
    if (packageToRecipe.isNotEmpty) {
      final at = DateTime.utc(2026, 11, 12);
      await hub.putConfig(
        {for (final e in packageToRecipe.entries) e.key: ConfigEntry(recipe: e.value, updatedAt: at, by: 'odin-02c4')},
        deviceId: 'odin-02c4',
        now: at,
      );
    }
    return hub;
  }

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      saveSyncProvider.overrideWith((ref) => SaveSyncNotifier(
            paths: DevicePaths(sdcard: tmp.path),
            catalogIndex: (base) {
              final served = serving(base);
              return RecipeIndex(baseUrl: served.base, cacheDir: Directory('${tmp.path}/cache-${served.server.port}'));
            },
          )),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  // The case that matters for devices already in the field: their recipe came
  // from the APK, so nothing from the catalog is cached yet, and the hub holds
  // an older copy. They must end on the catalog's.
  // The id is one the APK does not bundle, so the hub copy is really loaded
  // and the catalog has to beat it, not a bundled one.
  test('a device with only an older hub copy ends on the catalog body', () async {
    final hub = await seedHub({catalogOnlyPkg: 'catalog-only'});
    await hub.publishRecipe(jsonDecode(recipe(id: 'catalog-only', name: 'Catalog Only (hub copy)', packages: [catalogOnlyPkg])) as Map<String, dynamic>,
        source: 'bundled', deviceId: 'odin-02c4', now: DateTime.utc(2026, 11, 12));
    catalog.bodies['catalog-only'] = recipe(id: 'catalog-only', name: 'Catalog Only (catalog)', packages: [catalogOnlyPkg]);
    final c = container();

    await c.read(saveSyncProvider.notifier).refresh();

    final g = c.read(saveSyncProvider).games.single;
    expect(g.recipe.name, 'Catalog Only (catalog)');
    expect(g.source, 'repo');
  });

  test('a recipe changed in the catalog replaces the kept one on the next refresh', () async {
    await seedHub({stardewPkg: 'stardew-valley'});
    catalog.bodies['stardew-valley'] = recipe(name: 'v1');
    final c = container();
    await c.read(saveSyncProvider.notifier).refresh();
    expect(c.read(saveSyncProvider).games.single.recipe.name, 'v1');

    catalog.bodies['stardew-valley'] = recipe(name: 'v2');
    await c.read(saveSyncProvider.notifier).refresh();
    expect(c.read(saveSyncProvider).games.single.recipe.name, 'v2');
  });

  test('a recipe written on this device still beats the catalog', () async {
    await seedHub({stardewPkg: 'stardew-valley'});
    catalog.bodies['stardew-valley'] = recipe(name: 'Catalog');
    final mine = File('${tmp.path}/RetroToolbox/SaveSync/recipes/stardew-valley.json');
    await mine.create(recursive: true);
    await mine.writeAsString(recipe(name: 'Mine'));
    final c = container();

    await c.read(saveSyncProvider.notifier).refresh();

    final g = c.read(saveSyncProvider).games.single;
    expect(g.recipe.name, 'Mine');
    expect(g.source, 'user');
  });

  test('an unreachable catalog is no error and the row still shows', () async {
    final hub = await seedHub({catalogOnlyPkg: 'catalog-only'});
    await hub.publishRecipe(jsonDecode(recipe(id: 'catalog-only', name: 'Catalog Only (hub copy)', packages: [catalogOnlyPkg])) as Map<String, dynamic>,
        source: 'bundled', deviceId: 'odin-02c4', now: DateTime.utc(2026, 11, 12));
    await catalog.server.close(force: true);
    final c = container();

    await c.read(saveSyncProvider.notifier).refresh();

    final s = c.read(saveSyncProvider);
    expect(s.error, isNull);
    expect(s.games, hasLength(1));
    expect(s.games.single.source, 'hub');
  });

  // Recipes from the old source must not outlive it, and the refresh that
  // follows the switch is the one that drops them.
  test('switching the recipe source drops what the old one brought', () async {
    await seedHub({catalogOnlyPkg: 'catalog-only'});
    catalog.bodies['catalog-only'] = recipe(id: 'catalog-only', name: 'Catalog Only', packages: [catalogOnlyPkg]);
    final empty = await Catalog.start();
    addTearDown(() => empty.server.close(force: true));
    serving = (base) => base == 'https://example.com/other/' ? empty : catalog;
    final c = container();
    final n = c.read(saveSyncProvider.notifier);
    await n.refresh();
    expect(c.read(saveSyncProvider).games.single.source, 'repo');

    expect(await n.setCatalogSetting('https://example.com/other'), isTrue);

    expect(c.read(saveSyncProvider).games.where((g) => g.recipe.id == 'catalog-only'), isEmpty);
  });

  // The configuration names the recipe; the catalog publishing another one
  // for the same package must not slip in under it.
  test('a catalog recipe with another id than the chosen one is not brought in', () async {
    await seedHub({catalogOnlyPkg: 'someone-elses'});
    catalog.bodies['catalog-only'] = recipe(id: 'catalog-only', name: 'Catalog Only', packages: [catalogOnlyPkg]);
    final c = container();

    await c.read(saveSyncProvider.notifier).refresh();

    expect(c.read(saveSyncProvider).games, isEmpty);
  });

  // Before this change the id was written to the hub configuration and no row
  // ever appeared, because nothing downloaded the body.
  test('adding an app only the catalog knows makes its row appear', () async {
    await seedHub({});
    catalog.bodies['catalog-only'] = recipe(id: 'catalog-only', name: 'Catalog Only', packages: ['com.example.catalogonly']);
    final c = container();

    final error = await c.read(saveSyncProvider.notifier).addApps({'com.example.catalogonly': 'catalog-only'});

    expect(error, isNull);
    final g = c.read(saveSyncProvider).games.single;
    expect(g.recipe.id, 'catalog-only');
    expect(g.source, 'repo');
  });

  test('an add whose recipe cannot be downloaded says why and writes nothing', () async {
    await seedHub({});
    catalog.bodies['catalog-only'] = recipe(id: 'catalog-only', name: 'Catalog Only', packages: ['com.example.catalogonly']);
    final c = container();
    final n = c.read(saveSyncProvider.notifier);
    await n.catalog(); // the index is cached, the body is not
    await catalog.server.close(force: true);

    final error = await n.addApps({'com.example.catalogonly': 'catalog-only'});

    expect(error, contains('com.example.catalogonly'));
    final hub = Hub(FolderBackend(Directory(hubPath)));
    await hub.open(deviceId: 'probe-0000');
    expect((await hub.config()).isEmpty, isTrue);
  });

  test('the recipe source setting takes https only and can go back to the default', () async {
    await seedHub({});
    final n = container().read(saveSyncProvider.notifier);

    expect(await n.setCatalogSetting('http://plain.example/r'), isFalse);
    expect(await n.catalogBase(), defaultCatalogBase);
    expect(await n.setCatalogSetting('https://example.com/r'), isTrue);
    expect(await n.catalogSetting(), 'https://example.com/r/');
    expect(await n.catalogBase(), 'https://example.com/r/');
    expect(await n.setCatalogSetting(null), isTrue);
    expect(await n.catalogSetting(), isNull);
    expect(await n.catalogBase(), defaultCatalogBase);
  });
}
