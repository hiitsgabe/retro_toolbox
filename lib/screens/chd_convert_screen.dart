import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/game_model.dart';
import 'package:roms_downloader/models/task_queue_model.dart';
import 'package:roms_downloader/providers/game_state_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/services/chd_service.dart';
import 'package:roms_downloader/services/directory_service.dart';
import 'package:roms_downloader/widgets/common/path_browser.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Convert disc images to/from CHD via chdman. Compresses .cue/.gdi/.iso and
/// extracts .chd back. Blocks with a "chdman required" card until a binary is
/// resolvable (a user-set path, a bundled asset, or one on PATH).
class ChdConvertScreen extends ConsumerStatefulWidget {
  const ChdConvertScreen({super.key});

  @override
  ConsumerState<ChdConvertScreen> createState() => _ChdConvertScreenState();
}

class _ChdConvertScreenState extends ConsumerState<ChdConvertScreen> {
  String? _inputPath;
  String? _outputDir;
  bool? _chdmanReady;

  @override
  void initState() {
    super.initState();
    _checkChdman();
  }

  Future<void> _checkChdman() async {
    final ready = await ChdService.isAvailable(ref.read(settingsProvider).chdmanPath);
    if (mounted) setState(() => _chdmanReady = ready);
  }

  Future<String> _browseRoot() async {
    if (_outputDir != null) return _outputDir!;
    if (_inputPath != null) return p.dirname(_inputPath!);
    return DirectoryService().getDownloadDir();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickChdman() async {
    try {
      final result = await FilePicker.platform.pickFiles(dialogTitle: 'Select the chdman binary');
      final path = result?.files.firstOrNull?.path;
      if (path == null) return;
      await ref.read(settingsProvider.notifier).setChdmanPath(path);
      ChdService.debugReset();
      await _checkChdman();
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _pickInput() async {
    try {
      String? path;
      const exts = ['cue', 'gdi', 'toc', 'iso', 'chd'];
      if (Platform.isAndroid) {
        final root = await _browseRoot();
        if (!mounted) return;
        path = await PathBrowser.show(context, title: 'Select a disc image', initialDir: root, allowedExtensions: exts);
      } else {
        final result = await FilePicker.platform.pickFiles(
          dialogTitle: 'Select a disc image',
          type: FileType.custom,
          allowedExtensions: exts,
        );
        path = result?.files.firstOrNull?.path;
      }
      if (path == null || !mounted) return;
      setState(() {
        _inputPath = path;
        _outputDir ??= p.dirname(path!);
      });
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _pickOutput() async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select output folder');
    if (dir == null || !mounted) return;
    setState(() => _outputDir = dir);
  }

  void _enqueue() {
    if (_inputPath == null || _outputDir == null) return;
    final name = p.basename(_inputPath!);
    int size = 0;
    try {
      size = File(_inputPath!).lengthSync();
    } catch (_) {}
    final game = Game(title: name, url: 'https://manual/${Uri.encodeComponent(name)}', size: size, consoleId: 'manual');
    final taskId = game.gameId;
    ref.read(gameStateManagerProvider.notifier).registerTransientGame(game);
    ref.read(taskQueueProvider.notifier).enqueue(taskId, TaskType.chdConversion, {
      'taskId': taskId,
      'inputPath': _inputPath!,
      'outputDir': _outputDir!,
      'chdmanPath': ref.read(settingsProvider).chdmanPath,
    });
    _snack('Conversion added to the task list');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _chdmanReady;
    return Scaffold(
      appBar: AppBar(title: const Text('CHD Converter')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const ToolDescription(
              icon: Icons.compress,
              text: 'Convert disc images to CHD to save space, or extract CHD back. Compresses '
                  '.cue/.gdi/.iso and extracts .chd. Needs the chdman tool (bundled with MAME).',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ready == null
                  ? const Center(child: CircularProgressIndicator())
                  : (ready ? _convertUi(context) : _chdmanWarning(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _convertUi(BuildContext context) {
    final theme = Theme.of(context);
    final input = _inputPath;
    final plan = input == null ? null : ChdService.planFor(input);
    final canRun = input != null && _outputDir != null && plan != null;
    final action = input == null
        ? ''
        : (ChdService.modeForInput(input) == ChdMode.extract ? 'Extract → .cue/.bin' : 'Compress → .chd');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fileRow(theme, Icons.insert_drive_file_outlined, 'Disc image',
            input != null ? p.basename(input) : 'No file selected', _pickInput),
        const SizedBox(height: 12),
        _fileRow(theme, Icons.folder_outlined, 'Output folder', _outputDir ?? 'No folder selected', _pickOutput),
        if (input != null && plan == null) ...[
          const SizedBox(height: 12),
          Text('Unsupported file type.', style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (action.isNotEmpty && plan != null) ...[
          const SizedBox(height: 12),
          Text(action, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canRun ? _enqueue : null,
            icon: const Icon(Icons.compress, size: 18),
            label: const Text('Add to task list'),
          ),
        ),
      ],
    );
  }

  Widget _chdmanWarning(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Icon(Icons.build_circle_outlined, size: 40, color: scheme.primary),
                        const SizedBox(height: 12),
                        Text('chdman required', style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'CHD conversion is done by chdman, part of the MAME tools. Many handhelds '
                    '(Batocera, Knulli) and desktops already have it. If it is not found '
                    'automatically, point the app at a chdman binary.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _pickChdman,
                      icon: const Icon(Icons.folder_open, size: 18),
                      label: const Text('Select chdman binary'),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
