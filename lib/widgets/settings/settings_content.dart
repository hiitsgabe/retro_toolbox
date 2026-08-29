import 'package:flutter/material.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/models/settings_model.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/widgets/settings/directory_setting.dart';
import 'package:roms_downloader/widgets/settings/boolean_setting.dart';
import 'package:roms_downloader/widgets/settings/number_setting.dart';
import 'package:roms_downloader/widgets/settings/permissions_setting.dart';
import 'package:roms_downloader/widgets/settings/tools_setting.dart';
import 'package:roms_downloader/widgets/settings/favorites_settings.dart';
import 'package:roms_downloader/widgets/settings/accounts_setting.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/settings/nsz_setting.dart';
import 'package:roms_downloader/widgets/settings/catalog_source_setting.dart';

class SettingsContent extends StatelessWidget {
  final Console? selectedConsole;
  final SettingsNotifier settingsNotifier;

  const SettingsContent({
    super.key,
    required this.selectedConsole,
    required this.settingsNotifier,
  });

  /// Consistent card wrapper: icon + title, optional subtitle, then content.
  Widget _section(BuildContext context, {required IconData icon, required String title, String? subtitle, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _section(
            context,
            icon: selectedConsole == null ? Icons.settings : Icons.videogame_asset,
            title: selectedConsole == null ? 'General Settings' : '${selectedConsole!.name} Settings',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  DirectorySetting(
                    settingKey: AppSettings.downloadDir,
                    title: 'Download Directory',
                    icon: Icons.folder_open,
                    console: selectedConsole,
                    settingsNotifier: settingsNotifier,
                  ),
                  const SizedBox(height: 8),
                  BooleanSetting(
                    settingKey: AppSettings.autoExtract,
                    defaultValue: true,
                    title: 'Auto Extract After Download',
                    subtitle: 'Automatically extract archive files after download completes',
                    icon: Icons.archive,
                    console: selectedConsole,
                    settingsNotifier: settingsNotifier,
                  ),
                  const SizedBox(height: 8),
                  BooleanSetting(
                    settingKey: AppSettings.extractToFolder,
                    defaultValue: false,
                    title: 'Extract Into Subfolder',
                    subtitle: 'Extract each archive into its own folder instead of the download directory',
                    icon: Icons.create_new_folder_outlined,
                    console: selectedConsole,
                    settingsNotifier: settingsNotifier,
                  ),
                  if (selectedConsole == null) ...[
                    const SizedBox(height: 8),
                    NumberSetting(
                      settingKey: AppSettings.maxParallelDownloads,
                      defaultValue: 5,
                      title: 'Max Parallel Downloads',
                      subtitle: 'Maximum number of simultaneous downloads',
                      icon: Icons.download,
                      min: 1,
                      max: 20,
                      dropdown: true,
                      settingsNotifier: settingsNotifier,
                    ),
                    const SizedBox(height: 8),
                    NumberSetting(
                      settingKey: AppSettings.maxParallelExtractions,
                      defaultValue: 2,
                      title: 'Max Parallel Extractions',
                      subtitle: 'Maximum number of simultaneous extractions',
                      icon: Icons.archive,
                      min: 1,
                      max: 20,
                      dropdown: true,
                      settingsNotifier: settingsNotifier,
                    ),
                  ],
                ],
              ),
            ),
          if (selectedConsole == null) ...[
            const SizedBox(height: 8),
            _section(
              context,
              icon: Icons.dataset_outlined,
              title: 'Catalog Source',
              subtitle: 'Import a console catalog JSON file or load one from a URL.',
              child: const CatalogSourceSetting(),
            ),
            const SizedBox(height: 8),
            const PermissionsSetting(),
          ],
          if (selectedConsole != null && selectedConsole!.shouldDecompressNsz) ...[
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: NszSetting(),
              ),
            ),
          ],
          if (selectedConsole != null && selectedConsole!.hasTokenAuth) ...[
            const SizedBox(height: 8),
            _section(
              context,
              icon: Icons.lock_outline,
              title: 'Authentication',
              child: ConsoleAuthSetting(console: selectedConsole!),
            ),
          ],
          const SizedBox(height: 8),
          _section(
            context,
            icon: Icons.build,
            title: 'Tools',
            child: ToolsSetting(console: selectedConsole),
          ),
          if (selectedConsole == null) ...[
            const SizedBox(height: 8),
            _section(
              context,
              icon: Icons.manage_accounts_outlined,
              title: 'Accounts',
              subtitle: 'Connect accounts for restricted or private collections.',
              child: const AccountsSetting(),
            ),
            const SizedBox(height: 8),
            _section(
              context,
              icon: Icons.favorite,
              title: 'Favorites',
              child: const FavoritesSettings(),
            ),
          ],
        ],
      ),
    );
  }
}
