import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/services/key_files.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/settings/settings_sections.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Standalone NSZ to NSP decompression: pick a .nsz, an output folder, and
/// run. Requires prod.keys: until one is set the status asks for it and Start
/// is off; the form stays.
class NszDecompressScreen extends ConsumerStatefulWidget {
  const NszDecompressScreen({super.key});

  @override
  ConsumerState<NszDecompressScreen> createState() => _NszDecompressScreenState();
}

class _NszDecompressScreenState extends ConsumerState<NszDecompressScreen> {
  String? _nszPath;
  String? _outputDir;
  bool _outputPicked = false;
  bool _deleteOriginals = false;
  (String, String)? _error;

  void _fail(String line, Object e) {
    if (mounted) setState(() => _error = (line, '$e'));
  }

  Future<void> _pickKeys() async {
    try {
      await chooseKeyFile(context, ref, KeyFile.switchKeys);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      _fail('Could not use that file', e);
    }
  }

  Future<void> _pickNsz() async {
    try {
      final path = await pickFile(
        context,
        title: 'Select an NSZ file',
        extensions: const ['nsz'],
        initialDir: _outputDir ?? (_nszPath != null ? p.dirname(_nszPath!) : null),
      );
      if (path == null || !mounted) return;
      setState(() {
        _nszPath = path;
        // Decompressing next to the source is almost always what's wanted, and
        // it saves a second pick.
        if (!_outputPicked) _outputDir = p.dirname(path);
        _error = null;
      });
    } catch (e) {
      _fail('Could not open the file picker', e);
    }
  }

  Future<void> _pickOutput() async {
    try {
      final dir = await pickDirectory(context, title: 'Select output folder', initialDir: _outputDir);
      if (dir == null || !mounted) return;
      setState(() {
        _outputDir = dir;
        _outputPicked = true;
        _error = null;
      });
    } catch (e) {
      _fail('Could not open the folder picker', e);
    }
  }

  /// Hands the decompression to the task queue, so it runs in the background
  /// and shows in the task list. The tool stays: the status shows the queued
  /// file, and the slot is free for the next one.
  void _enqueueDecompress() {
    final keysPath = ref.read(settingsProvider).nszKeysPath;
    final nsz = _nszPath, out = _outputDir;
    if (nsz == null || out == null || keysPath == null) return;
    // The gameId (not the raw path) is the task key, and nszFilePath carries
    // the real path, so the two never disagree.
    enqueueToolTask(ref, TaskType.nszDecompression, nsz, {
      'nszFilePath': nsz,
      'outputDir': out,
      'keysPath': keysPath,
      'deleteOriginals': _deleteOriginals,
    });
    setState(() {
      _nszPath = null;
      if (!_outputPicked) _outputDir = null;
    });
  }

  StatusPanel _status(bool hasKeys) {
    final error = _error;
    if (!hasKeys) {
      return StatusPanel.missingRequirement(
        title: 'prod.keys needed',
        detail: 'An .nsz is a compressed and encrypted game file. To unpack it, the app needs the encryption keys '
            '(a prod.keys file, sometimes alongside title.keys) dumped from a modded console.',
        actionLabel: 'Locate prod.keys',
        onAction: _pickKeys,
        linkLabel: 'Open Settings > Keys',
        onLink: () => SettingsScreen.open(context, section: SettingsSection.keys),
      );
    }
    if (error != null) return StatusPanel.error(line: error.$1, details: error.$2);
    return toolTaskStatus(
      ref.watch(taskQueueProvider),
      ref.watch(extractionProvider),
      TaskType.nszDecompression,
      name: (t) => p.basename('${t.params['nszFilePath']}'),
      saved: (t) => savedIn('${p.basenameWithoutExtension('${t.params['nszFilePath']}')}.nsp', '${t.params['outputDir']}'),
      failed: 'Could not unpack',
    );
  }

  @override
  Widget build(BuildContext context) {
    final keysPath = ref.watch(settingsProvider).nszKeysPath;
    final hasKeys = keysPath != null && keysPath.isNotEmpty;
    final nsz = _nszPath;
    final canRun = hasKeys && nsz != null && _outputDir != null;
    return KitScaffold(
      title: 'NSZ Decompress',
      subtitle: 'Unpack .nsz back to installable .nsp',
      icon: Icons.unarchive,
      glyph: PixelIcons.nsz,
      area: AppArea.tools,
      info: const InfoButton(
        icon: Icons.unarchive_rounded,
        title: 'NSZ Decompress',
        text: 'Converts compressed .nsz files back into their original installable form. Pick a file and an output folder, then run. Requires your prod.keys.\n\n'
            'Only use keys and games from a console you personally own. This tool is for managing your own '
            'legally-owned backups; we do not support or condone piracy.',
      ),
      body: KitColumns(
        endFirstWhenStacked: true,
        start: [
          const KitLabel('Input'),
          KitPanel(children: [
            Slot(label: 'NSZ file', path: nsz, emptyText: 'Choose an .nsz', onPick: _pickNsz, autofocus: true),
            Slot(label: 'Save to', folder: true, path: _outputDir, emptyText: 'Same folder as the file', onPick: _pickOutput),
          ]),
          const KitLabel('Options'),
          OptionList(children: [
            OptionToggle(
              title: 'Delete original',
              subtitle: 'Only after it unpacks',
              value: _deleteOriginals,
              onChanged: (v) => setState(() => _deleteOriginals = v),
            ),
          ]),
        ],
        end: [_status(hasKeys)],
      ),
      actionBar: ActionBar(
        primary: KitAction('Unpack to NSP', canRun ? _enqueueDecompress : null, icon: Icons.unarchive_outlined),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: !hasKeys
            ? 'Needs prod.keys'
            : nsz == null
                ? 'Pick an .nsz'
                : '${p.basename(nsz)} to .nsp',
      ),
    );
  }
}
