import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/browser_layout_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// One row in a [FileBrowserView]. [id] must be unique within the listing
/// (a path or a name) — it keys selection and maps back to the underlying
/// SMB/FTP entry in the parent.
class BrowserItem {
  final String id;
  final String name;
  final bool isDir;
  final int size;
  const BrowserItem({required this.id, required this.name, required this.isDir, required this.size});
}

/// An action on the current selection, shown as an icon button. A null
/// [onPressed] shows it disabled (e.g. Rename with more than one item).
class BrowserAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  const BrowserAction({required this.icon, required this.label, required this.onPressed, this.destructive = false});
}

/// A transfer in flight, shown as a progress bar. [total] is 0 while unknown.
class BrowserTransfer {
  final String name;
  final int done;
  final int total;
  final bool upload;
  const BrowserTransfer({required this.name, required this.done, required this.total, required this.upload});

  double get fraction => total > 0 ? done / total : 0;
}

/// The next unfinished background download/zip that [source] ('smb' / 'ftp')
/// queued: the running one, else the first waiting. Null when none. Progress
/// is the task's fraction (0 while it hasn't started, which reads as unknown).
BrowserTransfer? queuedTransfer(WidgetRef ref, String source) {
  final tasks = ref.watch(taskQueueProvider).tasks.where((t) => t.type == TaskType.remoteTransfer && t.params['source'] == source && (t.status == TaskQueueStatus.waiting || t.status == TaskQueueStatus.running));
  final task = tasks.where((t) => t.status == TaskQueueStatus.running).firstOrNull ?? tasks.firstOrNull;
  if (task == null) return null;
  final progress = ref.watch(extractionProvider).tasks[task.id]?.progress ?? 0;
  // ponytail: a fraction in fixed units; the bar only needs done/total.
  return BrowserTransfer(name: '${task.params['verb']} ${task.params['label']}', done: (progress * 1000).round(), total: progress > 0 ? 1000 : 0, upload: false);
}

/// Finder-style file browser: toolbar + icon grid + multi-select action bar +
/// transfer bar. Presentation only — the parent owns the connection, supplies
/// [items]/[selectedIds]/[transfer] and reacts to the callbacks. Shared by the
/// SMB and FTP screens so both look identical.
class FileBrowserView extends ConsumerWidget {
  final String locationLabel;
  final bool canGoUp;
  final bool busy;
  final String? error;
  final List<BrowserItem> items;
  final Set<String> selectedIds;
  final BrowserTransfer? transfer;

  /// 'smb' / 'ftp': also shows that screen's queued background downloads as a
  /// bar. Unlike [transfer] it never blocks selecting or starting more.
  final String? queuedSource;

  /// When false, activating an item opens it (no selection, no checkboxes) — e.g. the SMB shares
  /// root, where entries are shares you can only enter.
  final bool selectable;

  final VoidCallback? onUp;
  final VoidCallback onRefresh;
  final void Function(BrowserItem) onOpen;
  final void Function(BrowserItem) onToggleSelect;
  final VoidCallback onClearSelection;

  /// Selection actions. A null callback hides/disables that action.
  final VoidCallback? onDownload;
  final VoidCallback? onZip;
  final VoidCallback? onDelete;

  /// Replaces the Download/Zip/Delete selection buttons with these.
  final List<BrowserAction>? selectionActions;

  /// Extra buttons at the right of the location bar (e.g. New folder).
  final List<Widget> toolbarActions;

  /// Screen-level actions (New folder, Paste, Upload) added to the Y actions
  /// sheet. Called when the sheet opens; entries with a null `onPressed` are
  /// left out.
  final List<BrowserAction> Function()? extraActions;

  const FileBrowserView({
    super.key,
    required this.locationLabel,
    required this.canGoUp,
    required this.busy,
    this.error,
    required this.items,
    required this.selectedIds,
    this.transfer,
    this.queuedSource,
    this.selectable = true,
    this.onUp,
    required this.onRefresh,
    required this.onOpen,
    required this.onToggleSelect,
    required this.onClearSelection,
    this.onDownload,
    this.onZip,
    this.onDelete,
    this.selectionActions,
    this.toolbarActions = const [],
    this.extraActions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // The user's grid/list choice; until they pick, short screens get the
    // dense list (more entries) and the rest the icon grid.
    final layout = ref.watch(browserLayoutProvider) ?? (MediaQuery.sizeOf(context).height < 640 ? BrowserLayout.list : BrowserLayout.grid);
    final asList = layout == BrowserLayout.list;
    // Y outside a row (toolbar, selection bar); rows bind their own, with the entry.
    return Builder(
      builder: (ctx) => Actions(
        actions: {
          ItemActionsIntent: CallbackAction<ItemActionsIntent>(onInvoke: (_) {
            _showActions(ctx, null);
            return null;
          }),
        },
        child: _body(context, ref, theme, asList),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, ThemeData theme, bool asList) {
    return Column(
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_upward), tooltip: 'Up', onPressed: canGoUp && !busy ? onUp : null),
              Expanded(child: Text(locationLabel, style: const TextStyle(fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
              ...toolbarActions,
              IconButton(
                icon: Icon(asList ? Icons.grid_view_rounded : Icons.view_list_rounded),
                tooltip: asList ? 'Show as grid' : 'Show as list',
                onPressed: () => ref.read(browserLayoutProvider.notifier).set(asList ? BrowserLayout.grid : BrowserLayout.list),
              ),
              IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: busy ? null : onRefresh),
            ],
          ),
        ),
        if (transfer != null) _transferBar(context, transfer!),
        if (queuedSource != null) ...[
          if (queuedTransfer(ref, queuedSource!) case final q?) _transferBar(context, q),
        ],
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: items.isEmpty && !busy
              ? const Center(child: Text('Empty'))
              : asList
                  ? ListView.builder(
                      key: ValueKey(locationLabel),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _row(context, items[i], i),
                    )
                  : GridView.builder(
                      key: ValueKey(locationLabel),
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 132,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _tile(context, items[i], i),
                    ),
        ),
        if (selectedIds.isNotEmpty) _selectionBar(context),
      ],
    );
  }

  /// X marks the entry, Y opens the actions sheet for it.
  Widget _gamepad(BuildContext context, BrowserItem e, Widget child) => Actions(
        actions: {
          if (selectable)
            MarkIntent: CallbackAction<MarkIntent>(onInvoke: (_) {
              onToggleSelect(e);
              return null;
            }),
          ItemActionsIntent: CallbackAction<ItemActionsIntent>(onInvoke: (_) {
            _showActions(context, e);
            return null;
          }),
        },
        child: child,
      );

  /// What the selection bar offers right now, plus Clear and the screen extras.
  List<BrowserAction> _sheetActions() {
    final hasSelection = selectedIds.isNotEmpty;
    final all = <BrowserAction>[
      if (hasSelection && transfer == null)
        ...(selectionActions ??
            [
              BrowserAction(icon: Icons.download, label: 'Download', onPressed: onDownload),
              BrowserAction(icon: Icons.folder_zip, label: 'Zip', onPressed: onZip),
              BrowserAction(icon: Icons.delete, label: 'Delete', onPressed: onDelete, destructive: true),
            ]),
      if (hasSelection) BrowserAction(icon: Icons.close, label: 'Clear selection', onPressed: onClearSelection),
      ...?extraActions?.call(),
    ];
    return [for (final a in all) if (a.onPressed != null) a];
  }

  /// With nothing selected, the focused [entry] is selected first so the list
  /// is the same one the selection bar would show.
  Future<void> _showActions(BuildContext context, BrowserItem? entry) async {
    final nav = Navigator.of(context);
    if (_sheetOpen[nav] == true) return; // a fast double press must not toggle twice or stack sheets
    _sheetOpen[nav] = true;
    try {
      await _openActions(context, entry);
    } finally {
      _sheetOpen[nav] = false;
    }
  }

  // Per navigator, so a sheet that never closes (a test ending) can't block another app.
  static final _sheetOpen = Expando<bool>();

  Future<void> _openActions(BuildContext context, BrowserItem? entry) async {
    var view = this;
    if (entry != null && selectable && selectedIds.isEmpty) {
      onToggleSelect(entry);
      await WidgetsBinding.instance.endOfFrame; // the parent rebuilds with the new selection
      if (!context.mounted) return;
      view = context.findAncestorWidgetOfExactType<FileBrowserView>() ?? this;
    }
    final actions = view._sheetActions();
    if (actions.isEmpty) return;
    final error = Theme.of(context).colorScheme.error;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++)
                ListTile(
                  autofocus: i == 0,
                  leading: Icon(actions[i].icon, color: actions[i].destructive ? error : null),
                  title: Text(actions[i].label, style: actions[i].destructive ? TextStyle(color: error) : null),
                  onTap: () {
                    Navigator.pop(sheet);
                    actions[i].onPressed!();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Folders open (ignored while busy); files toggle selection. Where nothing
  /// is selectable (the SMB shares root) every entry just opens. Never null, so
  /// the row keeps focus while busy (a null onTap would make it unfocusable).
  VoidCallback _activate(BrowserItem e) {
    if (e.isDir || !selectable) {
      return () {
        if (!busy) onOpen(e);
      };
    }
    return () => onToggleSelect(e);
  }

  Widget _checkbox(BrowserItem e) => Checkbox(
        value: selectedIds.contains(e.id),
        onChanged: (_) => onToggleSelect(e),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _tile(BuildContext context, BrowserItem e, int index) => _gamepad(context, e, _tileBody(context, e, index));

  Widget _tileBody(BuildContext context, BrowserItem e, int index) {
    final theme = Theme.of(context);
    final selected = selectedIds.contains(e.id);
    // The checkbox is a sibling above the tile (not an overlay) so the d-pad's
    // Up from the tile reaches it.
    return Column(
      children: [
        if (selectable) Align(alignment: Alignment.centerLeft, child: _checkbox(e)),
        Expanded(
          child: InkWell(
            autofocus: index == 0,
            borderRadius: BorderRadius.circular(10),
            onTap: _activate(e),
            child: Container(
              decoration: BoxDecoration(
                color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: selected ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
              ),
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              child: Column(
                children: [
                  Icon(e.isDir ? Icons.folder : _fileIcon(e.name), size: 48, color: e.isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 6),
                  Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
                  if (!e.isDir) Text(_fmtSize(e.size), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, BrowserItem e, int index) => _gamepad(context, e, _rowBody(context, e, index));

  Widget _rowBody(BuildContext context, BrowserItem e, int index) {
    final theme = Theme.of(context);
    final selected = selectedIds.contains(e.id);
    return Row(
      children: [
        if (selectable) _checkbox(e),
        Expanded(
          child: ListTile(
            autofocus: index == 0,
            dense: true,
            visualDensity: VisualDensity.compact,
            selected: selected,
            selectedTileColor: theme.colorScheme.primaryContainer,
            leading: Icon(e.isDir ? Icons.folder : _fileIcon(e.name), color: e.isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: e.isDir ? null : Text(_fmtSize(e.size), style: theme.textTheme.labelSmall),
            onTap: _activate(e),
          ),
        ),
      ],
    );
  }

  Widget _selectionBar(BuildContext context) {
    final theme = Theme.of(context);
    final busyTransfer = transfer != null;
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.close), tooltip: 'Clear', onPressed: onClearSelection),
              Text('${selectedIds.length} selected', style: theme.textTheme.bodyMedium),
              const Spacer(),
              if (selectionActions != null)
                for (final a in selectionActions!)
                  IconButton(
                    icon: Icon(a.icon, color: a.destructive && a.onPressed != null ? theme.colorScheme.error : null),
                    tooltip: a.label,
                    onPressed: busyTransfer ? null : a.onPressed,
                  )
              else ...[
                TextButton.icon(
                  onPressed: busyTransfer ? null : onDownload,
                  icon: const Icon(Icons.download),
                  label: const Text('Download'),
                ),
                TextButton.icon(
                  onPressed: busyTransfer ? null : onZip,
                  icon: const Icon(Icons.folder_zip),
                  label: const Text('Zip'),
                ),
                TextButton.icon(
                  onPressed: busyTransfer ? null : onDelete,
                  icon: Icon(Icons.delete, color: theme.colorScheme.error),
                  label: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _transferBar(BuildContext context, BrowserTransfer t) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(t.upload ? Icons.upload : Icons.download, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(t.name, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)),
              if (t.total > 0) Text('${(t.fraction * 100).toStringAsFixed(0)}%', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: t.total > 0 ? t.fraction : null),
        ],
      ),
    );
  }
}

IconData _fileIcon(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.zip') || n.endsWith('.7z') || n.endsWith('.rar')) return Icons.folder_zip;
  if (n.endsWith('.txt') || n.endsWith('.nfo') || n.endsWith('.md')) return Icons.description;
  if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg')) return Icons.image;
  return Icons.insert_drive_file;
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var u = 0;
  while (size >= 1024 && u < units.length - 1) {
    size /= 1024;
    u++;
  }
  return '${size.toStringAsFixed(size >= 10 ? 0 : 1)} ${units[u]}';
}
