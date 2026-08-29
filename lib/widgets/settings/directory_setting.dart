import 'package:flutter/material.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/providers/settings_provider.dart';

class DirectorySetting extends StatelessWidget {
  final String settingKey;
  final String title;
  final IconData icon;
  final Console? console;
  final SettingsNotifier settingsNotifier;

  const DirectorySetting({
    super.key,
    required this.settingKey,
    required this.title,
    required this.icon,
    required this.console,
    required this.settingsNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final generalDir = settingsNotifier.getGeneralSetting<String>(settingKey) ?? '';
    final consoleSpecificDir = console != null ? settingsNotifier.getConsoleSetting<String>(console!.id, settingKey) : null;
    final hasConsoleSpecific = console != null && (consoleSpecificDir?.isNotEmpty ?? false);

    // With no override, show the real resolved path (general dir + roms_folder).
    final String currentDir;
    if (hasConsoleSpecific) {
      currentDir = consoleSpecificDir!;
    } else if (console != null && settingKey == AppSettings.downloadDir && generalDir.isNotEmpty) {
      currentDir = settingsNotifier.getDownloadDir(console!.id);
    } else {
      currentDir = generalDir;
    }
    final isUsingGeneral = console != null && !hasConsoleSpecific && generalDir.isNotEmpty;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentDir.isEmpty)
            Text(
              'No directory selected',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            )
          else ...[
            Text(
              currentDir,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            if (isUsingGeneral)
              Text(
                'Using general setting',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasConsoleSpecific)
            IconButton(
              onPressed: () async {
                await settingsNotifier.setConsoleSetting(console!.id, settingKey, '');
              },
              icon: const Icon(Icons.restore),
              tooltip: 'Use general setting',
            ),
          IconButton(
            onPressed: () async {
              final newDir = await settingsNotifier.selectDownloadDirectory();
              if (newDir != null) {
                if (console == null) {
                  await settingsNotifier.setGeneralSetting(settingKey, newDir);
                } else {
                  await settingsNotifier.setConsoleSetting(console!.id, settingKey, newDir);
                }
              }
            },
            icon: const Icon(Icons.folder_open),
            tooltip: 'Choose directory',
          ),
        ],
      ),
    );
  }
}
