import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/archive_extract_service.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Standalone archive extraction: pick a .rar or .zip and an output folder,
/// then extract. The work runs as a background task (task manager + Android
/// notification, with progress); the tool stays and shows it.
class RarDecompressScreen extends ConsumerStatefulWidget {
  const RarDecompressScreen({super.key});

  @override
  ConsumerState<RarDecompressScreen> createState() => _RarDecompressScreenState();
}

class _RarDecompressScreenState extends ConsumerState<RarDecompressScreen> {
  String? _archivePath;
  String? _outputDir;
  bool _outputPicked = false;
  bool _deleteOriginals = false;
  (String, String)? _error;

  void _fail(String line, Object e) {
    if (mounted) setState(() => _error = (line, '$e'));
  }

  Future<void> _pickArchive() async {
    try {
      final path = await pickFile(
        context,
        title: 'Select a .rar or .zip file',
        extensions: const ['rar', 'zip'],
        initialDir: _outputDir ?? (_archivePath != null ? p.dirname(_archivePath!) : null),
      );
      if (path == null || !mounted) return;
      setState(() {
        _archivePath = path;
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

  static bool _unsupported(String archive) => ArchiveExtractService.archiveKind(archive) == ArchiveKind.rar && !ArchiveExtractService.rarSupported();

  /// Hands the extraction to the task queue, so it runs in the background and
  /// shows in the task list. The tool stays: the status shows the queued
  /// archive, and the slot is free for the next one.
  void _extract() {
    final archive = _archivePath, out = _outputDir;
    if (archive == null || out == null) return;
    if (_unsupported(archive)) {
      _fail("This device can't open .rar files", UnsupportedError('RAR extraction is not supported on this platform yet.'));
      return;
    }
    enqueueToolTask(ref, TaskType.archiveExtraction, archive, {
      'archivePath': archive,
      'outputDir': out,
      'deleteOriginals': _deleteOriginals,
    });
    setState(() {
      _archivePath = null;
      if (!_outputPicked) _outputDir = null;
    });
  }

  StatusPanel _status() {
    final error = _error;
    if (error != null) return StatusPanel.error(line: error.$1, details: error.$2);
    return toolTaskStatus(
      ref.watch(taskQueueProvider),
      ref.watch(extractionProvider),
      TaskType.archiveExtraction,
      name: (t) => p.basename('${t.params['archivePath']}'),
      saved: (t) => 'Extracted ${p.basename('${t.params['archivePath']}')} to ${pathParts('${t.params['outputDir']}').join(pathSeparator)}',
      failed: 'Could not extract',
    );
  }

  @override
  Widget build(BuildContext context) {
    final archive = _archivePath;
    final unsupported = archive != null && _unsupported(archive);
    final canRun = archive != null && _outputDir != null && !unsupported;
    return KitScaffold(
      title: 'Rar Decompress',
      subtitle: 'Extract .zip and .rar archives',
      icon: Icons.folder_zip,
      glyph: PixelIcons.rar,
      area: AppArea.tools,
      info: const InfoButton(
        icon: Icons.folder_zip_outlined,
        title: 'Rar Decompress',
        text: 'Extracts .rar and .zip archives to a folder. Pick an archive and an output '
            'folder, then extract. RAR support is available on Android, macOS and Linux.\n\n'
            'Delete original only runs after a successful extraction; a multi-part archive takes all its parts with it.',
      ),
      body: KitColumns(
        endFirstWhenStacked: true,
        start: [
          const KitLabel('Input'),
          KitPanel(children: [
            Slot(label: 'Archive', path: archive, emptyText: 'Choose a .zip or .rar', onPick: _pickArchive, autofocus: true),
            Slot(label: 'Save to', folder: true, path: _outputDir, emptyText: 'Same folder as the archive', onPick: _pickOutput),
          ]),
          const KitLabel('Options'),
          OptionList(children: [
            OptionToggle(
              title: 'Delete original',
              subtitle: 'Only after it extracts, with every part',
              value: _deleteOriginals,
              onChanged: (v) => setState(() => _deleteOriginals = v),
            ),
          ]),
        ],
        end: [_status()],
      ),
      actionBar: ActionBar(
        primary: KitAction('Extract', canRun ? _extract : null, icon: Icons.unarchive),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: archive == null
            ? 'Pick a .zip or .rar'
            : unsupported
                ? "This device can't open .rar files"
                : '${p.basename(archive)} into ${p.basename(_outputDir ?? '')}',
      ),
    );
  }
}
