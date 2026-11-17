import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/key_files.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';
import 'package:retro_toolbox/widgets/settings/settings_sheet.dart';

/// "Make CHD": a conversion as a choice.
String handlerChoice(GameHandler h) => 'Make ${h.output.substring(1).toUpperCase()}';

String _chdType(bool cd) => cd ? 'CD (createcd)' : 'DVD (createdvd)';

/// What runs after extraction for [console]: keep the files, or one of the
/// conversions that fit its games. The catalog's choice holds until the user
/// picks another, which is marked Changed (X resets it). With CHD, the CHD
/// type an .iso is packed as; with NSZ and no Switch keys, a row to Keys
/// ([onOpenKeys]).
class HandlerSetting extends ConsumerWidget {
  final Console console;
  final VoidCallback? onOpenKeys;

  const HandlerSetting({super.key, required this.console, this.onOpenKeys});

  Future<void> _pickChdType(BuildContext context, SettingsNotifier notifier) {
    return showSettingsSheet<void>(
      context,
      title: 'CHD type for .iso',
      subtitle: 'DVD is the standard for PS2/PSP. Pick CD for AetherSX2/NetherSX2, which only boot CD CHDs (current PCSX2 builds read both).',
      builder: (sheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
        for (final cd in [false, true])
          SheetOption(
            icon: notifier.chdIsoAsCd(console.id) == cd ? SettingsIcons.check : SettingsIcons.none,
            label: _chdType(cd),
            autofocus: notifier.chdIsoAsCd(console.id) == cd,
            onPressed: () {
              notifier.setChdIsoAsCd(console.id, cd);
              Navigator.of(sheet).pop();
            },
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider); // rebuild when the choice changes
    final notifier = ref.read(settingsProvider.notifier);
    final active = notifier.activeHandler(console.id);
    final changed = notifier.changedKeys(console.id);
    final iso = notifier.chdIsoAsCd(console.id);
    final isoChanged = changed.contains(AppSettings.chdIsoAsCd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSegmentedRow<GameHandler?>(
          title: 'After extraction',
          subtitle: active == null ? 'Leave the files as they are' : '${active.inputs.join(' / ')} to ${active.output}',
          options: [
            (null, 'Keep files'),
            for (final h in console.applicableHandlers) (h, handlerChoice(h)),
          ],
          selected: active,
          onChanged: (h) => notifier.setActiveHandler(console.id, h),
          changed: changed.contains(AppSettings.additionalHandler),
          onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.additionalHandler),
        ),
        if (active == GameHandler.chdCompress)
          SettingsValueRow(
            title: 'CHD type for .iso',
            subtitle: isoChanged ? 'Default: ${_chdType(false)}' : 'Advanced',
            value: _chdType(iso),
            indent: true,
            onTap: () => _pickChdType(context, notifier),
            changed: isoChanged,
            onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.chdIsoAsCd),
          ),
        if (active == GameHandler.nszDecompress && KeyFile.switchKeys.pathIn(settings) == null)
          SettingsValueRow(
            key: const ValueKey('missing switch keys'),
            title: 'Switch keys missing',
            subtitle: 'NSZ to NSP needs them. Set them in Keys',
            value: 'Not set',
            indent: true,
            onTap: onOpenKeys,
          ),
      ],
    );
  }
}
