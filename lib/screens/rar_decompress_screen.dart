import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Standalone archive extraction: pick a .rar or .zip and an output folder,
/// then extract. The work runs as a background task (task manager + Android
/// notification, with progress), so the user can leave this screen.
class RarDecompressScreen extends ConsumerStatefulWidget {
  const RarDecompressScreen({super.key});

  @override
  ConsumerState<RarDecompressScreen> createState() => _RarDecompressScreenState();
}

class _RarDecompressScreenState extends ConsumerState<RarDecompressScreen> {
  String? _archivePath;
  String? _outputDir;
  String? _result;
  bool _failed = false;

  Future<String> _browseRoot() async {
    if (_outputDir != null) return _outputDir!;
    if (_archivePath != null) return p.dirname(_archivePath!);
    return DirectoryService().getDownloadDir();
  }

  void _setError(Object e) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _result = '$e';
    });
  }

  Future<void> _pickArchive() async {
    try {
      String? path;
      if (Platform.isAndroid) {
        // Mirror NSZ: the SAF file picker copies the pick into cache, which is
        // wasteful for large archives — browse the real path instead.
        final root = await _browseRoot();
        if (!mounted) return;
        path = await PathBrowser.show(
          context,
          title: 'Select a .rar or .zip file',
          initialDir: root,
          allowedExtensions: const ['rar', 'zip'],
        );
      } else {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select a .rar or .zip file',
          type: FileType.custom,
          allowedExtensions: ['rar', 'zip'],
        );
        path = result?.files.firstOrNull?.path;
      }
      if (path == null || !mounted) return;
      setState(() {
        _archivePath = path;
        _outputDir ??= p.dirname(path!);
        _result = null;
        _failed = false;
      });
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> _pickOutput() async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select output folder');
      if (dir == null || !mounted) return;
      setState(() {
        _outputDir = dir;
        _result = null;
        _failed = false;
      });
    } catch (e) {
      _setError(e);
    }
  }

  /// Hand the extraction to the task queue so it runs in the background and
  /// shows in the task list — the user can leave this screen and keep browsing.
  void _extract() {
    final archive = _archivePath, out = _outputDir;
    if (archive == null || out == null) return;
    if (ArchiveExtractService.archiveKind(archive) == ArchiveKind.rar && !ArchiveExtractService.rarSupported()) {
      _setError(UnsupportedError('RAR extraction is not supported on this platform yet.'));
      return;
    }

    // A transient game gives the task a row in the task manager; its id is the
    // task key and archivePath carries the real path.
    final name = p.basename(archive);
    int size = 0;
    try {
      size = File(archive).lengthSync();
    } catch (_) {}
    final game = Game(title: name, url: 'https://manual/${Uri.encodeComponent(name)}', size: size, consoleId: 'manual');
    ref.read(gameStateManagerProvider.notifier).registerTransientGame(game);
    ref.read(taskQueueProvider.notifier).enqueue(game.gameId, TaskType.archiveExtraction, {
      'taskId': game.gameId,
      'archivePath': archive,
      'outputDir': out,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Extraction added to the task list')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRun = _archivePath != null && _outputDir != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Rar Decompress')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ToolDescription(
              icon: Icons.folder_zip_outlined,
              text: 'Extracts .rar and .zip archives to a folder. Pick an archive and an output '
                  'folder, then extract. RAR support is available on Android and macOS.',
            ),
            const SizedBox(height: 16),
            _fileRow(theme, Icons.insert_drive_file_outlined, 'Archive',
                _archivePath != null ? p.basename(_archivePath!) : 'No file selected', _pickArchive),
            const SizedBox(height: 12),
            _fileRow(theme, Icons.folder_outlined, 'Output folder',
                _outputDir ?? 'No folder selected', _pickOutput),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canRun ? _extract : null,
                icon: const Icon(Icons.unarchive, size: 18),
                label: const Text('Extract'),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(_failed ? Icons.error_outline : Icons.check_circle,
                      color: _failed ? theme.colorScheme.error : Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_result!, style: TextStyle(color: _failed ? theme.colorScheme.error : null))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fileRow(ThemeData theme, IconData icon, String label, String value, VoidCallback? onPick) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                Text(value, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis, maxLines: 1),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: onPick, child: const Text('Choose')),
        ],
      ),
    );
  }
}
