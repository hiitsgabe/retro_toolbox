import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';

class PmShell implements PrivilegedShell {
  PmShell(this.installed, {this.privilege = Privilege.shell});

  final Set<String> installed;
  @override
  final Privilege privilege;
  final _real = ProcessShell();

  @override
  Future<ShellResult> run(List<String> argv) async {
    if (argv.first == 'pm') return installed.contains(argv[2]) ? ShellResult(0, 'package:/x/${argv[2]}.apk\n', '') : const ShellResult(1, '', '');
    return _real.run(argv);
  }
}

Recipe bundled(String id) => parseRecipeFiles({'$id.json': File('save_recipes/$id.json').readAsStringSync()}).recipes.single;

void main() {
  late Directory tmp;
  late DevicePaths paths;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('binding');
    paths = DevicePaths(sdcard: p.join(tmp.path, 'sdcard'), data: p.join(tmp.path, 'data'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  RecipeBinder binder(Recipe r, Set<String> installed, {Privilege privilege = Privilege.shell}) {
    final roots = [for (final pkg in r.packages) for (final a in Area.values) paths.area(a, pkg)];
    return RecipeBinder(ShellGameFs(PmShell(installed, privilege: privilege), PathGuard(roots)), paths, privilege: privilege);
  }

  test('not installed', () async {
    expect(await binder(bundled('stardew-valley'), {}).bind(bundled('stardew-valley')), isA<NotInstalled>());
  });

  test('one location: missing folder asks to open the game once', () async {
    final r = bundled('stardew-valley');
    expect(await binder(r, {'com.chucklefish.stardewvalley'}).bind(r), isA<FolderMissing>());
  });

  test('one location, verified, empty folder: bound (a fresh device can pull)', () async {
    final r = bundled('stardew-valley');
    Directory(p.join(paths.area(Area.androidData, 'com.chucklefish.stardewvalley'), 'files/Saves')).createSync(recursive: true);
    final b = (await binder(r, {'com.chucklefish.stardewvalley'}).bind(r)) as Bound;
    expect(b.binding.dir(paths), endsWith('Android/data/com.chucklefish.stardewvalley/files/Saves'));
    expect(b.binding.mode, 'sync');
  });

  test('two locations: the one with saves wins; a draft asks to confirm', () async {
    final r = bundled('sea-of-stars');
    final ext = p.join(paths.area(Area.androidData, 'com.playdigious.seaofstars'), 'files');
    File(p.join(ext, 'SOS_SaveSlot0.sos'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final res = (await binder(r, {'com.playdigious.seaofstars'}).bind(r)) as NeedsConfirm;
    expect(res.binding.area, Area.androidData);
    expect(res.binding.mode, 'backup');
    expect(res.files, ['SOS_SaveSlot0.sos']);
  });

  test('two locations, no saves anywhere: discovery', () async {
    final r = bundled('sea-of-stars');
    expect(await binder(r, {'com.playdigious.seaofstars'}).bind(r), isA<NeedsDiscovery>());
  });

  test('binding JSON round-trip', () {
    const b = Binding(recipe: 'sea-of-stars', package: 'com.playdigious.seaofstars', area: Area.internal, root: 'files', mode: 'backup');
    final c = Binding.fromJson(b.toJson());
    expect(c.area, Area.internal);
    expect(c.mode, 'backup');
    expect(c.dir(const DevicePaths()), '/data/data/com.playdigious.seaofstars/files');
  });
}
