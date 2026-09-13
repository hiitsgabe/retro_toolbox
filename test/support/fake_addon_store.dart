import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/services/addon_store.dart';

/// A fully in-memory `AddonStore` for widget tests, because disk IO hangs
/// inside a `testWidgets` body (it runs under FakeAsync).
///
/// `noSuchMethod` throws so an unimplemented call dies naming the method
/// instead of passing silently.
class FakeAddonStore implements AddonStore {
  List<Addon> _addons;

  /// What `writeCatalog` stored, per addon. Public so a case can assert the
  /// install wrote the catalog, not only that it touched the list.
  final Map<String, String> catalogs = {};

  FakeAddonStore(List<Addon> addons) : _addons = List.of(addons);

  @override
  List<Addon> load() => List.of(_addons);

  @override
  Future<void> save(List<Addon> list) async {
    _addons = List.of(list);
  }

  @override
  Future<String?> readCatalog(String addonId) async => catalogs[addonId];

  @override
  Future<void> writeCatalog(String addonId, String jsonStr) async {
    catalogs[addonId] = jsonStr;
  }

  @override
  Future<void> deleteCatalog(String addonId) async {
    catalogs.remove(addonId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
        'FakeAddonStore does not respond to ${invocation.memberName}.',
      );
}
