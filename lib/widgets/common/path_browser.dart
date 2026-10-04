import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/common/hammer_loader.dart';

/// Plain `dart:io` filesystem browser.
///
/// Used on Android in place of the SAF pickers. `file_picker` streams the whole
/// selection into the app cache before it returns a path (see
/// `FileUtils.openFileStream` in the plugin), so picking a multi-GB ROM either
/// runs for minutes or dies on ENOSPC; either way the delegate keeps its
/// `pendingResult` set and every later pick fails with `already_active`. The
/// app already requests MANAGE_EXTERNAL_STORAGE at startup, so browsing real
/// paths here costs nothing and hands the Python side a path it can open.
class PathBrowser extends StatefulWidget {
  const PathBrowser({
    super.key,
    required this.title,
    required this.initialDir,
    this.allowedExtensions,
    this.selectDirectory = false,
  });

  final String title;
  final String initialDir;

  /// Lowercase, no leading dot. Null shows every file.
  final List<String>? allowedExtensions;

  /// Pick a folder instead of a file: files are hidden and a "Use this folder"
  /// button returns the current folder.
  final bool selectDirectory;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String initialDir,
    List<String>? allowedExtensions,
    bool selectDirectory = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => PathBrowser(
        title: title,
        initialDir: initialDir,
        allowedExtensions: allowedExtensions,
        selectDirectory: selectDirectory,
      ),
    );
  }

  @override
  State<PathBrowser> createState() => _PathBrowserState();
}

/// Internal storage and any SD card, as `root path -> label` (Android only;
/// empty elsewhere).
///
/// `/storage` itself usually can't be listed, so walking up from
/// `/storage/emulated/0` is a dead end and there is no other way to reach a
/// removable card. `getExternalStorageDirectories` reports one app-specific
/// dir per mounted volume — trimming `/Android/...` off each gives the roots.
Future<Map<String, String>> storageVolumes() async {
  if (Handheld.current) return handheldRoots();
  if (!Platform.isAndroid) return const {};
  var appDirs = <String>[];
  var storageEntries = <String>[];
  try {
    appDirs = [for (final d in await getExternalStorageDirectories() ?? const <Directory>[]) d.path];
  } catch (_) {}
  try {
    // Some handhelds' cards don't show up in the app dirs above; with
    // all-files access `/storage` itself lists every mounted volume.
    storageEntries = [for (final e in Directory('/storage').listSync(followLinks: false)) if (e is Directory) e.path];
  } catch (_) {}
  return volumesFrom(appDirs: appDirs, storageEntries: storageEntries);
}

/// Where the handheld CFWs mount their ROM storage: Knulli `/userdata`, MuOS
/// `/mnt/mmc` + `/mnt/sdcard`, ROCKNIX `/storage`, `/roms`.
const _handheldRoots = ['/userdata', '/mnt/mmc', '/mnt/sdcard', '/storage', '/roms'];

/// The [_handheldRoots] that exist, as `path -> label`. [exists] is injectable
/// so tests don't depend on the host filesystem.
Map<String, String> handheldRoots({bool Function(String)? exists}) {
  final check = exists ?? (d) => Directory(d).existsSync();
  return {for (final r in _handheldRoots) if (check(r)) r: r};
}

/// `root path -> label` from the app-specific dirs (one per mounted volume,
/// trimmed at `/Android/`) and the entries of `/storage`. Internal storage
/// first and always present; `emulated`/`self` are aliases, not cards.
@visibleForTesting
Map<String, String> volumesFrom({required List<String> appDirs, required List<String> storageEntries}) {
  const internal = '/storage/emulated/0';
  final roots = <String>{internal};
  for (final d in appDirs) {
    final marker = d.indexOf('/Android/');
    if (marker > 0) roots.add(d.substring(0, marker));
  }
  for (final e in storageEntries) {
    final name = p.basename(e);
    if (name != 'emulated' && name != 'self') roots.add(e);
  }
  return {for (final r in roots) r: r == internal ? 'Internal storage' : 'SD card (${p.basename(r)})'};
}

class _PathBrowserState extends State<PathBrowser> {
  late String _dir;
  List<Directory> _dirs = [];
  List<File> _files = [];
  Map<String, String> _volumes = const {};
  bool _loading = true;
  String? _error;
  String? _cameFrom;

  // Handed to whichever tile should get focus after a load. A fresh node per
  // load: a reused one keeps a stale context from its previous tile.
  FocusNode _target = FocusNode(debugLabel: 'path-browser-target');

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _dir = widget.initialDir;
    _load(_dir);
    _loadVolumes();
  }

  Future<void> _loadVolumes() async {
    final volumes = await storageVolumes();
    if (!mounted || volumes.length < 2) return;
    setState(() => _volumes = volumes);
  }

  bool _allowed(File f) {
    final exts = widget.allowedExtensions;
    if (exts == null) return true;
    final ext = p.extension(f.path).toLowerCase();
    return ext.isNotEmpty && exts.contains(ext.substring(1));
  }

  /// [cameFrom]: the folder just left, so going up lands back on it.
  Future<void> _load(String path, {String? cameFrom}) async {
    // The focused tile is about to be unmounted by the loader; release focus
    // first so the focus outline never paints a defunct element.
    final focused = FocusManager.instance.primaryFocus;
    if (focused?.context?.findAncestorStateOfType<_PathBrowserState>() == this) focused!.unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await Directory(path).list(followLinks: false).toList();
      final dirs = entries.whereType<Directory>().toList();
      final files = widget.selectDirectory ? <File>[] : entries.whereType<File>().where(_allowed).toList();
      int byName(FileSystemEntity a, FileSystemEntity b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      dirs.sort(byName);
      files.sort(byName);
      if (!mounted) return;
      final previous = _target;
      _target = FocusNode(debugLabel: 'path-browser-target');
      setState(() {
        _dir = path;
        _dirs = dirs;
        _files = files;
        _cameFrom = cameFrom;
        _loading = false;
      });
      // The tile only exists after this frame's build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        previous.dispose();
        if (mounted && _target.context != null) _target.requestFocus();
      });
    } on FileSystemException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.osError?.message ?? e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parent = p.dirname(_dir);
    final canGoUp = parent != _dir;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    _dir,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (_volumes.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final entry in _volumes.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Center(
                          child: ChoiceChip(
                            label: Text(entry.value),
                            selected: _dir == entry.key || p.isWithin(entry.key, _dir),
                            onSelected: (_) => _load(entry.key),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Flexible(child: _body(theme, canGoUp, parent)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  if (widget.selectDirectory) ...[
                    const SizedBox(width: 8),
                    FilledButton(onPressed: () => Navigator.pop(context, _dir), child: const Text('Use this folder')),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, bool canGoUp, String parent) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: HammerLoader()));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off_outlined, color: theme.colorScheme.error),
            const SizedBox(height: 8),
            Text("Can't open this folder: $_error", textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            if (canGoUp) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => _load(parent), child: const Text('Go up')),
            ],
          ],
        ),
      );
    }

    final empty = _dirs.isEmpty && _files.isEmpty;
    // Focus lands on the folder we just left, else the first real entry, else "..".
    final cameFrom = _cameFrom;
    final focusPath = (cameFrom != null && _dirs.any((d) => d.path == cameFrom))
        ? cameFrom
        : (_dirs.isNotEmpty ? _dirs.first.path : (_files.isNotEmpty ? _files.first.path : null));
    return ListView(
      key: ValueKey(_dir),
      shrinkWrap: true,
      children: [
        if (canGoUp)
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward, size: 20),
            title: const Text('..'),
            focusNode: focusPath == null ? _target : null,
            onTap: () => _load(parent, cameFrom: _dir),
          ),
        for (final d in _dirs)
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(p.basename(d.path), overflow: TextOverflow.ellipsis, maxLines: 1),
            focusNode: d.path == focusPath ? _target : null,
            onTap: () => _load(d.path),
          ),
        for (final f in _files)
          ListTile(
            dense: true,
            leading: const Icon(Icons.insert_drive_file_outlined, size: 20),
            title: Text(p.basename(f.path), overflow: TextOverflow.ellipsis, maxLines: 1),
            focusNode: f.path == focusPath ? _target : null,
            onTap: () => Navigator.pop(context, f.path),
          ),
        if (empty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.selectDirectory ? 'No subfolders' : widget.allowedExtensions == null ? 'Empty folder' : 'No matching files here',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
