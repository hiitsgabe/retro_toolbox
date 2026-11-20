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

/// Converts 3DS cartridge images (.3ds/.cci) to installable .cia via the
/// bundled 3dsconv. Needs boot9.bin or aes_keys.txt for encrypted dumps: until
/// one is set the status asks for it and Start is off (decrypted dumps still
/// work best with it). The form stays.
class CiaConvertScreen extends ConsumerStatefulWidget {
  const CiaConvertScreen({super.key});

  @override
  ConsumerState<CiaConvertScreen> createState() => _CiaConvertScreenState();
}

class _CiaConvertScreenState extends ConsumerState<CiaConvertScreen> {
  String? _inputPath;
  String? _outputDir;
  bool _outputPicked = false;
  bool _deleteOriginals = false;
  (String, String)? _error;

  void _fail(String line, Object e) {
    if (mounted) setState(() => _error = (line, '$e'));
  }

  Future<void> _pickBoot9() async {
    try {
      await chooseKeyFile(context, ref, KeyFile.boot9);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      _fail('Could not use that file', e);
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
    enqueueToolTask(ref, TaskType.cia3dsConversion, input, {
      'inputPath': input,
      'outputDir': out,
      'boot9Path': ref.read(settingsProvider).boot9Path,
      'ignoreEncryption': false,
      'deleteOriginals': _deleteOriginals,
    });
    setState(() {
      _inputPath = null;
      if (!_outputPicked) _outputDir = null;
    });
  }

  StatusPanel _status(bool hasKeys) {
    final error = _error;
    if (!hasKeys) {
      return StatusPanel.missingRequirement(
        title: '3DS keys needed',
        detail: 'Converting an encrypted 3DS dump needs keys from your own console: the ARM9 bootROM '
            '(boot9.bin, dumped with e.g. GodMode9) or the aes_keys.txt from Citra/Azahar’s sysdata '
            'folder. They are not distributed.',
        actionLabel: 'Locate boot9.bin or aes_keys.txt',
        onAction: _pickBoot9,
        linkLabel: 'Open Settings > Keys',
        onLink: () => SettingsScreen.open(context, section: SettingsSection.keys),
      );
    }
    if (error != null) return StatusPanel.error(line: error.$1, details: error.$2);
    return toolTaskStatus(
      ref.watch(taskQueueProvider),
      ref.watch(extractionProvider),
      TaskType.cia3dsConversion,
      name: (t) => p.basename('${t.params['inputPath']}'),
      saved: (t) => savedIn('${p.basenameWithoutExtension('${t.params['inputPath']}')}.cia', '${t.params['outputDir']}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasKeys = ref.watch(settingsProvider).boot9Path?.isNotEmpty ?? false;
    final input = _inputPath;
    final canRun = hasKeys && input != null && _outputDir != null;
    return KitScaffold(
      title: '3DS → CIA',
      subtitle: 'Turn .3ds dumps into installable .cia files',
      icon: Icons.sd_card,
      glyph: PixelIcons.cia,
      area: AppArea.tools,
      info: const InfoButton(
        icon: Icons.sd_card_outlined,
        title: '3DS → CIA',
        text: 'Converts 3DS cartridge images (.3ds/.cci) into installable .cia, for use with the '
            'FBI Server or your own backups. Encrypted dumps need your console’s boot9.bin or aes_keys.txt.\n\n'
            'Only use keys and games from a console you own. We do not support or condone piracy.',
      ),
      body: KitColumns(
        endFirstWhenStacked: true,
        start: [
          const KitLabel('Input'),
          KitPanel(children: [
            Slot(label: '3DS image', path: input, emptyText: 'Choose a .3ds or .cci', onPick: _pickInput, autofocus: true),
            Slot(label: 'Save to', folder: true, path: _outputDir, emptyText: 'Same folder as the image', onPick: _pickOutput),
          ]),
          const KitLabel('Options'),
          OptionList(children: [
            OptionToggle(
              title: 'Delete original',
              subtitle: 'Only after it converts',
              value: _deleteOriginals,
              onChanged: (v) => setState(() => _deleteOriginals = v),
            ),
          ]),
        ],
        end: [_status(hasKeys)],
      ),
      actionBar: ActionBar(
        primary: KitAction('Convert to CIA', canRun ? _enqueue : null, icon: Icons.sync),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: !hasKeys
            ? 'Needs your 3DS keys'
            : input == null
                ? 'Pick a .3ds or .cci'
                : '${p.basename(input)} to .cia',
      ),
    );
  }
}
