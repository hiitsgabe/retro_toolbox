import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/addon_store.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/services/console_merge.dart';

final addonProvider = StateNotifierProvider<AddonNotifier, List<Addon>>((ref) {
  return AddonNotifier(AddonStore.open());
});

/// Source priority order, derived from the list order.
final sourcePriorityProvider = Provider<List<String>>((ref) => [for (final addon in ref.watch(addonProvider)) addon.id]);

/// Addon id to the display name the user wrote or the catalog carried.
///
/// Callers must handle a missing id: a removed addon's cached games outlive
/// the removal, and their `sourceId` is no longer in the list.
final addonNamesProvider = Provider<Map<String, String>>(
  (ref) => {for (final addon in ref.watch(addonProvider)) addon.id: addon.name},
);

/// The merged catalog of every installed addon, in their order.
final mergedCatalogProvider = FutureProvider<MergedCatalog>((ref) async {
  ref.watch(addonProvider);
  return CatalogService().mergedCatalog();
});

/// How the addons screen fetches a catalog. Injectable for tests.
final catalogFetcherProvider = Provider<CatalogFetcher>((ref) => fetchCatalogByHttp);

/// Per-addon coverage, derived from the merged catalog.
final addonCoverageProvider = FutureProvider<Map<String, AddonCoverage>>((ref) async {
  return (await ref.watch(mergedCatalogProvider.future)).coverage();
});

/// An (addon, console) pair that needs a credential. The pair is the unit,
/// not the console: two addons serving one console have two secrets.
typedef AddonAccount = ({Addon addon, Console console});

/// Every addon account, in addon priority order.
final addonAccountsProvider = FutureProvider<List<AddonAccount>>((ref) async {
  final addons = ref.watch(addonProvider);
  final merged = await ref.watch(mergedCatalogProvider.future);
  final coverage = merged.coverage();
  return [
    for (final addon in addons)
      for (final consoleId in coverage[addon.id]?.authConsoles ?? const <String>[])
        if (merged.consoles[consoleId] != null) (addon: addon, console: merged.consoles[consoleId]!),
  ];
});

class AddonNotifier extends StateNotifier<List<Addon>> {
  final Future<AddonStore> _store;

  final Future<void> Function() _invalidateCache;

  /// Resolves once the initial list has loaded from disk.
  late final Future<void> ready;

  AddonNotifier(this._store, {Future<void> Function()? invalidateCache})
      : _invalidateCache = invalidateCache ?? CatalogService().invalidateForAddonChange,
        super(const []) {
    ready = _load();
  }

  Future<void> _load() async {
    final store = await _store;
    if (!mounted) return;
    state = store.load();
  }

  /// Installs, or reinstalls, an addon with the already-fetched catalog.
  /// Reinstalling keeps the position (`upsertAddon`).
  Future<void> install(Addon addon, String catalogJson) async {
    final store = await _store;
    await store.writeCatalog(addon.id, catalogJson);
    final next = upsertAddon(state, addon);
    await store.save(next);
    await _invalidateCache();
    if (mounted) state = next;
  }

  /// Removes the addon from the list and deletes its catalog from disk.
  /// Does not delete the vault secret: reinstalling the same source must find
  /// the token again, which is why `Addon.idFromUrl` is stable.
  Future<void> remove(String id) async {
    final store = await _store;
    await store.deleteCatalog(id);
    final next = removeAddon(state, id);
    await store.save(next);
    await _invalidateCache();
    if (mounted) state = next;
  }

  Future<void> reorder(int from, int to) async {
    final next = reorderAddons(state, from, to);
    final store = await _store;
    await store.save(next);
    await _invalidateCache();
    if (mounted) state = next;
  }
}
