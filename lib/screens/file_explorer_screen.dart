import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/services/file_ops.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';
import 'package:retro_toolbox/widgets/file_browser.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Local file explorer: browse the device's storage, then copy/move (paste
/// into another folder), zip, extract, rename, create folders and delete.
/// Copy, move, zip and extract run as background tasks (task manager and
/// notification), so the user can leave while they work.
class FileExplorerScreen extends ConsumerStatefulWidget {
  /// Open this folder instead of the storage list. For tests and screenshots.
  @visibleForTesting
  final String? initialPath;

  /// The storage roots (path to name) instead of this device's. For screenshots.
  @visibleForTesting
  final Map<String, String>? roots;

  const FileExplorerScreen({super.key, this.initialPath, this.roots});

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

  /// What went wrong, for a person, and the raw error behind Details.
  ({String line, String? details})? _error;
  final Set<String> _ourTasks = {};

  @override
  void initState() {
    super.initState();
    _loadRoots();
    if (widget.initialPath != null) _load(widget.initialPath!);
  }

  Future<void> _loadRoots() async {
    if (widget.roots != null) return setState(() => _roots = widget.roots!);
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
          _error = _failed('open', p.basename(dir), e);
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
      _showRoots();
    } else {
      _load(parent);
    }
  }

  Future<void> _refresh() async {
    if (_dir != null) await _load(_dir!);
  }

  List<String> get _selectedPaths => _entries.map((e) => e.path).where(_selected.contains).toList();

  String _labelFor(List<String> paths) => paths.length == 1 ? p.basename(paths.single) : '${paths.length} items';

  /// "Can't delete notes.txt: permission denied", with the raw error behind Details.
  static ({String line, String? details}) _failed(String verb, String name, Object e) {
    final reason = errorReason(e);
    // "Permission denied" reads as part of the sentence; "SMB..." keeps its caps.
    final lower = reason.length > 1 && reason[1] == reason[1].toLowerCase() ? reason[0].toLowerCase() + reason.substring(1) : reason;
    return (line: "Can't $verb $name: $lower", details: '$e');
  }

  // ---- Background tasks ----------------------------------------------------

  /// Queues [type] with a task-manager row titled [title]. [verb] and [label]
  /// name it in the progress bar under the location bar ('Zipping', 'saves.zip').
  void _enqueue(TaskType type, String title, String verb, String label, Map<String, dynamic> params) {
    // Unique per job: the task key comes from the URL's file name.
    final game = Game(title: title, url: 'https://manual/op-${DateTime.now().microsecondsSinceEpoch}.task', size: 0, consoleId: 'manual');
    ref.read(gameStateManagerProvider.notifier).registerTransientGame(game);
    _ourTasks.add(game.gameId);
    ref.read(taskQueueProvider.notifier).enqueue(game.gameId, type, {'taskId': game.gameId, 'source': 'explorer', 'verb': verb, 'label': label, ...params});
  }

  void _paste() {
    final clip = _clipboard, dir = _dir;
    if (clip == null || dir == null) return;
    final label = _labelFor(clip.paths);
    _enqueue(TaskType.fileCopy, '${clip.move ? 'Move' : 'Copy'} $label', clip.move ? 'Moving' : 'Copying', label, {
      'sources': clip.paths,
      'destDir': dir,
      'move': clip.move,
      'label': label,
    });
    setState(() => _clipboard = null);
  }

  Future<void> _zip() async {
    final dir = _dir;
    final paths = _selectedPaths;
    if (dir == null || paths.isEmpty) return;
    final base = paths.length == 1 ? p.basenameWithoutExtension(paths.single) : p.basename(dir);
    final outZip = p.join(dir, FileOps.uniqueName(dir, '$base.zip'));
    if (!await _confirm('Compress?', 'Compress ${_labelFor(paths)} into\n$outZip', 'Compress') || !mounted) return;
    final name = p.basename(outZip);
    _enqueue(TaskType.fileZip, 'Zip $name', 'Zipping', name, {'sources': paths, 'outZip': outZip});
    setState(() => _selected = {});
  }

  /// Extracts into a new folder named after the archive, beside it.
  Future<void> _extract() async {
    final dir = _dir;
    final paths = _selectedPaths;
    if (dir == null || paths.length != 1) return;
    final archive = paths.single, name = p.basename(archive);
    final out = p.join(dir, FileOps.uniqueName(dir, p.basenameWithoutExtension(archive)));
    final deleteOriginals = ValueNotifier(false);
    if (!await _confirm('Extract?', 'Extract $name into\n$out', 'Extract', deleteOriginals: deleteOriginals) || !mounted) return;
    _enqueue(TaskType.archiveExtraction, 'Extract $name', 'Extracting', name, {
      'archivePath': archive,
      'outputDir': out,
      'deleteOriginals': deleteOriginals.value,
    });
    setState(() => _selected = {});
  }

  /// Asks before a background job. Focus starts on [action] for the d-pad;
  /// Back (B / Escape) cancels. With [deleteOriginals] it also offers the
  /// tools' "Delete original when done".
  Future<bool> _confirm(String title, String message, String action, {ValueNotifier<bool>? deleteOriginals}) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: deleteOriginals == null
              ? Text(message)
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message),
                    const SizedBox(height: 12),
                    ValueListenableBuilder(
                      valueListenable: deleteOriginals,
                      builder: (_, value, __) => CheckboxListTile(
                        value: value,
                        onChanged: (v) => deleteOriginals.value = v ?? false,
                        title: const Text('Delete original when done'),
                        subtitle: const Text('Only after a successful extraction, with every part of a multi-part archive.'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(autofocus: true, onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ==
      true;

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
      setState(() => _error = (line: 'Invalid name: $name', details: null));
      return null;
    }
    if (FileSystemEntity.typeSync(p.join(dir, name)) != FileSystemEntityType.notFound) {
      setState(() => _error = (line: '$name already exists', details: null));
      return null;
    }
    return name;
  }

  Future<void> _newFolder() async {
    final dir = _dir;
    if (dir == null) return;
    final name = _validName(await _askName('New folder', 'New folder'), dir);
    if (name == null) return;
    ({String line, String? details})? error;
    try {
      await Directory(p.join(dir, name)).create();
    } catch (e) {
      error = _failed('create', name, e);
    }
    await _refresh();
    // After the refresh, which clears the error of the listing.
    if (error != null && mounted) setState(() => _error = error);
  }

  Future<void> _rename() async {
    final dir = _dir;
    final paths = _selectedPaths;
    if (dir == null || paths.length != 1) return;
    final old = paths.single;
    final name = _validName(await _askName('Rename', p.basename(old)), dir);
    if (name == null) return;
    ({String line, String? details})? error;
    try {
      await (await FileSystemEntity.isDirectory(old) ? Directory(old).rename(p.join(dir, name)) : File(old).rename(p.join(dir, name)));
    } catch (e) {
      error = _failed('rename', p.basename(old), e);
    }
    await _refresh();
    if (error != null && mounted) setState(() => _error = error);
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
    final failed = <(String, Object)>[];
    for (final path in paths) {
      try {
        await (await FileSystemEntity.isDirectory(path) ? Directory(path).delete(recursive: true) : File(path).delete());
      } catch (e) {
        failed.add((path, e));
      }
    }
    await _refresh();
    if (failed.isNotEmpty && mounted) {
      setState(() => _error = failed.length == 1
          ? _failed('delete', p.basename(failed.single.$1), failed.single.$2)
          : (line: "Can't delete ${failed.length} items", details: [for (final (path, e) in failed) '${p.basename(path)}: $e'].join('\n')));
    }
  }

  // ---- UI -------------------------------------------------------------------

  void _showRoots() => setState(() {
        _dir = null;
        _entries = [];
        _selected = {};
        _error = null;
      });

  /// The storage root [dir] is in (the deepest, so Downloads wins over Internal).
  String? _rootOf(String dir) =>
      _roots.keys.where((r) => dir == r || p.isWithin(r, dir)).fold<String?>(null, (best, r) => best == null || r.length > best.length ? r : best);

  /// The storage root by its name, then each folder down to this one; each
  /// goes there on a tap. Back from the root shows the storage list.
  List<Crumb> _crumbs() {
    final dir = _dir;
    if (dir == null) return const [Crumb('Storage')];
    final root = _rootOf(dir);
    final out = <Crumb>[];
    var at = root ?? p.rootPrefix(dir);
    if (root != null) {
      out.add(Crumb(_roots[root]!, () => _load(root)));
    } else if (at.isNotEmpty) {
      out.add(Crumb(at, () => _load(at)));
    }
    for (final part in p.split(p.relative(dir, from: at.isEmpty ? '.' : at))) {
      if (part == '.') continue;
      final target = at = p.join(at, part);
      out.add(Crumb(part, () => _load(target)));
    }
    return out;
  }

  /// Jump between internal storage, SD cards and Downloads from any folder.
  void _pickStorage() {
    final current = _dir == null ? null : _rootOf(_dir!);
    showRowMenu(context, title: 'Storage', items: [
      for (final r in _roots.entries)
        RowMenuItem(r.value, () => _load(r.key), subtitle: r.key, icon: r.key == current ? Icons.check : Icons.sd_storage_outlined),
    ]);
  }

  static const _info = InfoButton(
    icon: Icons.folder_copy,
    title: 'File Explorer',
    text: 'X or a long press selects. Y opens the actions for the focused item. '
        'Copy and Move hold the items until you open the folder they go to and press Paste here (Start). '
        'Copy, move, zip and extract keep running in Tasks if you leave.',
  );

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

    final atRoots = _dir == null;
    final selected = _selectedPaths;
    final single = selected.length == 1 ? selected.single : null;
    final archive = single != null && ArchiveExtractService.archiveKind(single) != ArchiveKind.unsupported;
    final clip = _clipboard;
    final pad = ref.watch(inputModeProvider) == InputMode.gamepad;
    final portrait = DeviceClass.of(context) == DeviceClass.portrait;

    final items = atRoots
        ? [for (final r in _roots.entries) BrowserItem(id: r.key, name: r.value, isDir: true, size: 0, detail: r.key)]
        : [
            for (final e in _entries)
              BrowserItem(
                id: e.path,
                name: p.basename(e.path),
                isDir: e is Directory,
                size: e is File ? _sizeOf(e) : 0,
              ),
          ];

    // The paste bar is the action bar: Start pastes. With a pad and nothing
    // to paste it carries the button hints.
    final bar = clip != null || (pad && !portrait)
        ? ActionBar(
            primary: clip == null ? null : KitAction('Paste here', atRoots ? null : _paste, icon: Icons.content_paste),
            secondary: clip == null ? null : KitAction('Cancel', () => setState(() => _clipboard = null), icon: Icons.close),
            hints: const [KitHint(PadButton.a, 'Open'), KitHint(PadButton.x, 'Select'), KitHint(PadButton.y, 'Actions'), KitHint(PadButton.b, 'Up')],
            summary: clip == null ? null : '${clip.move ? 'Move' : 'Copy'} ${_labelFor(clip.paths)}: open the folder and paste',
          )
        : null;

    return PopScope(
      // Back goes up a folder; only the storage list leaves the screen.
      canPop: atRoots,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _up();
      },
      // Start pastes when something is waiting to be pasted here, and does
      // nothing otherwise (it must not press whatever has focus). The action
      // bar binds it too; this covers focus that fell out of the screen.
      child: Actions(
        actions: {
          PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(onInvoke: (_) {
            if (_clipboard != null && _dir != null) _paste();
            return null;
          }),
        },
        // Own scope, so focus lost with a closed folder's rows lands here (under
        // the Actions above) instead of the route.
        child: FocusScope(
          child: KitScaffold(
            title: 'File Explorer',
            subtitle: 'Copy, move, zip and extract on this device',
            icon: Icons.folder_copy,
            glyph: PixelIcons.explorer,
            area: AppArea.tools,
            info: _info,
            actionBar: bar,
            body: FileBrowserView(
              locationLabel: _dir ?? 'Storage',
              crumbs: _crumbs(),
              queuedSource: 'explorer',
              busy: _busy,
              error: _error?.details,
              errorLine: _error?.line,
              items: items,
              selectedIds: _selected,
              selectable: !atRoots,
              onRefresh: atRoots ? _loadRoots : _refresh,
              onOpen: (item) => _load(item.id),
              onToggleSelect: (item) => setState(() {
                _selected = {..._selected};
                _selected.contains(item.id) ? _selected.remove(item.id) : _selected.add(item.id);
              }),
              onClearSelection: () => setState(() => _selected = {}),
              emptyLine: atRoots ? 'No storage found' : 'This folder is empty',
              emptyAction: atRoots ? null : KitAction('New folder', _busy ? null : _newFolder, icon: Icons.create_new_folder_outlined),
              barActions: [
                if (!atRoots) KitAction('New folder', _busy ? null : _newFolder, icon: Icons.create_new_folder_outlined),
                if (!atRoots && _roots.isNotEmpty) KitAction('Storage', _pickStorage, icon: Icons.sd_storage_outlined),
              ],
              extraActions: () => [
                if (!atRoots) BrowserAction(icon: Icons.create_new_folder_outlined, label: 'New folder', onPressed: _busy ? null : _newFolder),
                if (_clipboard != null) ...[
                  BrowserAction(icon: Icons.content_paste, label: 'Paste here', onPressed: atRoots ? null : _paste),
                  BrowserAction(icon: Icons.content_paste_off, label: 'Cancel paste', onPressed: () => setState(() => _clipboard = null)),
                ],
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
                BrowserAction(icon: Icons.drive_file_rename_outline, label: 'Rename', onPressed: single == null ? null : _rename, inBar: false),
                BrowserAction(icon: Icons.folder_zip_outlined, label: 'Zip', onPressed: _zip, inBar: false),
                BrowserAction(icon: Icons.unarchive_outlined, label: 'Extract here', onPressed: archive ? _extract : null, inBar: false),
                BrowserAction(icon: Icons.delete_outline, label: 'Delete', onPressed: _delete, destructive: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _sizeOf(File f) {
    try {
      return f.lengthSync();
    } catch (_) {
      return 0;
    }
  }
}
