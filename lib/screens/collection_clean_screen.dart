import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:roms_downloader/services/collection_clean_service.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Folder-scoped cleanup ported from console_utilities: dedupe game files,
/// clean up filenames, and remove OS junk ("ghost") files. Each operation
/// scans, previews with per-item checkboxes, then applies on confirmation.
class CollectionCleanScreen extends StatefulWidget {
  const CollectionCleanScreen({super.key});

  @override
  State<CollectionCleanScreen> createState() => _CollectionCleanScreenState();
}

class _CollectionCleanScreenState extends State<CollectionCleanScreen> {
  final _service = CollectionCleanService();
  String? _folder;

  Directory? get _dir => _folder == null ? null : Directory(_folder!);

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select a folder to clean');
    if (path != null) setState(() => _folder = path);
  }

  @override
  Widget build(BuildContext context) {
    final dir = _dir;
    return Scaffold(
      appBar: AppBar(title: const Text('Collection Clean')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ToolDescription(
              icon: Icons.cleaning_services,
              text: 'Tidy up a game folder: remove duplicate ROMs, strip tags from filenames, '
                  'and delete OS junk files. Pick a folder, then scan and preview each cleanup '
                  'before applying it.',
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open),
              label: Text(_folder ?? 'Choose folder'),
            ),
            if (dir == null)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('Pick a folder to enable cleanup.', textAlign: TextAlign.center),
              )
            else ...[
              const SizedBox(height: 16),
              _CleanSection(
                title: 'Dedupe Games',
                icon: Icons.copy_all,
                description: 'Finds game files that match after stripping region/version tags and keeps '
                    'the largest copy of each. Selected duplicates are deleted.',
                applyLabel: 'Delete selected',
                scan: () async => (await compute(CollectionCleanService.scanDuplicatesPath, dir.path))
                    .map((d) => CleanRow(
                          path: d.path,
                          title: _basename(d.path),
                          subtitle: '${_fmtSize(d.size)} — duplicate',
                        ))
                    .toList(),
                apply: (rows) async => _service.applyDelete(dir, rows.map((r) => r.path)),
              ),
              _CleanSection(
                title: 'Clean File Names',
                icon: Icons.drive_file_rename_outline,
                description: 'Removes (parenthetical) and [bracketed] tags from game filenames and '
                    'collapses extra spaces. Selected files are renamed.',
                applyLabel: 'Rename selected',
                scan: () async => (await compute(CollectionCleanService.scanRenamesPath, dir.path))
                    .map((r) => CleanRow(
                          path: r.path,
                          title: r.from,
                          subtitle: '→ ${r.to}',
                          to: r.to,
                        ))
                    .toList(),
                apply: (rows) async => _service.applyRenames(
                  dir,
                  rows.map<RenameEntry>((r) => (path: r.path, from: r.title, to: r.to!)).toList(),
                ),
              ),
              _CleanSection(
                title: 'Ghost File Cleaner',
                icon: Icons.cleaning_services,
                description: 'Finds OS junk (.DS_Store, ._* files, __MACOSX, Thumbs.db, desktop.ini) '
                    'anywhere under the folder. Selected items are deleted.',
                applyLabel: 'Delete selected',
                scan: () async => (await compute(CollectionCleanService.scanGhostsPath, dir.path))
                    .map((g) => CleanRow(
                          path: g.path,
                          title: g.name,
                          subtitle: '${g.isDir ? 'folder' : 'file'} — ${_fmtSize(g.size)}',
                        ))
                    .toList(),
                apply: (rows) async => _service.applyDelete(dir, rows.map((r) => r.path)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CleanRow {
  final String path;
  final String title;
  final String subtitle;
  final String? to;
  bool selected;
  CleanRow({required this.path, required this.title, required this.subtitle, this.to, this.selected = true});
}

class _CleanSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final String description;
  final String applyLabel;
  final Future<List<CleanRow>> Function() scan;
  final Future<int> Function(List<CleanRow> selected) apply;

  const _CleanSection({
    required this.title,
    required this.icon,
    required this.description,
    required this.applyLabel,
    required this.scan,
    required this.apply,
  });

  @override
  State<_CleanSection> createState() => _CleanSectionState();
}

class _CleanSectionState extends State<_CleanSection> {
  List<CleanRow>? _rows;
  bool _busy = false;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      final rows = await widget.scan();
      if (mounted) setState(() => _rows = rows);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setAll(List<CleanRow> rows, bool value) {
    setState(() {
      for (final r in rows) {
        r.selected = value;
      }
    });
  }

  Future<void> _apply() async {
    final selected = _rows!.where((r) => r.selected).toList();
    if (selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final n = await widget.apply(selected);
      _snack('${widget.title}: $n item(s) processed.');
      await _scan();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(widget.icon, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600))),
                TextButton.icon(
                  onPressed: _busy ? null : _scan,
                  icon: _busy
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.search, size: 16),
                  label: const Text('Scan'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ToolDescription(icon: widget.icon, text: widget.description),
            if (rows != null && rows.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Nothing found.')),
            if (rows != null && rows.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Actions pinned above the list so they stay reachable on huge lists.
              Row(
                children: [
                  Text('${rows.where((r) => r.selected).length}/${rows.length} selected',
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : () => _setAll(rows, !rows.every((r) => r.selected)),
                    child: Text(rows.every((r) => r.selected) ? 'None' : 'All'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy || !rows.any((r) => r.selected) ? null : _apply,
                    icon: const Icon(Icons.check, size: 16),
                    label: Text('${widget.applyLabel} (${rows.where((r) => r.selected).length})'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: (rows.length * 56.0).clamp(56.0, 320.0),
                child: ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: r.selected,
                      onChanged: _busy ? null : (v) => setState(() => r.selected = v ?? false),
                      title: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(r.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
