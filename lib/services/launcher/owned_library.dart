import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/library_snapshot_model.dart';
import 'package:retro_toolbox/services/launcher/launch_target.dart';
import 'package:retro_toolbox/services/m3u_service.dart';
import 'package:retro_toolbox/utils/title_metadata_parser.dart';

/// What [OwnedLibrary.scan] reads: a console, its library dir, the formats
/// that are its own there (see `ownFormats`), the dir's snapshot and the
/// console's catalog games. [OwnedScan.folders] false: a folder is never a
/// game (Switch keeps updates and DLC in folders). [OwnedScan.skip]: folders
/// that are never a game whatever it says, this app's own updates and mods.
typedef OwnedScan = ({String consoleId, String dir, Set<String> formats, LibrarySnapshot snapshot, List<Game> catalog, bool folders, Set<String> skip});

/// The url of a game built from a loose file: the console and the real name
/// of its lead file or folder, so its filename and gameId stay the same on
/// every scan.
String localGameUrl(String consoleId, String name) => '${Game.localScheme}://${Uri.encodeComponent(consoleId)}/${Uri.encodeComponent(name)}';

/// The games of a console's library dir that no catalog game claims: a loose
/// file, a cue or gdi with the files it names, a disc set, or a folder with a
/// game one level down.
class OwnedLibrary {
  const OwnedLibrary({this.games = const [], this.paths = const {}, this.unreadable = false});

  static const empty = OwnedLibrary();

  /// One synthetic game per loose entry, `local://` urls.
  final List<Game> games;

  /// Each loose game's files on disk, absolute and sorted, by gameId: the
  /// real names, which `Game.sanitizeForFat` may have changed in the gameId.
  final Map<String, List<String>> paths;

  /// The dir exists and could not be listed: owning nothing is not the
  /// answer then.
  final bool unreadable;

  static const _sheets = {'.cue', '.gdi'};

  /// The rules `hasGamesOnDisk` applies (a root file in [OwnedScan.formats],
  /// or a root folder with one directly inside), less every file a present
  /// catalog game has. An entry with any such file is the catalog game's.
  static Future<OwnedLibrary> scan(OwnedScan s) async {
    final (:consoleId, :dir, :formats, :snapshot, :catalog, :folders, :skip) = s;
    if (dir.isEmpty || formats.isEmpty) return empty;
    final List<FileSystemEntity> entries;
    try {
      if (!await Directory(dir).exists()) return empty;
      entries = await Directory(dir).list(followLinks: false).toList();
    } on FileSystemException {
      return const OwnedLibrary(unreadable: true);
    }
    bool game(String path) => formats.contains(p.extension(path).toLowerCase());

    final rootFiles = <String>{for (final e in entries) if (e is File) e.path};
    final gameFolders = <String, List<String>>{};
    for (final d in entries.whereType<Directory>()) {
      if (!folders || skip.contains(p.normalize(d.path))) continue;
      try {
        final files = [for (final f in await d.list(followLinks: false).toList()) if (f is File) f.path]..sort();
        if (files.any(game)) gameFolders[d.path] = files;
      } on FileSystemException {
        // One unreadable folder does not hide the rest, as in hasGamesOnDisk.
      }
    }

    // Groups of root files, merged as they turn out to be one game: same
    // base name, a sheet and the tracks it names, the discs of one set.
    final members = <String, Set<String>>{};
    final keyOf = <String, String>{};
    void add(String path, String key) {
      if (keyOf.containsKey(path)) return;
      keyOf[path] = key;
      (members[key] ??= {}).add(path);
    }

    void merge(String into, String from) {
      final a = keyOf[into]!, b = keyOf[from]!;
      if (a == b) return;
      for (final m in members.remove(b)!) {
        keyOf[m] = a;
        members[a]!.add(m);
      }
    }

    final candidates = [for (final f in rootFiles) if (game(f)) f]..sort();
    for (final f in candidates) {
      add(f, p.basenameWithoutExtension(f));
    }
    for (final sheet in candidates.where((f) => _sheets.contains(p.extension(f).toLowerCase()))) {
      for (final name in _sheetFiles(sheet)) {
        final track = p.join(dir, name);
        if (!rootFiles.contains(track)) continue;
        add(track, keyOf[sheet]!);
        merge(sheet, track);
      }
    }
    final setTitle = <String, String>{}, setLead = <String, String>{};
    for (final set in M3uService.detectDiscSets([for (final f in candidates) p.basename(f)], extensions: launchDiscExtensions)) {
      final discs = [for (final d in set.discs) p.join(dir, d)];
      for (final d in discs.skip(1)) {
        merge(discs.first, d);
      }
      final m3u = p.join(dir, '${set.base}.m3u');
      if (rootFiles.contains(m3u)) {
        add(m3u, keyOf[discs.first]!);
        merge(discs.first, m3u);
      }
      setTitle[keyOf[discs.first]!] = set.base;
      setLead[keyOf[discs.first]!] = discs.first;
    }
    // A folder named as a group's base is that game extracted beside it.
    final looseFolders = <String, List<String>>{};
    for (final e in gameFolders.entries) {
      final key = p.basename(e.key);
      if (members.containsKey(key)) {
        members[key]!.addAll(e.value);
      } else {
        looseFolders[e.key] = e.value;
      }
    }

    final claimed = _claimed(dir, snapshot, catalog);
    bool mine(Iterable<String> files) => !files.any((f) => claimed.contains(p.normalize(f)));
    final catalogById = {for (final g in catalog) g.gameId: g};
    final games = <Game>[];
    final paths = <String, List<String>>{};
    Future<void> entry({required String name, required String title, required List<String> files}) async {
      final game = Game(
        title: title,
        url: localGameUrl(consoleId, name),
        size: await _size(files),
        consoleId: consoleId,
        metadata: TitleMetadataParser.parseRomTitle(title),
      );
      // Two real names sanitizeForFat turns into one: the first one keeps the
      // id. A catalog game of that id keeps it only while it is on disk: one
      // the snapshot does not know yet would leave this file nowhere.
      final clash = catalogById[game.gameId];
      if ((clash != null && snapshot.statusFor(clash.filename) != LibraryPresence.none) || paths.containsKey(game.gameId)) return;
      games.add(game);
      paths[game.gameId] = [...files]..sort();
    }

    for (final e in members.entries) {
      if (!mine(e.value)) continue;
      final lead = setLead[e.key] ?? _lead(e.value);
      await entry(name: p.basename(lead), title: setTitle[e.key] ?? p.basenameWithoutExtension(lead), files: e.value.toList());
    }
    for (final e in looseFolders.entries) {
      if (!mine([e.key, ...e.value])) continue;
      await entry(name: p.basename(e.key), title: p.basename(e.key), files: e.value);
    }
    games.sort((a, b) => a.title.compareTo(b.title));
    return OwnedLibrary(games: games, paths: paths);
  }

  /// Every path a present catalog game has: its file and what the snapshot
  /// relates to it (its folder, its root siblings).
  static Set<String> _claimed(String dir, LibrarySnapshot snapshot, List<Game> catalog) {
    final present = snapshot.presentBaseNames();
    final out = <String>{};
    for (final g in catalog) {
      final name = g.filename;
      if (!present.contains(p.basenameWithoutExtension(name)) || snapshot.statusFor(name) == LibraryPresence.none) continue;
      out.add(p.normalize(p.join(dir, name)));
      for (final f in snapshot.relatedFilesFor(name)) {
        out.add(p.normalize(p.isAbsolute(f) ? f : p.join(dir, f)));
      }
    }
    return out;
  }

  /// The file a group is named by: a playlist, then a sheet, then a disc
  /// image, then anything else, by name within each.
  static String _lead(Iterable<String> files) {
    int rank(String f) => switch (p.extension(f).toLowerCase()) {
          '.m3u' => 0,
          '.cue' || '.gdi' => 1,
          final e when launchDiscExtensions.contains(e) => 2,
          _ => 3,
        };
    return (files.toList()..sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.compareTo(b))).first;
  }

  /// The file names a cue (`FILE "x.bin" BINARY`) or a gdi (`1 0 4 2352 "x.bin" 0`) names.
  static List<String> _sheetFiles(String sheet) {
    final cue = p.extension(sheet).toLowerCase() == '.cue';
    final line = cue ? RegExp(r'^\s*FILE\s+(?:"([^"]+)"|(\S+))', caseSensitive: false) : RegExp(r'^\s*\d+\s+\d+\s+\d+\s+\d+\s+(?:"([^"]+)"|(\S+))');
    try {
      return [
        for (final l in File(sheet).readAsLinesSync())
          if (line.firstMatch(l) case final m?) p.basename(m.group(1) ?? m.group(2)!),
      ];
    } on Exception {
      // Unreadable, or not text: the sheet joins nothing, its tracks stay
      // entries of their own.
      return const [];
    }
  }

  /// A stat that fails reads as size -1: that file counts 0.
  static Future<int> _size(List<String> files) async {
    var total = 0;
    for (final f in files) {
      final size = (await File(f).stat()).size;
      if (size > 0) total += size;
    }
    return total;
  }
}
