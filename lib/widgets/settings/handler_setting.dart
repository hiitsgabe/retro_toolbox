import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';

/// One switch per conversion that fits [console]'s game files. At most one is
/// on; the catalog's handler is on until the user says otherwise. With CHD on,
/// Advanced picks the CHD type an .iso is packed as.
class HandlerSetting extends ConsumerWidget {
  final Console console;

  const HandlerSetting({super.key, required this.console});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider); // rebuild when the choice changes
    final notifier = ref.read(settingsProvider.notifier);
    final active = notifier.activeHandler(console.id);
    return Column(
      children: [
        for (final handler in console.applicableHandlers)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(handler.label),
            subtitle: Text('${handler.inputs.join(' / ')} → ${handler.output}'),
            value: active == handler,
            onChanged: (v) => notifier.setActiveHandler(console.id, v ? handler : null),
          ),
        if (active == GameHandler.chdCompress)
          ExpansionTile(
            title: const Text('Advanced'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CHD type for .iso', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('DVD (createdvd)')),
                  ButtonSegment(value: true, label: Text('CD (createcd)')),
                ],
                selected: {notifier.chdIsoAsCd(console.id)},
                onSelectionChanged: (s) => notifier.setChdIsoAsCd(console.id, s.first),
              ),
              const SizedBox(height: 8),
              Text(
                'DVD is the standard for PS2/PSP. Pick CD for AetherSX2/NetherSX2, which only boot CD CHDs '
                '(current PCSX2 builds read both).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
      ],
    );
  }
}
