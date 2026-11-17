import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/settings/setting_rows.dart';

/// "Group versions", and under it, while it is on for this scope,
/// "Download every disc". [console] null: the general settings.
class VersionGroupingSetting extends ConsumerWidget {
  const VersionGroupingSetting({super.key, required this.console});

  final Console? console;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider);
    final grouped = ref.read(settingsProvider.notifier).groupVersions(console?.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        BoolSettingRow(
          settingKey: AppSettings.groupVersions,
          defaultValue: true,
          title: 'Group versions',
          subtitle: 'One entry per game, with its regions, revisions, discs and extras inside',
          console: console,
        ),
        if (grouped)
          BoolSettingRow(
            settingKey: AppSettings.downloadAllDiscs,
            defaultValue: true,
            title: 'Download every disc',
            subtitle: 'Download on a grouped game gets all its discs',
            console: console,
            indent: true,
          ),
      ],
    );
  }
}
