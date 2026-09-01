import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/task_queue_model.dart';
import 'package:roms_downloader/providers/game_state_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/widgets/common/path_browser.dart';

/// Standalone NSZ→NSP decompression: pick a .nsz, an output folder, and run.
/// Requires prod.keys — the UI blocks with a keys picker until one is set.
class NszDecompressScreen extends ConsumerStatefulWidget {
  const NszDecompressScreen({super.key});

  @override
  ConsumerState<NszDecompressScreen> createState() => _NszDecompressScreenState();
}

class _NszDecompressScreenState extends ConsumerState<NszDecompressScreen> {
  String? _nszPath;
  String? _outputDir;
  String? _result;
  bool _failed = false;

  /// Where the in-app browser opens. Prefers whatever the user already chose,
  /// then the download dir, so the .nsz sitting next to the ROMs is one tap away.
  Future<String> _browseRoot() async {
    if (_outputDir != null) return _outputDir!;
    if (_nszPath != null) return p.dirname(_nszPath!);
    return DirectoryService().getDownloadDir();
  }

  void _showPickError(Object e) {
    if (!mounted) return;
    setState(() {
      _failed = true;
      _result = '$e';
    });
  }

  Future<void> _pickKeys() async {
    try {
      // Keys files are a few hundred KB, so the SAF picker's cache copy is
      // harmless here — unlike for the .nsz below.
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select prod.keys or title.keys',
        type: FileType.any,
      );
      final src = result?.files.firstOrNull?.path;
      if (src == null) return;
      // Copy into app support: the picker's temp copy can be cleaned up, and the
      // Python process needs a stable path.
      final supportDir = await getApplicationSupportDirectory();
      final dest = File(p.join(supportDir.path, 'keys', p.basename(src)));
      await dest.parent.create(recursive: true);
      await File(src).copy(dest.path);
      await ref.read(settingsProvider.notifier).setNszKeysPath(dest.path);
    } catch (e) {
      _showPickError(e);
    }
  }

  Future<void> _pickNsz() async {
    try {
      String? path;
      if (Platform.isAndroid) {
        final root = await _browseRoot();
        if (!mounted) return;
        path = await PathBrowser.show(
          context,
          title: 'Select an NSZ file',
          initialDir: root,
          allowedExtensions: const ['nsz'],
        );
      } else {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select an NSZ file',
          type: FileType.custom,
          allowedExtensions: ['nsz'],
        );
        path = result?.files.firstOrNull?.path;
      }
      if (path == null || !mounted) return;
      setState(() {
        _nszPath = path;
        // Decompressing next to the source is almost always what's wanted, and
        // it saves a second pick.
        _outputDir ??= p.dirname(path!);
        _result = null;
        _failed = false;
      });
    } catch (e) {
      _showPickError(e);
    }
  }

  Future<void> _pickOutput() async {
    try {
      // The SAF directory picker is fine on Android: it resolves the tree URI to
      // a real path without copying anything, and MANAGE_EXTERNAL_STORAGE makes
      // that path writable. Only the *file* picker has to be avoided.
      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select output folder');
      if (dir == null || !mounted) return;
      setState(() {
        _outputDir = dir;
        _result = null;
        _failed = false;
      });
    } catch (e) {
      _showPickError(e);
    }
  }

  /// Hand the decompression to the task queue so it runs in the background and
  /// shows in the task list — the user can leave this screen and keep browsing.
  void _enqueueDecompress() {
    final keysPath = ref.read(settingsProvider).nszKeysPath;
    if (_nszPath == null || _outputDir == null || keysPath == null) return;

    // Register a transient game so the task shows in the task manager. The
    // gameId (not the raw path) is the task key, and nszFilePath carries the
    // real path, so the two never disagree.
    final name = p.basename(_nszPath!);
    int size = 0;
    try {
      size = File(_nszPath!).lengthSync();
    } catch (_) {}
    final game = Game(title: name, url: 'https://manual/${Uri.encodeComponent(name)}', size: size, consoleId: 'manual');
    final taskId = game.gameId;
    ref.read(gameStateManagerProvider.notifier).registerTransientGame(game);

    ref.read(taskQueueProvider.notifier).enqueue(taskId, TaskType.nszDecompression, {
      'taskId': taskId,
      'nszFilePath': _nszPath!,
      'outputDir': _outputDir!,
      'keysPath': keysPath,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Decompression added to the task list')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final keysPath = ref.watch(settingsProvider).nszKeysPath;
    final hasKeys = keysPath != null && keysPath.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('NSZ Decompress')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: hasKeys ? _decompressUi(context) : _keysWarning(context),
      ),
    );
  }

  Widget _keysWarning(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('prod.keys required', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                'NSZ decompression needs your console keys (prod.keys or title.keys). '
                'Select the file to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _pickKeys,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Select keys file'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _decompressUi(BuildContext context) {
    final theme = Theme.of(context);
    final canRun = _nszPath != null && _outputDir != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fileRow(context, Icons.insert_drive_file_outlined, 'NSZ file',
            _nszPath != null ? p.basename(_nszPath!) : 'No file selected', _pickNsz),
        const SizedBox(height: 12),
        _fileRow(context, Icons.folder_outlined, 'Output folder',
            _outputDir ?? 'No folder selected', _pickOutput),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canRun ? _enqueueDecompress : null,
            icon: const Icon(Icons.compress, size: 18),
            label: const Text('Add to task list'),
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
    );
  }

  Widget _fileRow(BuildContext context, IconData icon, String label, String value, VoidCallback? onPick) {
    final theme = Theme.of(context);
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
