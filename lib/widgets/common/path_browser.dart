import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

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
    this.directoriesOnly = false,
    this.allowedExtensions,
  });

  final String title;
  final String initialDir;
  final bool directoriesOnly;

  /// Lowercase, no leading dot. Null shows every file.
  final List<String>? allowedExtensions;

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String initialDir,
    bool directoriesOnly = false,
    List<String>? allowedExtensions,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => PathBrowser(
        title: title,
        initialDir: initialDir,
        directoriesOnly: directoriesOnly,
        allowedExtensions: allowedExtensions,
      ),
    );
  }

  @override
  State<PathBrowser> createState() => _PathBrowserState();
}

class _PathBrowserState extends State<PathBrowser> {
  late String _dir;
  List<Directory> _dirs = [];
  List<File> _files = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _dir = widget.initialDir;
    _load(_dir);
  }

  bool _allowed(File f) {
    final exts = widget.allowedExtensions;
    if (exts == null) return true;
    final ext = p.extension(f.path).toLowerCase();
    return ext.isNotEmpty && exts.contains(ext.substring(1));
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await Directory(path).list(followLinks: false).toList();
      final dirs = entries.whereType<Directory>().toList();
      final files = widget.directoriesOnly ? <File>[] : entries.whereType<File>().where(_allowed).toList();
      int byName(FileSystemEntity a, FileSystemEntity b) => p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      dirs.sort(byName);
      files.sort(byName);
      if (!mounted) return;
      setState(() {
        _dir = path;
        _dirs = dirs;
        _files = files;
        _loading = false;
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
            const Divider(height: 1),
            Flexible(child: _body(theme, canGoUp, parent)),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  if (widget.directoriesOnly) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, _dir),
                      child: const Text('Use this folder'),
                    ),
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
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
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
    return ListView(
      shrinkWrap: true,
      children: [
        if (canGoUp)
          ListTile(
            dense: true,
            leading: const Icon(Icons.arrow_upward, size: 20),
            title: const Text('..'),
            onTap: () => _load(parent),
          ),
        for (final d in _dirs)
          ListTile(
            dense: true,
            leading: const Icon(Icons.folder_outlined, size: 20),
            title: Text(p.basename(d.path), overflow: TextOverflow.ellipsis, maxLines: 1),
            onTap: () => _load(d.path),
          ),
        for (final f in _files)
          ListTile(
            dense: true,
            leading: const Icon(Icons.insert_drive_file_outlined, size: 20),
            title: Text(p.basename(f.path), overflow: TextOverflow.ellipsis, maxLines: 1),
            onTap: () => Navigator.pop(context, f.path),
          ),
        if (empty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.allowedExtensions == null ? 'Empty folder' : 'No matching files here',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
