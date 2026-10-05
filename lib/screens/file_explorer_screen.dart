import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/services/file_ops.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';
import 'package:retro_toolbox/widgets/file_browser.dart';

/// Local file explorer: browse the device's storage, then copy/move (paste
/// into another folder), zip, extract, rename, create folders and delete.
/// Copy, move, zip and extract run as background tasks (task manager and
/// notification), so the user can leave while they work.
class FileExplorerScreen extends ConsumerStatefulWidget {
  /// Open this folder instead of the storage list. For tests and screenshots.
  @visibleForTesting
  final String? initialPath;

  const FileExplorerScreen({super.key, this.initialPath});

  @override
  ConsumerState<FileExplorerScreen> createState() => _FileExplorerScreenState();
}

/// Paths waiting to be pasted, and whether the paste moves them.
class _Clipboard {
  final List<String> paths;
  final bool move;
  const _Clipboard(this.paths, this.move);
}

class _FileExplorerScreenState extends ConsumerState<FileExplorerScreen> {
  Map<String, String> _roots = const {}; // path -> label
  String? _dir; // null = the storage list
  List<FileSystemEntity> _entries = [];
  Set<String> _selected = {};
  _Clipboard? _clipboard;
  bool _busy = false;
  String? _error;
  final Set<String> _ourTasks = {};

  @override
  void initState() {
    super.initState();
    _loadRoots();
    if (widget.initialPath != null) _load(widget.initialPath!);
  }

  Future<void> _loadRoots() async {
    final roots = <String, String>{...await storageVolumes()};
    if (!Platform.isAndroid) {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) roots[home] = 'Home';
    }
    try {
      final downloads = await DirectoryService().getDownloadDir();
      if (downloads.isNotEmpty) roots.putIfAbsent(downloads, () => 'Downloads');
    } catch (_) {}
    if (mounted) setState(() => _roots = roots);
  }

  Future<void> _load(String dir) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entries = await Directory(dir).list(followLinks: false).toList();
      entries.sort((a, b) {
        final ad = a is Directory, bd = b is Directory;
        if (ad != bd) return ad ? -1 : 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _dir = dir;
        _entries = entries;
        _selected = {};
        _busy = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  void _up() {
    final dir = _dir;
    if (dir == null) return;
    final parent = p.dirname(dir);
    // Leaving a storage root (or the filesystem root) goes back to the list.
    if (_roots.containsKey(dir) || parent == dir) {
      setState(() {
        _dir = null;
        _entries = [];
        _selected = {};
        _error = null;
      });
    } else {
      _load(parent);
    }
  }

  Future<void> _refresh() async {
    if (_dir != null) await _load(_dir!);
  }

  List<String> get _selectedPaths => _entries.map((e) => e.path).where(_selected.contains).toList();

  String _labelFor(List<String> paths) => paths.length == 1 ? p.basename(paths.single) : '${paths.length} items';

  // ---- Background tasks ----------------------------------------------------

  /// Queues [type] with a task-manager row titled [title].
  void _enqueue(TaskType type, String title, Map<String, dynamic> params) {
    // Unique per job: the task key comes from the URL's file name.
    final game = Game(title: title, url: 'https://manual/op-${DateTime.now().microsecondsSinceEpoch}.task', size: 0, consoleId: 'manual');
    ref.read(gameStateManagerProvider.notifier).registerTransientGame(game);
    _ourTasks.add(game.gameId);
    ref.read(taskQueueProvider.notifier).enqueue(game.gameId, type, {'taskId': game.gameId, ...params});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title added to the task list')));
  }

  void _paste() {
    final clip = _clipboard, dir = _dir;
    if (clip == null || dir == null) return;
    final label = _labelFor(clip.paths);
    _enqueue(TaskType.fileCopy, '${clip.move ? 'Move' : 'Copy'} $label', {
      'sources': clip.paths,
      'destDir': dir,
      'move': clip.move,
      'label': label,
    });
    setState(() => _clipboard = null);
  }

  void _zip() {
    final dir = _dir;
    final paths = _selectedPaths;
    if (dir == null || paths.isEmpty) return;
    final base = paths.length == 1 ? p.basenameWithoutExtension(paths.single) : p.basename(dir);
    final outZip = p.join(dir, FileOps.uniqueName(dir, '$base.zip'));
    _enqueue(TaskType.fileZip, 'Zip ${p.basename(outZip)}', {'sources': paths, 'outZip': outZip, 'label': p.basename(outZip)});
    setState(() => _selected = {});
  }

  /// Extracts into a new folder named after the archive, beside it.
  void _extract() {
    final dir = _dir;
    final paths = _selectedPaths;
    if (dir == null || paths.length != 1) return;
    final archive = paths.single;
    final out = p.join(dir, FileOps.uniqueName(dir, p.basenameWithoutExtension(archive)));
    _enqueue(TaskType.archiveExtraction, 'Extract ${p.basename(archive)}', {'archivePath': archive, 'outputDir': out});
    setState(() => _selected = {});
  }

  // ---- Instant operations --------------------------------------------------

  Future<String?> _askName(String title, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v.trim())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
  }

  /// A name that's safe to create in [dir], or null after reporting why not.
  String? _validName(String? name, String dir) {
    if (name == null || name.isEmpty) return null;
    if (name.contains('/') || name.contains('\\') || name == '.' || name == '..') {
      setState(() => _error = 'Invalid name: $name');
      return null;
    }
    if (FileSystemEntity.typeSync(p.join(dir, name)) != FileSystemEntityType.notFound) {
      setState(() => _error = '$name already exists');
      return null;
    }
    return name;
  }

  Future<void> _newFolder() async {
    final dir = _dir;
    if (dir == null) return;
    final name = _validName(await _askName('New folder', 'New folder'), dir);
    if (name == null) return;
    try {
      await Directory(p.join(dir, name)).create();
    } catch (e) {
      setState(() => _error = '$e');
    }
    await _refresh();
  }

  Future<void> _rename() async {
    final dir = _dir;
    final paths = _selectedPaths;
    if (dir == null || paths.length != 1) return;
    final old = paths.single;
    final name = _validName(await _askName('Rename', p.basename(old)), dir);
    if (name == null) return;
    try {
      await (await FileSystemEntity.isDirectory(old) ? Directory(old).rename(p.join(dir, name)) : File(old).rename(p.join(dir, name)));
    } catch (e) {
      setState(() => _error = '$e');
    }
    await _refresh();
  }

  Future<void> _delete() async {
    final paths = _selectedPaths;
    if (paths.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${_labelFor(paths)}? Folders are deleted with everything inside. This cannot be undone.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    for (final path in paths) {
      try {
        await (await FileSystemEntity.isDirectory(path) ? Directory(path).delete(recursive: true) : File(path).delete());
      } catch (e) {
        setState(() => _error = '$e');
      }
    }
    await _refresh();
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Show the result of our own copy/zip/extract once it lands here.
    ref.listen(taskQueueProvider, (prev, next) {
      final finished = next.tasks.any((t) =>
          _ourTasks.contains(t.id) && t.status != TaskQueueStatus.waiting && t.status != TaskQueueStatus.running);
      if (finished) {
        _ourTasks.removeWhere((id) => next.tasks.any((t) => t.id == id && t.status != TaskQueueStatus.waiting && t.status != TaskQueueStatus.running));
        _refresh();
      }
    });

    final compact = MediaQuery.sizeOf(context).height < 640;
    final atRoots = _dir == null;
    final selected = _selectedPaths;
    final single = selected.length == 1 ? selected.single : null;
    final archive = single != null && ArchiveExtractService.archiveKind(single) != ArchiveKind.unsupported;

    final items = atRoots
        ? [for (final r in _roots.entries) BrowserItem(id: r.key, name: r.value, isDir: true, size: 0)]
        : [
            for (final e in _entries)
              BrowserItem(
                id: e.path,
                name: p.basename(e.path),
                isDir: e is Directory,
                size: e is File ? _sizeOf(e) : 0,
              ),
          ];

    return PopScope(
      // Back goes up a folder; only the storage list leaves the screen.
      canPop: atRoots,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      // Start pastes when something is waiting to be pasted here.
      child: Actions(
        actions: {
          if (_clipboard != null && !atRoots)
            PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(onInvoke: (_) {
              _paste();
              return null;
            }),
        },
        // Own scope, so focus lost with a closed folder's rows lands here (under
        // the Actions above) instead of the route.
        child: FocusScope(
          child: Scaffold(
            appBar: AppBar(title: const Text('File Explorer'), toolbarHeight: compact ? 48 : null),
            body: Column(
              children: [
                Expanded(
                  child: FileBrowserView(
                    locationLabel: _dir ?? 'Storage',
                    canGoUp: !atRoots,
                    busy: _busy,
                    error: _error,
                    items: items,
                    selectedIds: _selected,
                    selectable: !atRoots,
                    onUp: _up,
                    onRefresh: atRoots ? _loadRoots : _refresh,
                    onOpen: (item) => _load(item.id),
                    onToggleSelect: (item) => setState(() {
                      _selected = {..._selected};
                      _selected.contains(item.id) ? _selected.remove(item.id) : _selected.add(item.id);
                    }),
                    onClearSelection: () => setState(() => _selected = {}),
                    extraActions: () => [
                      if (!atRoots) BrowserAction(icon: Icons.create_new_folder_outlined, label: 'New folder', onPressed: _busy ? null : _newFolder),
                      if (_clipboard != null) ...[
                        BrowserAction(icon: Icons.content_paste, label: 'Paste here', onPressed: atRoots ? null : _paste),
                        BrowserAction(icon: Icons.content_paste_off, label: 'Cancel paste', onPressed: () => setState(() => _clipboard = null)),
                      ],
                    ],
                    toolbarActions: [
                      if (!atRoots) IconButton(icon: const Icon(Icons.create_new_folder_outlined), tooltip: 'New folder', onPressed: _busy ? null : _newFolder),
                      if (_roots.isNotEmpty) _storagePicker(),
                    ],
                    selectionActions: [
                      BrowserAction(
                        icon: Icons.copy,
                        label: 'Copy',
                        onPressed: () => setState(() {
                          _clipboard = _Clipboard(selected, false);
                          _selected = {};
                        }),
                      ),
                      BrowserAction(
                        icon: Icons.drive_file_move_outline,
                        label: 'Move',
                        onPressed: () => setState(() {
                          _clipboard = _Clipboard(selected, true);
                          _selected = {};
                        }),
                      ),
                      BrowserAction(icon: Icons.drive_file_rename_outline, label: 'Rename', onPressed: single == null ? null : _rename),
                      BrowserAction(icon: Icons.folder_zip_outlined, label: 'Zip', onPressed: _zip),
                      BrowserAction(icon: Icons.unarchive_outlined, label: 'Extract here', onPressed: archive ? _extract : null),
                      BrowserAction(icon: Icons.delete_outline, label: 'Delete', onPressed: _delete, destructive: true),
                    ],
                  ),
                ),
                if (_clipboard != null) _pasteBar(Theme.of(context), atRoots),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Jump between internal storage, SD cards and Downloads from any folder.
  Widget _storagePicker() {
    final current = _dir == null
        ? null
        : _roots.keys.where((r) => _dir == r || p.isWithin(r, _dir!)).fold<String?>(null, (best, r) => best == null || r.length > best.length ? r : best);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.sd_storage_outlined),
      tooltip: 'Storage',
      onSelected: _load,
      itemBuilder: (_) => [
        for (final r in _roots.entries)
          CheckedPopupMenuItem(value: r.key, checked: r.key == current, child: Text(r.value)),
      ],
    );
  }

  static int _sizeOf(File f) {
    try {
      return f.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  Widget _pasteBar(ThemeData theme, bool atRoots) {
    final clip = _clipboard!;
    return Material(
      color: theme.colorScheme.primaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(clip.move ? Icons.drive_file_move_outline : Icons.copy, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${clip.move ? 'Move' : 'Copy'} ${_labelFor(clip.paths)}: open the destination and paste',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(onPressed: () => setState(() => _clipboard = null), child: const Text('Cancel')),
              FilledButton(onPressed: atRoots ? null : _paste, child: const Text('Paste here')),
            ],
          ),
        ),
      ),
    );
  }
}
