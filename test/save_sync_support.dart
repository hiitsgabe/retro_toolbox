import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/services/save_sync/game_fs.dart';
import 'package:retro_toolbox/services/save_sync/path_guard.dart';
import 'package:retro_toolbox/services/save_sync/privileged_shell.dart';
import 'package:retro_toolbox/services/save_sync/recipe.dart';
import 'package:retro_toolbox/services/save_sync/recipe_store.dart';

const stardewPkg = 'com.chucklefish.stardewvalley';

Recipe bundledRecipe(String id) => parseRecipeFiles({'$id.json': File('save_recipes/$id.json').readAsStringSync()}).recipes.single;

/// Real file commands on Linux, faked Android ones (pidof, dumpsys, pm), and
/// optional injected failures on atomic replaces (0-based): the Nth only, or
/// every one from the Nth on. [startGameAfterReplaces] makes pidof report the
/// game running once that many atomic replaces have happened. [afterRun] sees
/// the argv of every real command that succeeded, after it ran.
class TestShell implements PrivilegedShell {
  TestShell({this.privilege = Privilege.shell});

  @override
  final Privilege privilege;
  final _real = ProcessShell();
  bool gameRunning = false;
  /// Null makes `dumpsys` fail.
  String? version = '1.6.15.2';
  Set<String> installed = {stardewPkg};
  int failReplaceAt = -1;
  int failReplaceFrom = -1;
  int startGameAfterReplaces = -1;
  int _replaces = 0;
  /// Runs the real `mv` onto a path ending in this, then reports it unreachable once (the reply is lost).
  String? loseReplyOnMvTo;
  void Function(List<String> argv)? afterRun;

  /// Atomic replaces tried so far.
  int get replaces => _replaces;

  @override
  Future<ShellResult> run(List<String> argv) async {
    switch (argv.first) {
      case 'pidof':
        final running = gameRunning || (startGameAfterReplaces >= 0 && _replaces >= startGameAfterReplaces);
        return ShellResult(running ? 0 : 1, running ? '42\n' : '', '');
      case 'dumpsys':
        return version == null ? const ShellResult(1, '', 'dumpsys failed') : ShellResult(0, '    versionName=$version\n', '');
      case 'pm':
        return installed.contains(argv[2]) ? ShellResult(0, 'package:/data/app/${argv[2]}/base.apk\n', '') : const ShellResult(1, '', '');
      case 'mv' when argv.length == 4 && p.basename(argv[2]).startsWith('.rtsync-'):
        final n = _replaces++;
        if (n == failReplaceAt || (failReplaceFrom >= 0 && n >= failReplaceFrom)) return const ShellResult(1, '', 'injected failure');
    }
    final r = await _real.run(argv);
    if (r.ok) afterRun?.call(argv);
    if (r.ok && argv.first == 'mv' && loseReplyOnMvTo != null && argv.last.endsWith(loseReplyOnMvTo!)) {
      loseReplyOnMvTo = null; // once
      return const ShellResult(ShellResult.unreachable, '', 'reply lost');
    }
    return r;
  }
}

/// One simulated handheld: its own sdcard and data folders under [root].
class TestDevice {
  TestDevice(String root, this.name, {Privilege privilege = Privilege.shell})
      : paths = DevicePaths(sdcard: p.join(root, 'sdcard'), data: p.join(root, 'data')),
        shell = TestShell(privilege: privilege);

  final String name;
  final DevicePaths paths;
  final TestShell shell;

  String get saves => p.join(paths.area(Area.androidData, stardewPkg), 'files', 'Saves');

  GameFs fsFor(Recipe r) => ShellGameFs(shell, PathGuard([for (final pkg in r.packages) for (final a in Area.values) paths.area(a, pkg), paths.saveSync]));

  void makeSavesFolder() => Directory(saves).createSync(recursive: true);

  void writeFarm(String farm, String body, {String version = '1.6.15'}) {
    File(p.join(saves, farm, farm))
      ..createSync(recursive: true)
      ..writeAsStringSync('<?xml version="1.0"?><SaveGame>$body</SaveGame>');
    File(p.join(saves, farm, 'SaveGameInfo')).writeAsStringSync('<Farmer><gameVersion>$version</gameVersion></Farmer>');
  }

  String farm(String farm) => File(p.join(saves, farm, farm)).readAsStringSync();

  bool has(String rel) => File(p.join(saves, rel)).existsSync();
}
