import 'package:retro_toolbox/services/save_sync/drive_api.dart';
import 'package:retro_toolbox/services/save_sync/hub_backend.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';

/// A hub in the `Retro Toolbox Saves` folder of one Google account's My Drive.
///
/// Drive allows two folders with the same name in one parent, so two devices that create
/// `units/<recipe>` at the same moment get two. A path resolves to every same-name folder:
/// reads take the union, writes go to the oldest (createdTime, then id). A name stored twice
/// reads as its oldest copy, and delete trashes every copy.
///
/// The app makes one of these per refresh. [list] always asks Drive; folder ids and the last
/// listing of each folder are kept for the object's life, so reading the gens a listing just
/// showed costs no second listing.
class DriveBackend implements HubBackend {
  DriveBackend(this.accountId, this.api);

  static const folderName = 'Retro Toolbox Saves';

  /// Google's account id: each account is its own hub.
  final String accountId;
  final DriveApi api;

  /// Hub path ('' is the hub itself) to its folder ids, oldest first. Only paths that exist.
  final _dirs = <String, List<String>>{};

  /// Folder id to its last listing, kept up to date with this object's own changes.
  final _seen = <String, List<DriveFile>>{};

  @override
  String get id => 'drive:$accountId';

  static void _check(String path) {
    if (!PathGuard.isSafeRelative(path)) throw ArgumentError.value(path, 'path');
  }

  static (String, String) _split(String path) {
    final cut = path.lastIndexOf('/');
    return (cut < 0 ? '' : path.substring(0, cut), path.substring(cut + 1));
  }

  Future<List<DriveFile>> _listing(String folder, {bool fresh = false}) async {
    final seen = fresh ? null : _seen[folder];
    return seen ?? (_seen[folder] = await api.children(folder));
  }

  /// Items named [name] in [folders], oldest first. When the remembered listings have none, the
  /// folders listed from memory are listed again before the answer is "none".
  Future<List<DriveFile>> _find(List<String> folders, String name, {required bool folder}) async {
    bool match(DriveFile f) => f.isFolder == folder && f.name == name;
    final remembered = folders.where(_seen.containsKey).toList();
    var hits = [for (final f in folders) ...(await _listing(f)).where(match)];
    if (hits.isEmpty) hits = [for (final f in remembered) ...(await _listing(f, fresh: true)).where(match)];
    return hits..sort(oldestFirst);
  }

  /// The folders at [dir], oldest first; empty when it does not exist. With [create] the missing
  /// folders are made, each in the oldest of its parents, and the result is never empty.
  Future<List<String>> _folders(String dir, {bool create = false}) async {
    final known = _dirs[dir];
    if (known != null) return known;
    final (parent, name) = dir.isEmpty ? ('', folderName) : _split(dir);
    final parents = dir.isEmpty ? const ['root'] : await _folders(parent, create: create);
    if (parents.isEmpty) return const [];
    final found = await _find(parents, name, folder: true);
    if (found.isNotEmpty) return _dirs[dir] = [for (final f in found) f.id];
    if (!create) return const [];
    final made = await api.createFolder(name, parents.first);
    _seen[parents.first]?.add(made);
    _seen[made.id] = [];
    return _dirs[dir] = [made.id];
  }

  @override
  Future<List<HubEntry>> list(String dir) async {
    if (dir.isNotEmpty) _check(dir);
    final entries = <String, HubEntry>{};
    for (final folder in await _folders(dir)) {
      for (final f in await _listing(folder, fresh: true)) {
        // Docs, shortcuts and other Google types have no bytes to sync.
        if (f.name.startsWith('.') || (!f.isFolder && f.mimeType.startsWith('application/vnd.google-apps.'))) continue;
        entries.putIfAbsent('${f.isFolder}/${f.name}', () => HubEntry(f.name, isDir: f.isFolder, size: f.size));
      }
    }
    return entries.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Future<List<int>> read(String path) async {
    _check(path);
    final (dir, name) = _split(path);
    final files = await _find(await _folders(dir), name, folder: false);
    if (files.isEmpty) throw DriveError(404, 'notFound', 'Not in the hub: $path');
    return api.download(files.first.id);
  }

  @override
  Future<void> write(String path, List<int> bytes) async {
    _check(path);
    final (dir, name) = _split(path);
    final folders = await _folders(dir, create: true);
    final existing = await _find(folders, name, folder: false);
    if (existing.isNotEmpty) {
      await api.updateFile(existing.first.id, name, bytes);
      return;
    }
    final f = await api.createFile(name, folders.first, bytes);
    _seen[folders.first]?.add(f);
  }

  @override
  Future<void> delete(String path) async {
    _check(path);
    final (dir, name) = _split(path);
    for (final f in await _find(await _folders(dir), name, folder: false)) {
      await api.trash(f.id);
      for (final l in _seen.values) {
        l.removeWhere((e) => e.id == f.id);
      }
    }
  }
}
