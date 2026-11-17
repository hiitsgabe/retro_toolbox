import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/widgets/settings/rows/switch_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';

/// What a console row says when the console follows the general setting.
const followingDownloads = 'Following Downloads';

/// An on/off setting, general ([console] null, [defaultValue] when unset) or
/// a console's: then it says whether the console follows Downloads or
/// changes it, with Reset (X) to follow again.
class BoolSettingRow extends ConsumerWidget {
  const BoolSettingRow({
    super.key,
    required this.settingKey,
    required this.title,
    this.subtitle,
    required this.defaultValue,
    this.console,
    this.indent = false,
  });

  final String settingKey;
  final String title;
  final String? subtitle;
  final bool defaultValue;
  final Console? console;
  final bool indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final console = this.console;
    if (console == null) {
      return SettingsSwitchRow(
        title: title,
        subtitle: subtitle,
        indent: indent,
        value: notifier.getGeneralSetting<bool>(settingKey) ?? defaultValue,
        onChanged: (v) => notifier.setGeneralSetting(settingKey, v),
      );
    }
    final fallback = notifier.generalBool(settingKey, console.id);
    final changed = notifier.changedKeys(console.id).contains(settingKey);
    return SettingsSwitchRow(
      title: title,
      subtitle: changed ? 'Default: ${fallback ? 'on' : 'off'}' : followingDownloads,
      indent: indent,
      value: notifier.getConsoleSetting<bool>(console.id, settingKey) ?? fallback,
      onChanged: (v) => notifier.setConsoleSetting(console.id, settingKey, v),
      changed: changed,
      onReset: () => notifier.resetConsoleSetting(console.id, settingKey),
    );
  }
}

/// Where downloads go: the general folder, or a console's own one (with the
/// folder it would use otherwise, and Reset).
class DownloadFolderRow extends ConsumerWidget {
  const DownloadFolderRow({super.key, this.console});

  final Console? console;

  Future<void> _pick(BuildContext context, SettingsNotifier notifier) async {
    final dir = await pickDirectory(context, title: 'Select download folder');
    if (dir == null) return;
    await notifier.saveDownloadDirectory(dir);
    if (console == null) {
      await notifier.setGeneralSetting(AppSettings.downloadDir, dir);
    } else {
      await notifier.setConsoleSetting(console!.id, AppSettings.downloadDir, dir);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final console = this.console;
    if (console == null) {
      final dir = notifier.getGeneralSetting<String>(AppSettings.downloadDir) ?? '';
      return SettingsValueRow(
        title: 'Download folder',
        subtitle: 'Games land here, one folder per console',
        value: dir.isEmpty ? 'Not chosen' : dir,
        monospace: dir.isNotEmpty,
        onTap: () => _pick(context, notifier),
      );
    }
    final changed = notifier.changedKeys(console.id).contains(AppSettings.downloadDir);
    final fallback = notifier.defaultDownloadDir(console.id);
    final dir = notifier.getDownloadDir(console.id);
    return SettingsValueRow(
      title: 'Download folder',
      subtitle: changed ? 'Default: ${fallback.isEmpty ? 'not chosen' : fallback}' : followingDownloads,
      value: dir.isEmpty ? 'Not chosen' : dir,
      monospace: dir.isNotEmpty,
      onTap: () => _pick(context, notifier),
      changed: changed,
      onReset: () => notifier.resetConsoleSetting(console.id, AppSettings.downloadDir),
    );
  }
}
