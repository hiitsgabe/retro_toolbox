import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/glob.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/units.dart';

/// Which package and location a recipe uses on this device. Stored locally, never synced.
class Binding {
  const Binding({required this.recipe, required this.package, required this.area, required this.root, this.mode = 'sync'});

  final String recipe;
  final String package;
  final Area area;
  final String root;

  /// `sync`, or `backup` for games with their own cloud (push only).
  final String mode;

  String dir(DevicePaths paths) => '${paths.area(area, package)}/$root';

  Map<String, dynamic> toJson() => {'recipe': recipe, 'package': package, 'area': area.name, 'root': root, 'mode': mode};

  static Binding fromJson(Map<String, dynamic> j) => Binding(
        recipe: j['recipe'] as String,
        package: j['package'] as String,
        area: Area.values.byName(j['area'] as String),
        root: j['root'] as String,
        mode: (j['mode'] as String?) ?? 'sync',
      );
}

sealed class BindResult {
  const BindResult();
}

class Bound extends BindResult {
  const Bound(this.binding);

  final Binding binding;
}

/// Saves found in one place, but the recipe is not verified: show [files] and ask.
class NeedsConfirm extends BindResult {
  const NeedsConfirm(this.binding, this.files);

  final Binding binding;
  final List<String> files;
}

class NotInstalled extends BindResult {
  const NotInstalled();
}

class NeedsRoot extends BindResult {
  const NeedsRoot(this.binding, {this.reason = outOfReach});

  /// The save folder lives where only root goes on any device.
  static const outOfReach = 'this game keeps its saves where only root reaches';

  /// The folder is right there, but this device keeps it private to the game.
  /// Same app, same path, other handheld: readable. It comes down to the
  /// group and the setgid bit on the folders above it, which nothing short of
  /// root can put back.
  static const refused = 'this device keeps that folder private to the game';

  final Binding binding;
  final String reason;
}

/// The game has not created its save folder yet: open it once.
class FolderMissing extends BindResult {
  const FolderMissing(this.binding);

  final Binding binding;
}

class NeedsDiscovery extends BindResult {
  const NeedsDiscovery(this.reason);

  final String reason;
}

class RecipeBinder {
  RecipeBinder(this.fs, this.paths, {required this.privilege});

  final GameFs fs;
  final DevicePaths paths;
  final Privilege privilege;

  Future<BindResult> bind(Recipe r) async {
    final installed = [
      for (final pkg in r.packages)
        if (await fs.installed(pkg)) pkg,
    ];
    if (installed.isEmpty) return const NotInstalled();
    final mode = r.nativeCloud?.defaultMode ?? 'sync';
    final declared = [
      for (final pkg in installed)
        for (final l in r.locations) Binding(recipe: r.id, package: pkg, area: l.area, root: l.root, mode: mode),
    ];
    // A root may carry one patterned segment, standing for a directory the
    // install named itself. It is resolved here and nowhere else: a Binding
    // is local and never travels, so every device looks the pattern up
    // against its own disk, and everything downstream — unit keys, hub
    // directories, stored bases — stays the plain path it always was.
    final candidates = <Binding>[];
    for (final b in declared) {
      candidates.addAll(await _resolveRoot(b));
    }
    bool reachable(Binding b) => b.area == Area.androidData || privilege == Privilege.root;

    if (candidates.length == 1) {
      final b = candidates.single;
      if (!reachable(b)) return NeedsRoot(b);
      if (!await fs.isDir(b.dir(paths))) return FolderMissing(b);
      final files = await _unitFilesOrRefused(r, b.dir(paths));
      if (files == null) return NeedsRoot(b, reason: NeedsRoot.refused);
      return r.status == RecipeStatus.verified || files.isEmpty ? Bound(b) : NeedsConfirm(b, files);
    }

    final withSaves = <(Binding, List<String>)>[];
    final refused = <Binding>[];
    for (final b in candidates.where(reachable)) {
      if (!await fs.isDir(b.dir(paths))) continue;
      final files = await _unitFilesOrRefused(r, b.dir(paths));
      if (files == null) {
        refused.add(b);
      } else if (files.isNotEmpty) {
        withSaves.add((b, files));
      }
    }
    if (withSaves.length == 1) {
      final (b, files) = withSaves.single;
      return r.status == RecipeStatus.verified ? Bound(b) : NeedsConfirm(b, files);
    }
    if (withSaves.length > 1) return const NeedsDiscovery('saves found in more than one place');
    // Nothing has saves yet. A device that has never played the game is the
    // reason to sync in the first place, so bind it anyway rather than giving
    // up: the single place that exists, or, when the game has not made one
    // yet, the first place it would use.
    final open = candidates.where(reachable).toList();
    if (open.isEmpty) return NeedsRoot(candidates.first);
    if (refused.isNotEmpty) return NeedsRoot(refused.first, reason: NeedsRoot.refused);
    final existing = <Binding>[];
    for (final b in open) {
      if (await fs.isDir(b.dir(paths))) existing.add(b);
    }
    if (existing.length == 1) return Bound(existing.single);
    if (existing.isEmpty) return FolderMissing(open.first);
    return const NeedsDiscovery('the save folder could be in more than one place');
  }

  /// Expands the one patterned segment, if there is one, against this device.
  /// A root with no pattern comes back as it is. Several matches all come
  /// back, so the caller decides between them the same way it decides between
  /// two declared locations. No match keeps the literal root, which reads as
  /// a folder that is not there — "open the app once" — rather than as
  /// nothing at all.
  Future<List<Binding>> _resolveRoot(Binding b) async {
    final segs = b.root.split('/');
    final i = segs.indexWhere((x) => x.contains('*') || x.contains('?') || x.contains('['));
    if (i < 0) return [b];
    final base = [paths.area(b.area, b.package), ...segs.take(i)].join('/');
    final glob = Glob(segs[i]);
    final rest = segs.skip(i + 1);
    final out = <Binding>[];
    for (final e in await fs.listDir(base)) {
      if (!e.isDir || !glob.matches(e.name)) continue;
      out.add(Binding(recipe: b.recipe, package: b.package, area: b.area, root: [...segs.take(i), e.name, ...rest].join('/'), mode: b.mode));
    }
    out.sort((x, y) => x.root.compareTo(y.root));
    return out.isEmpty ? [b] : out;
  }

  /// The unit's files, or null when the folder is there and this device is
  /// refused a look inside. Only a refusal reads as null: anything else is a
  /// real failure and still throws.
  Future<List<String>?> _unitFilesOrRefused(Recipe r, String dir) async {
    try {
      return await _unitFiles(r, dir);
    } on GameFsError catch (e) {
      if (_refused(e.message)) return null;
      rethrow;
    }
  }

  static bool _refused(String message) => message.contains('Permission denied') || message.contains('Operation not permitted');

  Future<List<String>> _unitFiles(Recipe r, String dir) async {
    final rels = [for (final e in await fs.listFiles(dir)) p.posix.relative(e.path, from: dir)];
    return [for (final g in groupUnits(r, rels).values) ...g];
  }
}
