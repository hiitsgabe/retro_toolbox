import 'dart:io' show FileSystemException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/browser_layout_provider.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/widgets/card_styles/selected_mark.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// One row in a [FileBrowserView]. [id] must be unique within the listing
/// (a path or a name): it keys selection and maps back to the underlying
/// SMB/FTP entry in the parent. [detail] replaces the size under the name
/// (a storage root's path).
class BrowserItem {
  final String id;
  final String name;
  final bool isDir;
  final int size;
  final String? detail;
  const BrowserItem({required this.id, required this.name, required this.isDir, required this.size, this.detail});
}

/// An action on the current selection. A null [onPressed] shows it disabled
/// in the selection bar and leaves it out of the actions sheet (Rename with
/// more than one item). [inBar]: shown by name in the selection bar; the
/// rest wait behind More (and Y).
class BrowserAction {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool inBar;
  const BrowserAction({required this.icon, required this.label, required this.onPressed, this.destructive = false, this.inBar = true});
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

/// What a person can read of [error]: the system's reason for a file error
/// ("Permission denied"), else its first line without the exception's type,
/// kept short. The raw text goes behind Details.
String errorReason(Object error) {
  if (error is FileSystemException) {
    final os = error.osError?.message ?? '';
    if (os.isNotEmpty) return os;
    if (error.message.isNotEmpty) return error.message;
  }
  final raw = '$error';
  final os = RegExp(r'OS Error: ([^,)]+)').firstMatch(raw);
  if (os != null) return os.group(1)!.trim();
  var line = raw.trim().split('\n').first.trim().replaceFirst(RegExp(r'^[A-Za-z]*(Exception|Error):\s*'), '');
  if (line.length > 90) line = '${line.substring(0, 89)}…';
  return line.isEmpty ? 'Unknown error' : line;
}

/// The trail of a remote '/'-separated [path]: [root] (the shares, the
/// server's /) then each folder, each opening its own path through [go]
/// ('' for the root, '/a/b' below it).
List<Crumb> remoteCrumbs(String root, String path, void Function(String path) go) {
  final parts = path.split('/').where((s) => s.isNotEmpty).toList();
  return [
    Crumb(root, () => go('')),
    for (var i = 0; i < parts.length; i++) Crumb(parts[i], () => go('/${parts.take(i + 1).join('/')}')),
  ];
}

/// [source]'s ('smb' / 'ftp' / 'explorer') background tasks as bars, read
/// from the task queue the task manager shows: every running task (else the
/// first waiting one), plus tasks that failed while this browser was open,
/// with their error until dismissed. Progress comes from the extraction
/// provider because file tasks share its machinery.
class _QueuedTaskBars extends ConsumerStatefulWidget {
  final String source;
  const _QueuedTaskBars(this.source);

  @override
  ConsumerState<_QueuedTaskBars> createState() => _QueuedTaskBarsState();
}

class _QueuedTaskBarsState extends ConsumerState<_QueuedTaskBars> {
  final _opened = DateTime.now();
  final _dismissed = <QueuedTask>{}; // by identity: a retry's failure is a new object

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(taskQueueProvider).tasks.where((t) => t.params['source'] == widget.source).toList();
    final running = mine.where((t) => t.status == TaskQueueStatus.running);
    final failed = mine.where((t) => t.status == TaskQueueStatus.failed && (t.completedAt?.isAfter(_opened) ?? false) && !_dismissed.contains(t));
    final shown = [
      ...running.isNotEmpty ? running : mine.where((t) => t.status == TaskQueueStatus.waiting).take(1),
      ...failed,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in shown)
        Padding(
          padding: const EdgeInsets.only(top: kitGap),
          child: t.status == TaskQueueStatus.failed
              ? StatusPanel.error(
                  line: '${_taskName(t)} failed: ${errorReason(t.error ?? 'unknown error')}',
                  details: t.error,
                  onDismiss: () => setState(() => _dismissed.add(t)),
                )
              : _TaskProgressBar(t, key: ValueKey(t.id)),
        ),
    ]);
  }
}

String _taskName(QueuedTask t) => '${t.params['verb']} ${t.params['label']}';

/// One running or waiting task. Watches only that task's progress, so it
/// alone rebuilds as it moves.
class _TaskProgressBar extends ConsumerWidget {
  final QueuedTask task;
  const _TaskProgressBar(this.task, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = task.status == TaskQueueStatus.running ? ref.watch(extractionProvider.select((s) => s.tasks[task.id]?.progress)) ?? 0 : 0.0;
    final icon = switch (task.type) {
      TaskType.fileZip => Icons.folder_zip_outlined,
      TaskType.archiveExtraction => Icons.unarchive_outlined,
      TaskType.fileCopy => Icons.copy,
      _ => Icons.download,
    };
    // ponytail: a fraction in fixed units; the bar only needs done/total.
    return _TransferPanel(
      BrowserTransfer(name: _taskName(task), done: (progress * 1000).round(), total: progress > 0 ? 1000 : 0, upload: false),
      icon: icon,
      onCancel: () => TaskQueueService.cancelBackgroundTask(ref, task),
    );
  }
}

/// A transfer or a background job: its name, how far, and Cancel when it can
/// be stopped.
class _TransferPanel extends StatelessWidget {
  const _TransferPanel(this.t, {this.icon, this.onCancel});

  final BrowserTransfer t;
  final IconData? icon;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final kt = KitType.of(context);
    return KitPanel(padding: EdgeInsets.fromLTRB(12, 8, onCancel == null ? 12 : 4, 8), children: [
      Row(children: [
        Icon(icon ?? (t.upload ? Icons.upload : Icons.download), size: 18, color: kt.k.accent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: kt.row)),
              if (t.total > 0) ...[
                const SizedBox(width: 8),
                Text('${(t.fraction * 100).toStringAsFixed(0)}%', style: kt.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: t.total > 0 ? t.fraction : null, minHeight: 5)),
          ]),
        ),
        if (onCancel != null) IconButton(icon: const Icon(Icons.close, size: 20), tooltip: 'Cancel', onPressed: onCancel, visualDensity: VisualDensity.compact),
      ]),
    ]);
  }
}

/// The browser pattern of File Explorer, SMB and the FTP client: the folder
/// trail with the folder's actions by name, the work running for this
/// browser, readable errors, the entries (a list unless the user picks the
/// grid) and, while something is marked, a bar of named actions. Presentation
/// only: the parent owns the connection, supplies [items]/[selectedIds]/
/// [transfer] and reacts to the callbacks.
///
/// Pad: A opens a folder or marks a file, X marks, Y opens the actions,
/// Select the folder options. Touch: a tap opens or marks, a long press marks
/// (folders too).
class FileBrowserView extends ConsumerWidget {
  /// The full location; keys the list, and is the trail when [crumbs] is null.
  final String locationLabel;

  /// The folder trail, the current folder last. Taps are ignored while busy.
  final List<Crumb>? crumbs;
  final bool busy;

  /// The raw error; shown behind Details, under [errorLine] (null: its
  /// [errorReason]).
  final String? error;
  final String? errorLine;
  final List<BrowserItem> items;
  final Set<String> selectedIds;
  final BrowserTransfer? transfer;

  /// 'smb' / 'ftp' / 'explorer': shows that screen's background tasks (queued
  /// with `params['source']` set to it) as bars under the trail. Unlike
  /// [transfer] they never block selecting or starting more.
  final String? queuedSource;

  /// When false, activating an item opens it (no selection, no checkboxes): e.g. the SMB shares
  /// root, where entries are shares you can only enter.
  final bool selectable;

  final VoidCallback onRefresh;
  final void Function(BrowserItem) onOpen;
  final void Function(BrowserItem) onToggleSelect;
  final VoidCallback onClearSelection;

  /// Selection actions. A null callback disables that action.
  final VoidCallback? onDownload;
  final VoidCallback? onZip;
  final VoidCallback? onDelete;

  /// Replaces the Download/Zip/Delete selection actions with these.
  final List<BrowserAction>? selectionActions;

  /// The folder's actions by name in the trail's bar (New folder, Storage).
  final List<KitAction> barActions;

  /// Screen-level actions (New folder, Paste, Upload) added to the Y actions
  /// sheet. Called when the sheet opens; entries with a null `onPressed` are
  /// left out.
  final List<BrowserAction> Function()? extraActions;

  /// Shown when the folder has nothing in it.
  final String emptyLine;
  final KitAction? emptyAction;

  const FileBrowserView({
    super.key,
    required this.locationLabel,
    this.crumbs,
    required this.busy,
    this.error,
    this.errorLine,
    required this.items,
    required this.selectedIds,
    this.transfer,
    this.queuedSource,
    this.selectable = true,
    required this.onRefresh,
    required this.onOpen,
    required this.onToggleSelect,
    required this.onClearSelection,
    this.onDownload,
    this.onZip,
    this.onDelete,
    this.selectionActions,
    this.barActions = const [],
    this.extraActions,
    this.emptyLine = 'This folder is empty',
    this.emptyAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The user's grid/list choice; until they pick, a list: more names, readable, on every device.
    final asList = (ref.watch(browserLayoutProvider) ?? BrowserLayout.list) == BrowserLayout.list;
    // Y outside a row (trail, selection bar); rows bind their own, with the entry.
    return Builder(
      builder: (ctx) => Actions(
        actions: {
          ItemActionsIntent: CallbackAction<ItemActionsIntent>(onInvoke: (_) {
            _showActions(ctx, null);
            return null;
          }),
          OptionsIntent: CallbackAction<OptionsIntent>(onInvoke: (_) {
            _showFolderMenu(ctx, ref, asList);
            return null;
          }),
        },
        child: _body(ctx, ref, asList),
      ),
    );
  }

  String get _here => (crumbs?.isNotEmpty ?? false) ? crumbs!.last.label : locationLabel;

  /// View and Refresh: what every browser has, behind one icon.
  void _showFolderMenu(BuildContext context, WidgetRef ref, bool asList) {
    showRowMenu(context, title: _here, items: [
      RowMenuItem(
        asList ? 'Show as grid' : 'Show as list',
        () => ref.read(browserLayoutProvider.notifier).set(asList ? BrowserLayout.grid : BrowserLayout.list),
        icon: asList ? Icons.grid_view_rounded : Icons.view_list_rounded,
      ),
      RowMenuItem('Refresh', busy ? null : onRefresh, icon: Icons.refresh),
    ]);
  }

  Widget _body(BuildContext context, WidgetRef ref, bool asList) {
    final trail = [
      for (final c in crumbs ?? [Crumb(locationLabel)])
        Crumb(c.label, c.onTap == null ? null : () {
          if (!busy) c.onTap!();
        }),
    ];
    final line = errorLine ?? (error == null ? null : errorReason(error!));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrowserBar(crumbs: trail, actions: barActions, menu: () => _showFolderMenu(context, ref, asList), menuTooltip: 'Folder options'),
        if (transfer != null) Padding(padding: const EdgeInsets.only(top: kitGap), child: _TransferPanel(transfer!)),
        if (queuedSource != null) _QueuedTaskBars(queuedSource!),
        if (line != null) Padding(padding: const EdgeInsets.only(top: kitGap), child: StatusPanel.error(line: line, details: error == line ? null : error)),
        if (busy) const Padding(padding: EdgeInsets.only(top: 4), child: LinearProgressIndicator(minHeight: 3)),
        Expanded(
          child: items.isEmpty && !busy
              ? EmptyState(icon: Icons.folder_open, glyph: PixelIcons.folder, line: emptyLine, action: emptyAction)
              : asList
                  ? ListView.builder(
                      key: ValueKey(locationLabel),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (context, i) => _row(context, items[i], i),
                    )
                  : GridView.builder(
                      key: ValueKey(locationLabel),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
        if (selectedIds.isNotEmpty) _SelectionBar(view: this, onMore: () => _showActions(context, null)),
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

  /// What the selection offers, in order: by default Download, Zip, Delete.
  List<BrowserAction> get _selectionActions =>
      selectionActions ??
      [
        BrowserAction(icon: Icons.download, label: 'Download', onPressed: onDownload),
        BrowserAction(icon: Icons.folder_zip, label: 'Zip', onPressed: onZip),
        BrowserAction(icon: Icons.delete, label: 'Delete', onPressed: onDelete, destructive: true),
      ];

  /// What the selection bar offers right now, plus Clear and the screen extras.
  List<BrowserAction> _sheetActions() {
    final hasSelection = selectedIds.isNotEmpty;
    final all = <BrowserAction>[
      if (hasSelection && transfer == null) ..._selectionActions,
      if (hasSelection) BrowserAction(icon: Icons.close, label: 'Clear selection', onPressed: onClearSelection),
      ...?extraActions?.call(),
    ];
    return [for (final a in all) if (a.onPressed != null) a];
  }

  /// The sheet's title: the one marked entry, how many, or the folder.
  String _sheetTitle() {
    if (selectedIds.isEmpty) return _here;
    if (selectedIds.length > 1) return '${selectedIds.length} selected';
    return items.where((i) => i.id == selectedIds.single).firstOrNull?.name ?? '1 selected';
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
    await showRowMenu(context, title: view._sheetTitle(), items: [
      for (final a in actions) RowMenuItem(a.label, a.onPressed, icon: a.icon, destructive: a.destructive),
    ]);
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

  /// A long press marks an entry (the one touch way to mark a folder besides
  /// its box); it never unmarks, so a slow tap cannot undo a mark.
  VoidCallback? _longPress(BrowserItem e) => selectable && !selectedIds.contains(e.id) ? () => onToggleSelect(e) : null;

  Widget _checkbox(BrowserItem e) => Checkbox(
        value: selectedIds.contains(e.id),
        onChanged: (_) => onToggleSelect(e),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );

  Widget _tile(BuildContext context, BrowserItem e, int index) => _gamepad(context, e, _tileBody(context, e, index));

  Widget _tileBody(BuildContext context, BrowserItem e, int index) {
    final t = KitType.of(context);
    final k = t.k;
    final selected = selectedIds.contains(e.id);
    final radius = BorderRadius.circular(k.panelRadius.clamp(4, 12).toDouble());
    // The checkbox is a sibling above the tile (not an overlay) so the d-pad's
    // Up from the tile reaches it.
    return Column(
      children: [
        if (selectable) Align(alignment: Alignment.centerLeft, child: _checkbox(e)),
        Expanded(
          child: SelectedMark(
            selected: selected,
            radius: radius.topLeft.x,
            size: 18,
            child: Material(
              color: selected ? k.accent.withValues(alpha: 0.16) : k.panel,
              shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: k.panelLine)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                autofocus: index == 0,
                borderRadius: radius,
                onTap: _activate(e),
                onLongPress: _longPress(e),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  child: Column(
                    children: [
                      Icon(e.isDir ? Icons.folder : _fileIcon(e.name), size: 44, color: e.isDir ? k.accent : t.muted),
                      const SizedBox(height: 6),
                      Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: t.body.copyWith(height: 1.2)),
                      if (!e.isDir) Text(_fmtSize(e.size), style: t.subtitle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, BrowserItem e, int index) => _gamepad(context, e, _rowBody(context, e, index));

  Widget _rowBody(BuildContext context, BrowserItem e, int index) {
    final t = KitType.of(context);
    final k = t.k;
    final selected = selectedIds.contains(e.id);
    final detail = e.detail;
    return Row(
      children: [
        if (selectable) _checkbox(e),
        Expanded(
          child: ListTile(
            autofocus: index == 0,
            dense: true,
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(borderRadius: kitRowRadius(k)),
            selected: selected,
            selectedColor: t.ink,
            selectedTileColor: k.accent.withValues(alpha: 0.16),
            leading: Icon(e.isDir ? (detail != null ? Icons.sd_storage_outlined : Icons.folder) : _fileIcon(e.name), color: e.isDir ? k.accent : t.muted),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.row),
            subtitle: detail == null ? null : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle),
            trailing: e.isDir ? null : Text(_fmtSize(e.size), style: t.subtitle),
            onTap: _activate(e),
            onLongPress: _longPress(e),
          ),
        ),
      ],
    );
  }
}

/// While something is marked: how many, Clear, the actions by name and More
/// for the rest (the Y sheet). In portrait the actions take their own row,
/// icon over name, where the thumb is.
class _SelectionBar extends ConsumerWidget {
  const _SelectionBar({required this.view, required this.onMore});

  final FileBrowserView view;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = KitType.of(context);
    final k = t.k;
    final pad = ref.watch(inputModeProvider) == InputMode.gamepad;
    final portrait = DeviceClass.of(context) == DeviceClass.portrait;
    final blocked = view.transfer != null;
    final all = view._selectionActions;
    final shown = [for (final a in all) if (a.inBar) a];
    final more = shown.length < all.length;
    Widget button(String label, IconData icon, VoidCallback? onPressed, {bool destructive = false, Widget? lead}) {
      final color = destructive && onPressed != null ? k.error : null;
      if (portrait) {
        return Expanded(
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(foregroundColor: color, padding: const EdgeInsets.symmetric(vertical: 6), minimumSize: const Size(0, 52)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              lead ?? Icon(icon, size: 22),
              const SizedBox(height: 4),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: TextButton.icon(
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: color),
          icon: lead ?? Icon(icon, size: 18),
          label: Text(label),
        ),
      );
    }

    final buttons = [
      for (final a in shown) button(a.label, a.icon, blocked ? null : a.onPressed, destructive: a.destructive),
      if (more) button('More', Icons.more_horiz, onMore, lead: pad ? const PadKey(PadButton.y) : null),
    ];
    final count = Text('${view.selectedIds.length} selected', style: t.row, maxLines: 1);
    final clear = IconButton(icon: const Icon(Icons.close), tooltip: 'Clear', onPressed: view.onClearSelection, visualDensity: VisualDensity.compact);
    return Padding(
      padding: const EdgeInsets.only(top: kitGap),
      child: KitPanel(
        key: const ValueKey('browser-selection'),
        edge: k.accent.withValues(alpha: 0.5),
        divided: false,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        children: portrait
            ? [
                Row(children: [clear, Expanded(child: count)]),
                Row(children: buttons),
              ]
            : [
                Row(children: [
                  clear,
                  Flexible(child: count),
                  const Spacer(),
                  ...buttons,
                ]),
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
