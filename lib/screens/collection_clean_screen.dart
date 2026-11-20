import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/services/collection_clean_service.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Folder-scoped cleanup ported from console_utilities: dedupe game files,
/// clean up filenames, and remove OS junk ("ghost") files. Picking a folder
/// scans it for all three; the findings are listed by cleanup with a mark
/// each, and Start applies the marked ones after a confirmation.
class CollectionCleanScreen extends StatefulWidget {
  const CollectionCleanScreen({super.key});

  /// "Renamed 3, skipped 2 (name already exists)." Skips are grouped by reason
  /// so a collision never reads as a rename that happened.
  static String renameSummary(RenameResult result) {
    final skipped = result.skipped;
    if (skipped.isEmpty) return 'Renamed ${result.renamed}.';
    final byReason = <String, int>{};
    for (final s in skipped) {
      byReason[s.reason] = (byReason[s.reason] ?? 0) + 1;
    }
    final why = byReason.length == 1 ? byReason.keys.single : byReason.entries.map((e) => '${e.value} ${e.key}').join(', ');
    return 'Renamed ${result.renamed}, skipped ${skipped.length} ($why).';
  }

  @override
  State<CollectionCleanScreen> createState() => _CollectionCleanScreenState();
}

/// The three cleanups, in the order they are applied: deleting first, so a
/// rename never runs on a file that is about to go.
enum _Clean {
  dedupe('Dedupe Games'),
  ghosts('Ghost File Cleaner'),
  rename('Clean File Names');

  const _Clean(this.title);

  final String title;
}

/// One finding: what it is about, and the rename's new name.
class _Item {
  const _Item(this.kind, this.path, this.title, this.subtitle, {this.to});

  final _Clean kind;
  final String path;
  final String title;
  final String subtitle;
  final String? to;

  String get id => '${kind.name}:$path';
}

String _count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

class _CollectionCleanScreenState extends State<CollectionCleanScreen> {
  final _service = CollectionCleanService();
  String? _folder;
  bool _scanning = false;
  List<_Item>? _items;
  Set<String> _selected = {};
  StatusPanel _status = const StatusPanel.hidden();

  Future<void> _pickFolder() async {
    try {
      final path = await pickDirectory(context, title: 'Select a folder to clean', initialDir: _folder);
      if (path == null || !mounted) return;
      setState(() {
        _folder = path;
        _items = null;
        _status = const StatusPanel.hidden();
      });
      await _scan();
    } catch (e) {
      if (mounted) setState(() => _status = StatusPanel.error(line: 'Could not open the folder picker', details: '$e'));
    }
  }

  /// Every cleanup at once, off the UI thread. Everything found is marked.
  Future<void> _scan() async {
    final folder = _folder;
    if (folder == null || _scanning) return;
    setState(() => _scanning = true);
    try {
      final (dupes, renames, ghosts) = await (
        compute(CollectionCleanService.scanDuplicatesPath, folder),
        compute(CollectionCleanService.scanRenamesPath, folder),
        compute(CollectionCleanService.scanGhostsPath, folder),
      ).wait;
      final items = [
        for (final d in dupes) _Item(_Clean.dedupe, d.path, _basename(d.path), '${_fmtSize(d.size)} · duplicate'),
        for (final g in ghosts) _Item(_Clean.ghosts, g.path, g.name, '${g.isDir ? 'folder' : 'file'} · ${_fmtSize(g.size)}'),
        for (final r in renames) _Item(_Clean.rename, r.path, r.from, '→ ${r.to}', to: r.to),
      ];
      if (!mounted || folder != _folder) return;
      setState(() {
        _items = items;
        _selected = {for (final i in items) i.id};
      });
    } catch (e) {
      if (mounted) setState(() => _status = StatusPanel.error(line: 'Could not read that folder', details: e is ParallelWaitError ? '${e.errors}' : '$e'));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  List<_Item> _marked(_Clean kind) => [for (final i in _items ?? const <_Item>[]) if (i.kind == kind && _selected.contains(i.id)) i];

  /// "Delete 2 duplicates and rename 4 files": what Start is about to do.
  String _plan() {
    final parts = [
      if (_marked(_Clean.dedupe).isNotEmpty) 'delete ${_count(_marked(_Clean.dedupe).length, 'duplicate')}',
      if (_marked(_Clean.ghosts).isNotEmpty) 'delete ${_count(_marked(_Clean.ghosts).length, 'junk item')}',
      if (_marked(_Clean.rename).isNotEmpty) 'rename ${_count(_marked(_Clean.rename).length, 'file')}',
    ];
    final text = parts.length < 2 ? parts.join() : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';
  }

  Future<void> _apply() async {
    final folder = _folder;
    if (folder == null || _selected.isEmpty || _scanning) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Collection Clean'),
        content: Text('${_plan()}? This cannot be undone.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final dir = Directory(folder);
    final dupes = _marked(_Clean.dedupe), ghosts = _marked(_Clean.ghosts);
    final gone = {for (final i in [...dupes, ...ghosts]) i.path};
    final renames = [for (final i in _marked(_Clean.rename)) if (!gone.contains(i.path)) (path: i.path, from: i.title, to: i.to!)];
    try {
      final lines = <String>[];
      if (dupes.isNotEmpty) lines.add('Deleted ${_count(_service.applyDelete(dir, dupes.map((i) => i.path)), 'duplicate')}.');
      if (ghosts.isNotEmpty) lines.add('Deleted ${_count(_service.applyDelete(dir, ghosts.map((i) => i.path)), 'junk item')}.');
      RenameResult? renamed;
      if (renames.isNotEmpty) {
        renamed = _service.applyRenames(dir, renames);
        lines.add(CollectionCleanScreen.renameSummary(renamed));
      }
      setState(() {
        _status = StatusPanel.done(
          summary: lines.join(' '),
          problems: [for (final s in renamed?.skipped ?? const <RenameSkip>[]) Problem(s.entry.from, s.reason)],
        );
      });
    } catch (e) {
      setState(() => _status = StatusPanel.error(line: 'Could not apply the changes', details: '$e'));
    }
    await _scan();
  }

  static const _info = InfoButton(
    icon: Icons.cleaning_services,
    title: 'Collection Clean',
    text: 'Tidy up a game folder: remove duplicate ROMs, strip tags from filenames, and delete OS junk files. '
        'Picking a folder scans it for all three; nothing changes until you apply the marked items.\n\n'
        'Dedupe Games finds game files that match after stripping region/version tags and keeps the largest copy of each. '
        'Marked duplicates are deleted.\n\n'
        'Clean File Names removes (parenthetical) and [bracketed] tags from game filenames and collapses extra spaces. '
        'A new name that is already taken is skipped.\n\n'
        'Ghost File Cleaner finds OS junk (.DS_Store, ._* files, __MACOSX, Thumbs.db, desktop.ini) anywhere under the folder. '
        'Marked items are deleted.',
  );

  @override
  Widget build(BuildContext context) {
    final folder = _folder, items = _items;
    final n = _selected.length;
    // A result stays up through the rescan that follows it.
    final status = _scanning && _status.isHidden ? StatusPanel.working(items: [WorkItem('Scanning ${_basename(folder ?? '')}')]) : _status;
    final groups = [
      for (final kind in _Clean.values)
        ResultGroup(kind.title, [
          for (final i in items ?? const <_Item>[])
            if (i.kind == kind)
              ResultRow(
                id: i.id,
                title: i.title,
                subtitle: i.subtitle,
                badge: kind == _Clean.rename ? 'Rename' : 'Delete',
                badgeTone: kind == _Clean.rename ? KitTone.accent : KitTone.error,
              ),
        ]),
    ];
    final String empty;
    if (folder == null) {
      empty = 'Pick a folder to enable cleanup.';
    } else if (items == null) {
      empty = _scanning ? 'Scanning the folder' : 'Scan the folder to see what can be cleaned';
    } else {
      empty = 'Nothing to clean in this folder.';
    }
    return KitScaffold(
      title: 'Collection Clean',
      subtitle: 'Duplicates, tags in names and OS junk',
      icon: Icons.cleaning_services,
      glyph: PixelIcons.clean,
      area: AppArea.tools,
      info: _info,
      body: KitColumns(
        fillEnd: true,
        start: [
          const KitLabel('Folder'),
          KitPanel(children: [
            Slot(label: 'Folder', folder: true, path: folder, emptyText: 'Choose folder', onPick: _scanning ? null : _pickFolder, autofocus: true),
          ]),
          status,
        ],
        end: [
          ResultsList(
            groups: groups,
            selected: _selected,
            onSelectionChanged: _scanning ? null : (s) => setState(() => _selected = s),
            empty: EmptyState(icon: Icons.cleaning_services, glyph: PixelIcons.clean, line: empty),
          ),
        ],
      ),
      actionBar: ActionBar(
        primary: KitAction(n == 0 ? 'Apply changes' : 'Apply ${_count(n, 'change')}', n == 0 || _scanning ? null : _apply, icon: Icons.check),
        secondary: KitAction('Scan again', folder == null || _scanning ? null : _scan, icon: Icons.refresh, button: PadButton.x),
        hints: const [KitHint(PadButton.a, 'Mark'), KitHint(PadButton.select, 'All'), KitHint(PadButton.b, 'Back')],
        summary: items == null ? (folder == null ? 'Pick a folder' : null) : (n == 0 ? 'Nothing marked' : '$n of ${items.length} marked'),
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
