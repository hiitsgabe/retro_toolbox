import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/switch_row.dart';

/// One switch per conversion that fits [console]'s game files. At most one is
/// on; the catalog's handler is on until the user says otherwise, and a
/// different choice is marked Changed with Reset. With CHD on, the CHD type
/// an .iso is packed as.
class HandlerSetting extends ConsumerWidget {
  final Console console;

  const HandlerSetting({super.key, required this.console});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider); // rebuild when the choice changes
    final notifier = ref.read(settingsProvider.notifier);
    final active = notifier.activeHandler(console.id);
    final fallback = notifier.defaultHandler(console.id);
    final changed = notifier.changedKeys(console.id);
    final handlerChanged = changed.contains(AppSettings.additionalHandler);
    final isoChanged = changed.contains(AppSettings.chdIsoAsCd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final handler in console.applicableHandlers)
          SettingsSwitchRow(
            title: handler.label,
            subtitle: handlerChanged && (handler == active || handler == fallback)
                ? 'Default: ${handler == fallback ? 'on' : 'off'}'
                : '${handler.inputs.join(' / ')} → ${handler.output}',
            value: active == handler,
            onChanged: (v) => notifier.setActiveHandler(console.id, v ? handler : null),
            changed: handlerChanged && (handler == active || handler == fallback),
            onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.additionalHandler),
          ),
        if (active == GameHandler.chdCompress) ...[
          SettingsSegmentedRow<bool>(
            title: 'CHD type for .iso',
            subtitle: isoChanged ? 'Default: DVD' : 'DVD for PS2/PSP; CD for AetherSX2/NetherSX2',
            indent: true,
            stacked: true,
            options: const [(false, 'DVD (createdvd)'), (true, 'CD (createcd)')],
            selected: notifier.chdIsoAsCd(console.id),
            onChanged: (v) => notifier.setChdIsoAsCd(console.id, v),
            changed: isoChanged,
            onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.chdIsoAsCd),
          ),
          const SettingsInfo(
            'DVD is the standard for PS2/PSP. Pick CD for AetherSX2/NetherSX2, which only boot CD CHDs (current PCSX2 builds read both).',
            indent: true,
          ),
        ],
      ],
    );
  }
}
