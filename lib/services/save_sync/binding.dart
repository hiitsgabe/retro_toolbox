import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
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
  const NeedsRoot(this.binding);

  final Binding binding;
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
    final candidates = [
      for (final pkg in installed)
        for (final l in r.locations) Binding(recipe: r.id, package: pkg, area: l.area, root: l.root, mode: mode),
    ];
    bool reachable(Binding b) => b.area == Area.androidData || privilege == Privilege.root;

    if (candidates.length == 1) {
      final b = candidates.single;
      if (!reachable(b)) return NeedsRoot(b);
      if (!await fs.isDir(b.dir(paths))) return FolderMissing(b);
      final files = await _unitFiles(r, b.dir(paths));
      return r.status == RecipeStatus.verified || files.isEmpty ? Bound(b) : NeedsConfirm(b, files);
    }

    final withSaves = <(Binding, List<String>)>[];
    for (final b in candidates.where(reachable)) {
      if (!await fs.isDir(b.dir(paths))) continue;
      final files = await _unitFiles(r, b.dir(paths));
      if (files.isNotEmpty) withSaves.add((b, files));
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
    final existing = <Binding>[];
    for (final b in open) {
      if (await fs.isDir(b.dir(paths))) existing.add(b);
    }
    if (existing.length == 1) return Bound(existing.single);
    if (existing.isEmpty) return FolderMissing(open.first);
    return const NeedsDiscovery('the save folder could be in more than one place');
  }

  Future<List<String>> _unitFiles(Recipe r, String dir) async {
    final rels = [for (final e in await fs.listFiles(dir)) p.posix.relative(e.path, from: dir)];
    return [for (final g in groupUnits(r, rels).values) ...g];
  }
}
