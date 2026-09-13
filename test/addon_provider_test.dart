import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/services/addon_store.dart';

Future<AddonStore> _store(List<Addon> addons) async {
  SharedPreferences.setMockInitialValues({});
  SharedPreferences.resetStatic();
  final root = await Directory.systemTemp.createTemp('addon_provider_test');
  addTearDown(() => root.delete(recursive: true));
  final store = AddonStore(await SharedPreferences.getInstance(), root);
  await store.save(addons);
  return store;
}

/// Returns the container with the initial list loaded, plus the store and the
/// invalidation counter. At the top of the file, not inside `main`, to satisfy
/// `no_leading_underscores_for_local_identifiers`.
Future<({ProviderContainer container, AddonStore store, List<int> invalidations})> _build(List<Addon> initial) async {
  final store = await _store(initial);
  final invalidations = <int>[];
  final container = ProviderContainer(overrides: [
    addonProvider.overrideWith((ref) => AddonNotifier(
          Future.value(store),
          invalidateCache: () async => invalidations.add(1),
        )),
  ]);
  addTearDown(container.dispose);
  await container.read(addonProvider.notifier).ready;
  return (container: container, store: store, invalidations: invalidations);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads the store list on boot', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
  });

  test('install appends at the end and persists', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'b', name: 'B'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.store.load().map((x) => x.id), ['a', 'b']);
  });

  test('install of the same id replaces without changing position', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A fixed'), '[]');
    expect(m.container.read(addonProvider).map((x) => x.id), ['a', 'b']);
    expect(m.container.read(addonProvider).first.name, 'A fixed');
  });

  test('install writes the catalog to the addon file', () async {
    final m = await _build(const []);
    await m.container.read(addonProvider.notifier).install(const Addon(id: 'a', name: 'A'), '[{"name":"SNES"}]');
    expect(await m.store.readCatalog('a'), '[{"name":"SNES"}]');
  });

  test('remove drops from the list and persists', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).remove('a');
    expect(m.container.read(addonProvider).map((x) => x.id), ['b']);
    expect(m.store.load().map((x) => x.id), ['b']);
  });

  test('remove deletes the addon\'s catalog file', () async {
    final m = await _build(const []);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'a', name: 'A'), '[]');
    await notifier.remove('a');
    expect(await m.store.readCatalog('a'), isNull);
  });

  test('reorder applies ReorderableListView semantics and persists', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B'), Addon(id: 'c', name: 'C')]);
    await m.container.read(addonProvider.notifier).reorder(0, 3);
    expect(m.container.read(addonProvider).map((x) => x.id), ['b', 'c', 'a']);
    expect(m.store.load().map((x) => x.id), ['b', 'c', 'a']);
  });

  test('install and remove invalidate the cache, and so does reorder', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    final notifier = m.container.read(addonProvider.notifier);
    await notifier.install(const Addon(id: 'c', name: 'C'), '[]');
    await notifier.remove('a');
    await notifier.reorder(0, 2);
    expect(m.invalidations.length, 3);
  });

  test('sourcePriority returns the ids in list order', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    expect(m.container.read(sourcePriorityProvider), ['a', 'b']);
  });

  test('sourcePriority follows the drag', () async {
    final m = await _build(const [Addon(id: 'a', name: 'A'), Addon(id: 'b', name: 'B')]);
    await m.container.read(addonProvider.notifier).reorder(1, 0);
    expect(m.container.read(sourcePriorityProvider), ['b', 'a']);
  });

  test('addonNames maps each id to the addon name', () async {
    final m = await _build(const [
      Addon(id: 'myrient', name: 'Myrient'),
      Addon(id: kBuiltinAddonId, name: 'Built-in catalog'),
    ]);

    expect(m.container.read(addonNamesProvider), {
      'myrient': 'Myrient',
      kBuiltinAddonId: 'Built-in catalog',
    });
  });
}
