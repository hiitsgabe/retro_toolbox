import 'dart:io';

import 'package:flutter/material.dart';
import 'package:retro_toolbox/services/m3u_service.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Generates .m3u playlists for multi-disc games in a folder: picking the
/// folder scans it, the disc sets are listed (one already written is marked),
/// and Start writes one playlist per marked game.
class M3uScreen extends StatefulWidget {
  const M3uScreen({super.key});

  @override
  State<M3uScreen> createState() => _M3uScreenState();
}

String _count(int n, String one) => n == 1 ? '1 $one' : '$n ${one}s';

class _M3uScreenState extends State<M3uScreen> {
  final _service = M3uService();
  String? _folder;
  List<DiscSet>? _sets;
  Map<String, PlaylistState> _existing = const {};
  Set<String> _selected = {};
  StatusPanel _status = const StatusPanel.hidden();

  Future<void> _pickFolder() async {
    try {
      final path = await pickDirectory(context, title: 'Select a folder to scan', initialDir: _folder);
      if (path == null || !mounted) return;
      setState(() {
        _folder = path;
        _status = const StatusPanel.hidden();
      });
      _scan();
    } catch (e) {
      if (mounted) setState(() => _status = StatusPanel.error(line: 'Could not open the folder picker', details: '$e'));
    }
  }

  /// Lists the disc sets of the folder. A set whose playlist is already there
  /// as it would be written is shown but not marked.
  void _scan() {
    final folder = _folder;
    if (folder == null) return;
    try {
      final dir = Directory(folder);
      final sets = _service.scanDiscSets(dir);
      final existing = {for (final s in sets) s.base: _service.playlistState(dir, s)};
      setState(() {
        _sets = sets;
        _existing = existing;
        _selected = {for (final s in sets) if (existing[s.base] != PlaylistState.same) s.base};
      });
    } catch (e) {
      setState(() {
        _sets = null;
        _status = StatusPanel.error(line: 'Could not read that folder', details: '$e');
      });
    }
  }

  void _create() {
    final folder = _folder, sets = _sets;
    if (folder == null || sets == null) return;
    final chosen = sets.where((s) => _selected.contains(s.base)).toList();
    if (chosen.isEmpty) return;
    final dir = Directory(folder);
    var made = 0;
    final problems = <Problem>[];
    for (final s in chosen) {
      try {
        _service.writeM3u(dir, s);
        made++;
      } catch (e) {
        problems.add(Problem('${s.base}.m3u', '$e'.split('\n').first, failed: true));
      }
    }
    setState(() {
      _status = made == 0
          ? StatusPanel.error(line: 'Could not write the playlists', details: problems.map((p) => '${p.name}: ${p.reason}').join('\n'))
          : StatusPanel.done(summary: 'Created ${_count(made, 'playlist')} in ${pathParts(folder).join(pathSeparator)}', problems: problems);
    });
    // The written sets now read as already there.
    _scan();
  }

  static const _info = InfoButton(
    icon: Icons.playlist_play,
    title: 'M3U Playlists',
    text: 'Creates .m3u playlists for multi-disc games so emulators show one entry and swap discs in-game. '
        'Files named like (Disc 1), (Disc 2) become one playlist. Picking a folder scans it; subfolders are not scanned.\n\n'
        'A game whose playlist is already there with the same discs is marked Exists. A playlist with the same name but other discs is replaced.',
  );

  @override
  Widget build(BuildContext context) {
    final folder = _folder, sets = _sets;
    final selectable = sets == null ? 0 : sets.where((s) => _existing[s.base] != PlaylistState.same).length;
    final n = _selected.length;
    final String summary;
    if (folder == null) {
      summary = 'Pick a folder';
    } else if (sets == null || sets.isEmpty) {
      summary = 'No disc sets';
    } else if (selectable == 0) {
      summary = 'Every playlist is there';
    } else {
      summary = '$n of $selectable marked';
    }
    final rows = [
      for (final s in sets ?? const <DiscSet>[])
        switch (_existing[s.base]) {
          PlaylistState.same => ResultRow(id: s.base, title: '${s.base}.m3u', subtitle: _discs(s), badge: 'Exists', selectable: false),
          PlaylistState.different => ResultRow(id: s.base, title: '${s.base}.m3u', subtitle: _discs(s), badge: 'Replace', badgeTone: KitTone.warning),
          _ => ResultRow(id: s.base, title: '${s.base}.m3u', subtitle: _discs(s), badge: 'New', badgeTone: KitTone.accent),
        },
    ];
    return KitScaffold(
      title: 'M3U Playlists',
      subtitle: 'One playlist per multi-disc game',
      icon: Icons.playlist_play,
      glyph: PixelIcons.m3u,
      area: AppArea.tools,
      info: _info,
      body: KitColumns(
        fillEnd: true,
        start: [
          const KitLabel('Folder'),
          KitPanel(children: [
            Slot(label: 'Folder', folder: true, path: folder, emptyText: 'Choose the folder with the discs', onPick: _pickFolder, autofocus: true),
          ]),
          _status,
        ],
        end: [
          ResultsList(
            groups: [ResultGroup('Multi-disc games', rows)],
            selected: _selected,
            onSelectionChanged: (s) => setState(() => _selected = s),
            empty: EmptyState(
              icon: Icons.playlist_play,
              glyph: PixelIcons.m3u,
              line: folder == null ? 'Pick the folder with the discs' : 'No multi-disc games in this folder. Subfolders are not scanned.',
            ),
          ),
        ],
      ),
      actionBar: ActionBar(
        primary: KitAction(n == 0 ? 'Create playlists' : 'Create ${_count(n, 'playlist')}', n == 0 ? null : _create, icon: Icons.playlist_add_check),
        secondary: KitAction('Scan again', folder == null ? null : _scan, icon: Icons.refresh, button: PadButton.x),
        hints: const [KitHint(PadButton.a, 'Mark'), KitHint(PadButton.select, 'All'), KitHint(PadButton.b, 'Back')],
        summary: summary,
      ),
    );
  }

  static String _discs(DiscSet s) => '${s.discs.length} discs: ${s.discs.join(', ')}';
}
