import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/binding.dart';
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/engine.dart';
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

/// A handheld whose save folder is right there but refuses a look inside:
/// the folder was made under a parent that had lost its shared group, so the
/// shell user is not in the group that may read it.
class RefusingShell extends PmShell {
  RefusingShell(super.installed);

  @override
  Future<ShellResult> run(List<String> argv) async {
    if (argv.first == 'find') return const ShellResult(1, '', 'find: /sdcard/Android/data/x/files/Saves: Permission denied');
    return super.run(argv);
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

  // The reason schema 2 exists: some apps bury their saves under a directory
  // they named themselves at install time, so the recipe cannot spell it out.
  group('a root with one patterned segment', () {
    Recipe patterned({String status = 'verified'}) => Recipe.parse({
          'schema': 2,
          'id': 'patterned',
          'name': 'Alpha Title',
          'status': status,
          'packages': ['com.example.alpha'],
          'locations': [
            {'area': 'androidData', 'root': 'files/save/0/*[!0]*'},
          ],
          'unit': 'folder',
          'include': ['*/**'],
        });

    String area() => paths.area(Area.androidData, 'com.example.alpha');

    test('resolves to the directory this install actually made', () async {
      Directory(p.join(area(), 'files/save/0/A1B2C3')).createSync(recursive: true);
      final res = await binder(patterned(), {'com.example.alpha'}).bind(patterned());
      expect(res, isA<Bound>());
      expect((res as Bound).binding.root, 'files/save/0/A1B2C3');
    });

    test('a directory the pattern excludes is not picked', () async {
      Directory(p.join(area(), 'files/save/0/00000')).createSync(recursive: true);
      final res = await binder(patterned(), {'com.example.alpha'}).bind(patterned());
      // Only the excluded one exists, so nothing resolved and the literal root
      // stands — which reads as "open the app once", not as a silent match.
      expect(res, isA<FolderMissing>());
    });

    test('two matching directories are a choice, not a guess', () async {
      for (final d in ['A1B2C3', 'D4E5F6']) {
        Directory(p.join(area(), 'files/save/0/$d')).createSync(recursive: true);
      }
      final res = await binder(patterned(), {'com.example.alpha'}).bind(patterned());
      expect(res, isA<NeedsDiscovery>());
      // Carried out, not just counted: the owner is shown the places rather
      // than told that several exist.
      expect(
        [for (final (b, _) in (res as NeedsDiscovery).places) b.root],
        ['files/save/0/A1B2C3', 'files/save/0/D4E5F6'],
      );
    });

    test('nothing there at all still asks for the app to be opened', () async {
      Directory(p.join(area(), 'files/save/0')).createSync(recursive: true);
      expect(await binder(patterned(), {'com.example.alpha'}).bind(patterned()), isA<FolderMissing>());
    });
  });

  test('not installed', () async {
    expect(await binder(bundled('stardew-valley'), {}).bind(bundled('stardew-valley')), isA<NotInstalled>());
  });

  test('one location: missing folder asks to open the game once', () async {
    final r = bundled('stardew-valley');
    expect(await binder(r, {'com.chucklefish.stardewvalley'}).bind(r), isA<FolderMissing>());
  });

  // The folder is there, the app is installed, and the shell is still refused.
  // That reads as "needs root", not as a shell error pasted into the card.
  test('one location the device may not look inside: needs root, with the reason', () async {
    final r = bundled('stardew-valley');
    Directory(p.join(paths.area(Area.androidData, 'com.chucklefish.stardewvalley'), 'files/Saves')).createSync(recursive: true);
    final roots = [for (final a in Area.values) paths.area(a, 'com.chucklefish.stardewvalley')];
    final refusing = RecipeBinder(ShellGameFs(RefusingShell({'com.chucklefish.stardewvalley'}), PathGuard(roots)), paths, privilege: Privilege.shell);
    final res = await refusing.bind(r);
    expect(res, isA<NeedsRoot>());
    expect((res as NeedsRoot).reason, NeedsRoot.refused);
    expect(bindLabel(res), isNot(contains('find')));
  });

  test('one location, verified, empty folder: bound (a fresh device can pull)', () async {
    final r = bundled('stardew-valley');
    final saves = Directory(p.join(paths.area(Area.androidData, 'com.chucklefish.stardewvalley'), 'files/Saves'))..createSync(recursive: true);
    final b = (await binder(r, {'com.chucklefish.stardewvalley'}).bind(r)) as Bound;
    expect(b.binding.dir(paths), endsWith('Android/data/com.chucklefish.stardewvalley/files/Saves'));
    expect(b.binding.mode, 'sync');
    // Verified, so saves already there bind without asking (a draft asks, below).
    File(p.join(saves.path, 'Farm_1/Farm_1'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    expect(await binder(r, {'com.chucklefish.stardewvalley'}).bind(r), isA<Bound>());
  });

  test('one location, not verified: binds only when empty, else asks to confirm', () async {
    Recipe variant(String id, Map<String, dynamic> changes) => Recipe.parse({...bundled(id).raw, ...changes});
    final r = variant('stardew-valley', {'status': 'draft'});
    final saves = Directory(p.join(paths.area(Area.androidData, 'com.chucklefish.stardewvalley'), 'files/Saves'))..createSync(recursive: true);
    final b = binder(r, {'com.chucklefish.stardewvalley'});
    expect(await b.bind(r), isA<Bound>());
    File(p.join(saves.path, 'Farm_1/Farm_1'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final res = await b.bind(r);
    expect(res, isA<NeedsConfirm>());
    expect((res as NeedsConfirm).files, ['Farm_1/Farm_1']);
  });

  test('two locations: the one with saves wins; a draft asks to confirm', () async {
    final r = bundled('sea-of-stars');
    final ext = p.join(paths.area(Area.androidData, 'com.playdigious.seaofstars'), 'files');
    File(p.join(ext, 'SOS_SaveSlot0.sos'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    Directory(p.join(paths.area(Area.internal, 'com.playdigious.seaofstars'), 'files')).createSync(recursive: true);
    final res = (await binder(r, {'com.playdigious.seaofstars'}, privilege: Privilege.root).bind(r)) as NeedsConfirm;
    expect(res.binding.area, Area.androidData);
    expect(res.binding.mode, 'backup');
    expect(res.files, ['SOS_SaveSlot0.sos']);
  });

  test('two locations: saves only in the second place bind that place, not the first', () async {
    final r = bundled('sea-of-stars');
    Directory(p.join(paths.area(Area.androidData, 'com.playdigious.seaofstars'), 'files')).createSync(recursive: true);
    File(p.join(paths.area(Area.internal, 'com.playdigious.seaofstars'), 'files', 'SOS_SaveSlot0.sos'))
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    final res = await binder(r, {'com.playdigious.seaofstars'}, privilege: Privilege.root).bind(r);
    expect(res, isA<NeedsConfirm>());
    expect((res as NeedsConfirm).binding.area, Area.internal);
  });

  test('two locations, saves in both: discovery', () async {
    final r = bundled('sea-of-stars');
    for (final a in [Area.androidData, Area.internal]) {
      File(p.join(paths.area(a, 'com.playdigious.seaofstars'), 'files', 'SOS_SaveSlot0.sos'))
        ..createSync(recursive: true)
        ..writeAsStringSync('x');
    }
    expect(await binder(r, {'com.playdigious.seaofstars'}, privilege: Privilege.root).bind(r), isA<NeedsDiscovery>());
  });

  // A handheld that has the game but has never played it is the whole reason
  // to sync, so it has to end up bindable rather than stuck on discovery.
  test('two locations, no saves and no folder: open the game once', () async {
    final r = bundled('sea-of-stars');
    final res = await binder(r, {'com.playdigious.seaofstars'}).bind(r);
    expect(res, isA<FolderMissing>());
    expect((res as FolderMissing).binding.area, Area.androidData);
  });

  test('two locations, no saves but one reachable folder: bound, so it can pull', () async {
    final r = bundled('sea-of-stars');
    Directory(p.join(paths.area(Area.androidData, 'com.playdigious.seaofstars'), 'files')).createSync(recursive: true);
    final res = await binder(r, {'com.playdigious.seaofstars'}).bind(r);
    expect(res, isA<Bound>());
    expect((res as Bound).binding.area, Area.androidData);
  });

  test('binding JSON round-trip', () {
    const b = Binding(recipe: 'sea-of-stars', package: 'com.playdigious.seaofstars', area: Area.internal, root: 'files', mode: 'backup');
    final c = Binding.fromJson(b.toJson());
    expect(c.area, Area.internal);
    expect(c.mode, 'backup');
    expect(c.dir(const DevicePaths()), '/data/data/com.playdigious.seaofstars/files');
  });
}
