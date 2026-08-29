import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/nsz_service.dart';

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
  bool _busy = false;
  double _progress = 0;
  String? _result;
  bool _failed = false;

  Future<void> _pickKeys() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select prod.keys or title.keys',
      type: FileType.any,
    );
    final src = result?.files.single.path;
    if (src == null) return;
    // Copy into app support: the picker's temp copy can be cleaned up, and the
    // Python process needs a stable path.
    final supportDir = await getApplicationSupportDirectory();
    final dest = File(p.join(supportDir.path, 'keys', p.basename(src)));
    await dest.parent.create(recursive: true);
    await File(src).copy(dest.path);
    await ref.read(settingsProvider.notifier).setNszKeysPath(dest.path);
  }

  Future<void> _pickNsz() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select an NSZ file',
      type: FileType.custom,
      allowedExtensions: ['nsz'],
    );
    final path = result?.files.single.path;
    if (path != null) setState(() => _nszPath = path);
  }

  Future<void> _pickOutput() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select output folder');
    if (dir != null) setState(() => _outputDir = dir);
  }

  Future<void> _decompress() async {
    final keysPath = ref.read(settingsProvider).nszKeysPath;
    if (_nszPath == null || _outputDir == null || keysPath == null) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _result = null;
      _failed = false;
    });
    try {
      await NszService.decompressNsz(
        nszFilePath: _nszPath!,
        outputDir: _outputDir!,
        keysPath: keysPath,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _result = 'Decompressed to $_outputDir');
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _result = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final canRun = _nszPath != null && _outputDir != null && !_busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fileRow(context, Icons.insert_drive_file_outlined, 'NSZ file',
            _nszPath != null ? p.basename(_nszPath!) : 'No file selected', _busy ? null : _pickNsz),
        const SizedBox(height: 12),
        _fileRow(context, Icons.folder_outlined, 'Output folder',
            _outputDir ?? 'No folder selected', _busy ? null : _pickOutput),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canRun ? _decompress : null,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.compress, size: 18),
            label: Text(_busy ? 'Decompressing…' : 'Decompress'),
          ),
        ),
        if (_busy) ...[
          const SizedBox(height: 16),
          LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          const SizedBox(height: 4),
          Text('${(_progress * 100).toStringAsFixed(0)}%', style: theme.textTheme.bodySmall),
        ],
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
