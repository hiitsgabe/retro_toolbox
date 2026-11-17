import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/settings/boolean_setting.dart';

/// "Group multi-disc games", and under it, while it is on for this scope,
/// "Download every disc". [console] null: the general settings.
class DiscGroupingSetting extends ConsumerWidget {
  const DiscGroupingSetting({super.key, required this.console, required this.settingsNotifier});

  final Console? console;
  final SettingsNotifier settingsNotifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = ref.watch(settingProvider((key: AppSettings.groupDiscs, consoleId: console?.id))) as bool? ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BooleanSetting(
          settingKey: AppSettings.groupDiscs,
          defaultValue: false,
          title: 'Group multi-disc games',
          subtitle: 'Show Disc 1, Disc 2... of a game as one entry',
          icon: Icons.album_outlined,
          console: console,
          settingsNotifier: settingsNotifier,
        ),
        if (grouped) ...[
          const SizedBox(height: 8),
          BooleanSetting(
            settingKey: AppSettings.downloadAllDiscs,
            defaultValue: true,
            title: 'Download every disc',
            subtitle: 'Download on a grouped game gets all its discs',
            icon: Icons.library_add_outlined,
            console: console,
            settingsNotifier: settingsNotifier,
          ),
        ],
      ],
    );
  }
}
