import 'package:flutter/material.dart';

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

/// Finder-style file browser: toolbar + icon grid + multi-select action bar +
/// transfer bar. Presentation only — the parent owns the connection, supplies
/// [items]/[selectedIds]/[transfer] and reacts to the callbacks. Shared by the
/// SMB and FTP screens so both look identical.
class FileBrowserView extends StatelessWidget {
  final String locationLabel;
  final bool canGoUp;
  final bool busy;
  final String? error;
  final List<BrowserItem> items;
  final Set<String> selectedIds;
  final BrowserTransfer? transfer;

  /// When false, tapping an item opens it (no selection) — e.g. the SMB shares
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

  const FileBrowserView({
    super.key,
    required this.locationLabel,
    required this.canGoUp,
    required this.busy,
    this.error,
    required this.items,
    required this.selectedIds,
    this.transfer,
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Material(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_upward), tooltip: 'Up', onPressed: canGoUp && !busy ? onUp : null),
              Expanded(child: Text(locationLabel, style: const TextStyle(fontFamily: 'monospace'), overflow: TextOverflow.ellipsis)),
              ...toolbarActions,
              IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: busy ? null : onRefresh),
            ],
          ),
        ),
        if (transfer != null) _transferBar(context, transfer!),
        if (error != null) Padding(padding: const EdgeInsets.all(12), child: Text(error!, style: TextStyle(color: theme.colorScheme.error))),
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: items.isEmpty && !busy
              ? const Center(child: Text('Empty'))
              // Short screens: a dense list fits several times more entries
              // than the icon grid.
              : MediaQuery.sizeOf(context).height < 640
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _row(context, items[i]),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 132,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _tile(context, items[i]),
                ),
        ),
        if (selectedIds.isNotEmpty) _selectionBar(context),
      ],
    );
  }

  Widget _tile(BuildContext context, BrowserItem e) {
    final theme = Theme.of(context);
    final selected = selectedIds.contains(e.id);
    return GestureDetector(
      onTap: () => selectable ? onToggleSelect(e) : onOpen(e),
      onDoubleTap: e.isDir && selectable && !busy ? () => onOpen(e) : null,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.topRight,
              children: [
                Icon(e.isDir ? Icons.folder : _fileIcon(e.name), size: 48, color: e.isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                if (selected) Icon(Icons.check_circle, size: 18, color: theme.colorScheme.primary),
              ],
            ),
            const SizedBox(height: 6),
            Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            if (!e.isDir) Text(_fmtSize(e.size), style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, BrowserItem e) {
    final theme = Theme.of(context);
    final selected = selectedIds.contains(e.id);
    return GestureDetector(
      onDoubleTap: e.isDir && selectable && !busy ? () => onOpen(e) : null,
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer,
        leading: Icon(e.isDir ? Icons.folder : _fileIcon(e.name), color: e.isDir ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: selected
            ? Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20)
            : (e.isDir ? null : Text(_fmtSize(e.size), style: theme.textTheme.labelSmall)),
        onTap: () => selectable ? onToggleSelect(e) : onOpen(e),
      ),
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
