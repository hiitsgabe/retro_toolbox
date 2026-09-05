import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:roms_downloader/services/m3u_service.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Generates .m3u playlists for multi-disc games in a folder: pick a folder,
/// scan for disc sets, preview, and write one playlist per game.
class M3uScreen extends StatefulWidget {
  const M3uScreen({super.key});

  @override
  State<M3uScreen> createState() => _M3uScreenState();
}

class _M3uScreenState extends State<M3uScreen> {
  final _service = M3uService();
  String? _folder;
  List<DiscSet>? _sets;
  late Set<String> _selected = {};
  bool _busy = false;

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select a folder to scan');
    if (path == null) return;
    setState(() {
      _folder = path;
      _sets = null;
      _selected = {};
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scan() async {
    setState(() => _busy = true);
    try {
      final sets = _service.scanDiscSets(Directory(_folder!));
      setState(() {
        _sets = sets;
        _selected = sets.map((s) => s.base).toSet();
      });
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final chosen = _sets!.where((s) => _selected.contains(s.base)).toList();
    if (chosen.isEmpty) return;
    setState(() => _busy = true);
    try {
      final dir = Directory(_folder!);
      for (final s in chosen) {
        _service.writeM3u(dir, s);
      }
      _snack('${chosen.length} playlist(s) created.');
      await _scan();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sets = _sets;
    return Scaffold(
      appBar: AppBar(title: const Text('M3U Playlists')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ToolDescription(
              icon: Icons.playlist_play,
              text: 'Creates .m3u playlists for multi-disc games so emulators show one entry and '
                  'swap discs in-game. Pick a folder, scan for disc sets, then create the playlists.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_folder ?? 'Choose folder', overflow: TextOverflow.ellipsis),
                  ),
                ),
                if (_folder != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _scan,
                    icon: _busy
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search, size: 16),
                    label: const Text('Scan'),
                  ),
                ],
              ],
            ),
            if (sets != null && sets.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text('No multi-disc games found.', textAlign: TextAlign.center),
              ),
            if (sets != null && sets.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('${_selected.length}/${sets.length} selected', style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _busy || _selected.isEmpty ? null : _create,
                    icon: const Icon(Icons.check, size: 16),
                    label: Text('Create playlists (${_selected.length})'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ...sets.map((s) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _selected.contains(s.base),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => (v ?? false) ? _selected.add(s.base) : _selected.remove(s.base)),
                    title: Text('${s.base}.m3u', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${s.discs.length} discs', maxLines: 1, overflow: TextOverflow.ellipsis),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}
