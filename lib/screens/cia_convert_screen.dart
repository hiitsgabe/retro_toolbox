import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/models/extraction_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/services/key_files.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';

/// Converts 3DS cartridge images (.3ds/.cci) to installable .cia via the
/// bundled 3dsconv. Needs boot9.bin or aes_keys.txt for encrypted dumps — blocks with a
/// picker card until one is set (decrypted dumps still work best with it).
class CiaConvertScreen extends ConsumerStatefulWidget {
  const CiaConvertScreen({super.key});

  @override
  ConsumerState<CiaConvertScreen> createState() => _CiaConvertScreenState();
}

class _CiaConvertScreenState extends ConsumerState<CiaConvertScreen> {
  String? _inputPath;
  String? _outputDir;
  String? _activeTaskId;
  bool _deleteOriginals = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickBoot9() async {
    try {
      await chooseKeyFile(context, ref, KeyFile.boot9);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _pickInput() async {
    try {
      final path = await pickFile(
        context,
        title: 'Select a .3ds/.cci file',
        extensions: const ['3ds', 'cci'],
        initialDir: _outputDir ?? (_inputPath != null ? p.dirname(_inputPath!) : null),
      );
      if (path == null || !mounted) return;
      setState(() {
        _inputPath = path;
        _outputDir ??= p.dirname(path);
      });
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _pickOutput() async {
    final dir = await pickDirectory(context, title: 'Select output folder');
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
    ref.read(taskQueueProvider.notifier).enqueue(taskId, TaskType.cia3dsConversion, {
      'taskId': taskId,
      'inputPath': _inputPath!,
      'outputDir': _outputDir!,
      'boot9Path': ref.read(settingsProvider).boot9Path,
      'ignoreEncryption': false,
      'deleteOriginals': _deleteOriginals,
    });
    setState(() => _activeTaskId = taskId);
  }

  void _reset() => setState(() {
        _activeTaskId = null;
        _inputPath = null;
      });

  @override
  Widget build(BuildContext context) {
    final hasBoot9 = ref.watch(settingsProvider).boot9Path?.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('3DS → CIA')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const ToolDescription(
              icon: Icons.sd_card_outlined,
              text: 'Converts 3DS cartridge images (.3ds/.cci) into installable .cia — for use with the '
                  'FBI Server or your own backups. Encrypted dumps need your console’s boot9.bin or aes_keys.txt.',
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _activeTaskId != null
                  ? _progressUi(context)
                  : (hasBoot9 ? _convertUi(context) : _boot9Warning(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressUi(BuildContext context) {
    final theme = Theme.of(context);
    final task = ref.watch(extractionProvider).getTaskState(_activeTaskId!);
    final status = task?.status ?? ExtractionStatus.extracting;
    final progress = task?.progress ?? 0.0;
    if (status == ExtractionStatus.failed) {
      return _resultCard(theme, Icons.error_outline, theme.colorScheme.error, 'Conversion failed', task?.error ?? 'Unknown error', 'Try again');
    }
    if (status == ExtractionStatus.completed) {
      return _resultCard(theme, Icons.check_circle, Colors.green, 'Done', 'Saved to $_outputDir', 'Convert another');
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Converting to CIA…', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: progress > 0 ? progress : null),
          const SizedBox(height: 8),
          Text('You can leave this screen — it keeps running in the task list.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _resultCard(ThemeData theme, IconData icon, Color color, String title, String detail, String action) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: color),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          FilledButton(onPressed: _reset, child: Text(action)),
        ],
      ),
    );
  }

  Widget _convertUi(BuildContext context) {
    final theme = Theme.of(context);
    final canRun = _inputPath != null && _outputDir != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fileRow(theme, Icons.insert_drive_file_outlined, '3DS image', _inputPath != null ? p.basename(_inputPath!) : 'No file selected', _pickInput),
        const SizedBox(height: 12),
        _fileRow(theme, Icons.folder_outlined, 'Output folder', _outputDir ?? 'No folder selected', _pickOutput),
        const SizedBox(height: 12),
        CheckboxListTile(
          value: _deleteOriginals,
          onChanged: (v) => setState(() => _deleteOriginals = v ?? false),
          title: const Text('Delete original when done'),
          subtitle: const Text('Only after a successful conversion.'),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(onPressed: canRun ? _enqueue : null, icon: const Icon(Icons.sync, size: 18), label: const Text('Add to task list')),
        ),
      ],
    );
  }

  Widget _boot9Warning(BuildContext context) {
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
                        Icon(Icons.vpn_key_rounded, size: 40, color: scheme.primary),
                        const SizedBox(height: 12),
                        Text('3DS keys required', style: theme.textTheme.titleMedium),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Converting an encrypted 3DS dump needs keys from your own console: the ARM9 bootROM '
                    '(boot9.bin, dumped with e.g. GodMode9) or the aes_keys.txt from Citra/Azahar’s sysdata '
                    'folder. They are not distributed.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined, size: 20, color: scheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Only use keys and games from a console you own. We do not support or condone piracy.',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: [
                      FilledButton.icon(onPressed: _pickBoot9, icon: const Icon(Icons.folder_open, size: 18), label: const Text('Choose file')),
                      OutlinedButton(
                        onPressed: () => SettingsScreen.open(context, section: SettingsSection.keys),
                        child: const Text('Open Settings > Keys'),
                      ),
                    ]),
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
      decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(8)),
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
