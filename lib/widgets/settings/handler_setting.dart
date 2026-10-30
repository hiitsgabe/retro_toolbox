import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';

/// One switch per conversion that fits [console]'s game files. At most one is
/// on; the catalog's handler is on until the user says otherwise.
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
      ],
    );
  }
}
