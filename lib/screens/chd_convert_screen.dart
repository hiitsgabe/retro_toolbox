import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/chd_service.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Convert disc images to/from CHD via chdman. Compresses .cue/.gdi/.iso and
/// extracts .chd back. Until a chdman is found (a user-set path, a bundled
/// one, or one on PATH) the status says so and Start is off; the form stays.
class ChdConvertScreen extends ConsumerStatefulWidget {
  const ChdConvertScreen({super.key, this.chdmanAvailable});

  /// Tests: whether a chdman resolves from the set path.
  final Future<bool> Function(String? path)? chdmanAvailable;

  @override
  ConsumerState<ChdConvertScreen> createState() => _ChdConvertScreenState();
}

class _ChdConvertScreenState extends ConsumerState<ChdConvertScreen> {
  String? _inputPath;
  String? _outputDir;

  /// The output folder was picked, not taken from the input's.
  bool _outputPicked = false;
  bool? _chdmanReady;
  bool _deleteOriginals = false;
  bool _isoAsCd = false;
  (String, String)? _error;

  @override
  void initState() {
    super.initState();
    _checkChdman();
  }

  Future<void> _checkChdman() async {
    final ready = await (widget.chdmanAvailable ?? ChdService.isAvailable)(ref.read(settingsProvider).chdmanPath);
    if (mounted) setState(() => _chdmanReady = ready);
  }

  void _fail(String line, Object e) {
    if (mounted) setState(() => _error = (line, '$e'));
  }

  Future<void> _pickChdman() async {
    try {
      final path = await pickFile(context, title: 'Select the chdman binary');
      if (path == null || !mounted) return;
      await ref.read(settingsProvider.notifier).setChdmanPath(path);
      ChdService.debugReset();
      setState(() => _error = null);
      await _checkChdman();
    } catch (e) {
      _fail('Could not use that file', e);
    }
  }

  Future<void> _pickInput() async {
    try {
      final path = await pickFile(
        context,
        title: 'Select a disc image',
        extensions: const ['cue', 'gdi', 'toc', 'iso', 'chd'],
        initialDir: _outputDir ?? (_inputPath != null ? p.dirname(_inputPath!) : null),
      );
      if (path == null || !mounted) return;
      setState(() {
        _inputPath = path;
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

  void _enqueue() {
    final input = _inputPath, out = _outputDir;
    if (input == null || out == null) return;
    enqueueToolTask(ref, TaskType.chdConversion, input, {
      'inputPath': input,
      'outputDir': out,
      'chdmanPath': ref.read(settingsProvider).chdmanPath,
      'deleteOriginals': _deleteOriginals,
      'isoAsCd': _isoAsCd,
    });
    // The tool stays: the status shows the queued disc, and the slot is free
    // for the next one.
    setState(() {
      _inputPath = null;
      if (!_outputPicked) _outputDir = null;
    });
  }

  static String _outName(QueuedTask t) {
    final input = '${t.params['inputPath']}';
    return '${p.basenameWithoutExtension(input)}${ChdService.planFor(input)?.outExt ?? '.chd'}';
  }

  StatusPanel _status() {
    final error = _error;
    if (_chdmanReady == false) {
      return StatusPanel.missingRequirement(
        title: 'chdman not found',
        detail: 'CHD conversion is done by chdman, part of the MAME tools. Many handhelds (Batocera, Knulli) and desktops already have it.',
        actionLabel: 'Locate chdman',
        onAction: _pickChdman,
      );
    }
    if (error != null) return StatusPanel.error(line: error.$1, details: error.$2);
    return toolTaskStatus(
      ref.watch(taskQueueProvider),
      ref.watch(extractionProvider),
      TaskType.chdConversion,
      name: (t) => p.basename('${t.params['inputPath']}'),
      saved: (t) => savedIn(_outName(t), '${t.params['outputDir']}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final input = _inputPath;
    final plan = input == null ? null : ChdService.planFor(input, isoAsCd: _isoAsCd);
    final extract = input != null && ChdService.modeForInput(input) == ChdMode.extract;
    final ready = _chdmanReady == true;
    final canRun = ready && input != null && _outputDir != null && plan != null;
    final String summary;
    if (_chdmanReady == null) {
      summary = 'Looking for chdman';
    } else if (!ready) {
      summary = 'Needs chdman';
    } else if (input == null) {
      summary = 'Pick a disc image';
    } else if (plan == null) {
      summary = 'chdman cannot read this file';
    } else {
      summary = '${p.basename(input)} to ${extract ? '.cue/.bin' : '.chd'}';
    }
    return KitScaffold(
      title: 'CHD Converter',
      subtitle: 'Shrink disc images to .chd, or extract them',
      icon: Icons.compress,
      glyph: PixelIcons.chd,
      area: AppArea.tools,
      info: const InfoButton(
        icon: Icons.compress,
        title: 'CHD Converter',
        text: 'Convert disc images to CHD to save space, or extract CHD back. Compresses '
            '.cue/.gdi/.iso and extracts .chd. Needs the chdman tool (bundled with MAME).\n\n'
            'Delete original only runs after a successful conversion; a .cue or .gdi takes its track files with it.\n\n'
            'For .iso: DVD is the standard for PS2/PSP. Pick CD for AetherSX2/NetherSX2, which only boot CD CHDs '
            '(current PCSX2 builds read both).',
      ),
      body: KitColumns(
        endFirstWhenStacked: true,
        start: [
          const KitLabel('Input'),
          KitPanel(children: [
            Slot(label: 'Disc image', path: input, emptyText: 'Choose a .cue, .gdi, .iso or .chd', onPick: _pickInput, autofocus: true),
            Slot(label: 'Save to', folder: true, path: _outputDir, emptyText: 'Same folder as the image', onPick: _pickOutput),
          ]),
          const KitLabel('Options'),
          OptionList(children: [
            OptionToggle(
              title: 'Delete original',
              subtitle: 'Only after it converts, with the .cue tracks',
              value: _deleteOriginals,
              onChanged: (v) => setState(() => _deleteOriginals = v),
            ),
            OptionExpander(subtitle: '.iso as DVD or CD', children: [
              OptionChoice<bool>(
                title: 'DVD',
                subtitle: 'The standard for PS2 and PSP',
                value: false,
                groupValue: _isoAsCd,
                onSelected: (v) => setState(() => _isoAsCd = v),
              ),
              OptionChoice<bool>(
                title: 'CD',
                subtitle: 'For AetherSX2 and NetherSX2',
                value: true,
                groupValue: _isoAsCd,
                onSelected: (v) => setState(() => _isoAsCd = v),
              ),
            ]),
          ]),
        ],
        end: [_status()],
      ),
      actionBar: ActionBar(
        primary: KitAction(extract ? 'Extract to CUE/BIN' : 'Compress to CHD', canRun ? _enqueue : null, icon: extract ? Icons.unarchive_outlined : Icons.compress),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: summary,
      ),
    );
  }
}
