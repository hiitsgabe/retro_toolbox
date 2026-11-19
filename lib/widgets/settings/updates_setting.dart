import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/widgets/settings/handler_setting.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';

/// Where [console]'s updates go and what is done with them, for a console
/// whose catalog lists updates. Unpacking and the handler follow the game's
/// until a choice here; each choice is a change with its own Reset.
class UpdatesSetting extends ConsumerWidget {
  const UpdatesSetting({super.key, required this.console});

  final Console console;

  Future<void> _pick(BuildContext context, SettingsNotifier notifier) async {
    final dir = await pickDirectory(context, title: 'Select updates folder');
    if (dir == null) return;
    await notifier.setConsoleSetting(console.id, AppSettings.updatesDir, dir);
  }

  Future<void> _choose(SettingsNotifier notifier, String key, String? value) =>
      value == null ? notifier.resetConsoleSetting(console.id, key) : notifier.setConsoleSetting(console.id, key, value);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final changed = notifier.changedKeys(console.id);
    final dir = notifier.updatesDir(console.id);
    final fallback = notifier.defaultUpdatesDir(console.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsValueRow(
          title: 'Updates and DLC folder',
          subtitle: changed.contains(AppSettings.updatesDir) ? 'Default: ${fallback.isEmpty ? 'not chosen' : fallback}' : 'A folder named updates in the download folder',
          value: dir.isEmpty ? 'Not chosen' : dir,
          onTap: () => _pick(context, notifier),
          changed: changed.contains(AppSettings.updatesDir),
          onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.updatesDir),
        ),
        SettingsSegmentedRow<String?>(
          title: 'Unpack updates',
          subtitle: 'Same as the game follows Extract archives and the catalog',
          options: const [(null, 'Same as the game'), ('none', 'Keep as is'), ('unzip', 'Unzip'), ('unrar', 'Unrar')],
          selected: notifier.getConsoleSetting<String>(console.id, AppSettings.updateDecompress),
          onChanged: (v) => _choose(notifier, AppSettings.updateDecompress, v),
          changed: changed.contains(AppSettings.updateDecompress),
          onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.updateDecompress),
        ),
        SettingsSegmentedRow<String?>(
          title: 'After an update downloads',
          options: [
            (null, 'Same as the game'),
            ('none', 'Keep files'),
            for (final h in console.applicableHandlers) (h.id, handlerChoice(h)),
          ],
          selected: notifier.getConsoleSetting<String>(console.id, AppSettings.updateHandler),
          onChanged: (v) => _choose(notifier, AppSettings.updateHandler, v),
          changed: changed.contains(AppSettings.updateHandler),
          onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.updateHandler),
        ),
      ],
    );
  }
}
