import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/settings/catalog_source_setting.dart';
import 'package:retro_toolbox/widgets/settings/console_auth_setting.dart';
import 'package:retro_toolbox/widgets/settings/disc_grouping_setting.dart';
import 'package:retro_toolbox/widgets/settings/dual_screen_setting.dart';
import 'package:retro_toolbox/widgets/settings/extra_servers_setting.dart';
import 'package:retro_toolbox/widgets/settings/favorites_settings.dart';
import 'package:retro_toolbox/widgets/settings/handler_setting.dart';
import 'package:retro_toolbox/widgets/settings/ia_credentials_setting.dart';
import 'package:retro_toolbox/widgets/settings/launchbox_setting.dart';
import 'package:retro_toolbox/widgets/settings/library_setting.dart';
import 'package:retro_toolbox/widgets/settings/network_address_setting.dart';
import 'package:retro_toolbox/widgets/settings/nsz_setting.dart';
import 'package:retro_toolbox/widgets/settings/on_screen_keyboard_setting.dart';
import 'package:retro_toolbox/widgets/settings/permissions_setting.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/stepper_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';
import 'package:retro_toolbox/widgets/settings/save_recipes_source_setting.dart';
import 'package:retro_toolbox/widgets/settings/setting_rows.dart';
import 'package:retro_toolbox/widgets/settings/sports_cache_settings.dart';
import 'package:retro_toolbox/widgets/settings/tools_setting.dart';

/// The parts of Settings, in rail order.
enum SettingsSection {
  library('Library', 'Catalog, metadata, favorites', Icons.collections_bookmark_outlined),
  downloads('Downloads', 'Folder, extraction, discs', Icons.download_outlined),
  consoles('Consoles', 'Changes for one console', Icons.sports_esports_outlined),
  screens('Screens & controls', 'Dual screen, keyboard', Icons.splitscreen_outlined),
  network('Network & servers', 'Address, install servers', Icons.wifi),
  accounts('Accounts & sync', 'Internet Archive, Save Sync', Icons.person_outline),
  sports('Sports', 'Roster patcher', Icons.sports_soccer_outlined),
  storage('Storage', 'Caches, permissions', Icons.storage_outlined);

  const SettingsSection(this.label, this.hint, this.icon);

  final String label;
  final String hint;
  final IconData icon;
}

/// Short names for the settings a console changes, for its row in Consoles.
const consoleKeyNames = {
  AppSettings.downloadDir: 'folder',
  AppSettings.autoExtract: 'extraction',
  AppSettings.extractToFolder: 'subfolder',
  AppSettings.groupDiscs: 'grouping',
  AppSettings.downloadAllDiscs: 'every disc',
  AppSettings.additionalHandler: 'conversion',
  AppSettings.chdIsoAsCd: 'CHD type',
};

String _changesLine(List<String> keys) {
  final names = keys.map((k) => consoleKeyNames[k] ?? k).join(', ');
  return names.isEmpty ? names : names[0].toUpperCase() + names.substring(1);
}

String _changesCount(int n) => '$n change${n == 1 ? '' : 's'}';

/// The rows of [section], built from what is on now; empty when it has none
/// to show (the section is then left out). Watches what decides that.
/// [onOpenConsole]: a console row in Consoles was picked.
List<Widget> settingsSectionRows(SettingsSection section, WidgetRef ref, {required ValueChanged<Console> onOpenConsole}) {
  final settings = ref.watch(settingsProvider);
  final library = settings.isLibraryEnabled;
  final notifier = ref.read(settingsProvider.notifier);
  switch (section) {
    case SettingsSection.library:
      final favorites = ref.watch(favoritesProvider).count;
      return [
        const SettingsHeader('Games Library'),
        const LibrarySetting(),
        if (library) ...[
          const SettingsExpandRow(
            title: 'Catalog source',
            subtitle: 'Import a catalog JSON file or load one from a URL',
            value: 'Change',
            child: CatalogSourceSetting(),
          ),
          const SettingsHeader('Game metadata (LaunchBox)'),
          const LaunchboxSetting(),
          const SettingsHeader('Favorites'),
          SettingsExpandRow(
            title: 'Favorites',
            subtitle: '$favorites game${favorites == 1 ? '' : 's'}. Share them as a code, import or clear them',
            value: 'Manage',
            child: const FavoritesSettings(),
          ),
        ],
      ];
    case SettingsSection.downloads:
      if (!library) return const [];
      final extract = notifier.getGeneralSetting<bool>(AppSettings.autoExtract) ?? true;
      return [
        const SettingsInfo('Defaults for every console. A console can change any of these under Consoles.'),
        const SettingsHeader('Where'),
        const DownloadFolderRow(),
        const SettingsHeader('After a download'),
        const BoolSettingRow(
          settingKey: AppSettings.autoExtract,
          defaultValue: true,
          title: 'Extract archives',
          subtitle: 'Unzip as soon as a download finishes',
        ),
        if (extract)
          const BoolSettingRow(
            settingKey: AppSettings.extractToFolder,
            defaultValue: false,
            title: 'Extract into a subfolder',
            subtitle: 'One folder per archive',
            indent: true,
          ),
        const SettingsHeader('Multi-disc games'),
        const DiscGroupingSetting(console: null),
        const SettingsHeader('Speed'),
        SettingsStepperRow(
          title: 'Parallel downloads',
          subtitle: 'At the same time, 1 to 20',
          value: notifier.getMaxParallelDownloads(),
          min: 1,
          max: 20,
          onChanged: (v) => notifier.setGeneralSetting(AppSettings.maxParallelDownloads, v),
        ),
        SettingsStepperRow(
          title: 'Parallel extractions',
          subtitle: 'At the same time, 1 to 20',
          value: notifier.getMaxParallelExtractions(),
          min: 1,
          max: 20,
          onChanged: (v) => notifier.setGeneralSetting(AppSettings.maxParallelExtractions, v),
        ),
      ];
    case SettingsSection.consoles:
      final consoles = ref.watch(appStateProvider.select((s) => s.consolesList));
      if (!library || consoles.isEmpty) return const [];
      final changed = {for (final c in consoles) c.id: notifier.changedKeys(c.id)};
      final custom = consoles.where((c) => changed[c.id]!.isNotEmpty).toList();
      final plain = consoles.where((c) => changed[c.id]!.isEmpty).toList();
      return [
        const SettingsInfo('Each console follows Downloads until you change something for it. Pick one to see and reset its changes.'),
        if (custom.isNotEmpty) ...[
          const SettingsHeader('Changed'),
          for (final c in custom)
            SettingsValueRow(
              title: c.name,
              subtitle: _changesLine(changed[c.id]!),
              value: _changesCount(changed[c.id]!.length),
              onTap: () => onOpenConsole(c),
            ),
        ],
        if (plain.isNotEmpty) ...[
          const SettingsHeader('Using the defaults'),
          for (final c in plain) SettingsValueRow(title: c.name, subtitle: 'Follows Downloads', value: 'Defaults', onTap: () => onOpenConsole(c)),
        ],
      ];
    case SettingsSection.screens:
      final dual = showDualScreenCard(isAndroid: Platform.isAndroid, hasSecondDisplay: ref.watch(dualScreenProvider.select((s) => s.hasSecondDisplay)));
      return [
        if (dual) ...[const SettingsHeader('Dual screen'), const DualScreenSetting()],
        // The Linux handheld always has it on.
        if (!Handheld.current) ...[const SettingsHeader('Controls'), const OnScreenKeyboardSetting()],
      ];
    case SettingsSection.network:
      return [
        if (!Handheld.current) ...[const SettingsHeader('Address'), const NetworkAddressSetting()],
        const SettingsHeader('Install servers'),
        const ExtraServersSetting(),
      ];
    case SettingsSection.accounts:
      return [
        if (library) ...[
          const SettingsHeader('Accounts'),
          SettingsExpandRow(
            key: ValueKey('ia_${settings.hasIaCredentials}'),
            title: 'Internet Archive',
            subtitle: settings.hasIaCredentials ? 'Connected' : 'Not connected',
            value: settings.hasIaCredentials ? 'Manage' : 'Connect',
            child: const IaCredentialsSetting(),
          ),
        ],
        // Save Sync is Android only, as the Tools menu gates it.
        if (Platform.isAndroid) ...[
          const SettingsHeader('Save Sync'),
          const SettingsExpandRow(
            title: 'Recipes source',
            subtitle: 'Where Save Sync reads game recipes from. Empty: the repo on GitHub',
            value: 'Change',
            child: SaveRecipesSourceSetting(),
          ),
        ],
      ];
    case SettingsSection.sports:
      return const [
        SettingsHeader('Roster patcher'),
        BoolSettingRow(
          settingKey: AppSettings.autoApplyFormations,
          defaultValue: true,
          title: 'Auto-apply saved formations',
          subtitle: 'When fetching a roster, reuse the formation saved for the same club',
        ),
      ];
    case SettingsSection.storage:
      final metadata = library && ref.watch(launchboxProvider.select((s) => s.manifest != null));
      return [
        const SettingsHeader('Caches'),
        if (library) const ToolsSetting(console: null),
        if (metadata) const _RemoveLaunchboxRow(),
        const SportsCacheSettings(),
        if (Platform.isAndroid && !Handheld.current) ...[const SettingsHeader('Permissions'), const PermissionsSetting()],
      ];
  }
}

class _RemoveLaunchboxRow extends ConsumerWidget {
  const _RemoveLaunchboxRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importing = ref.watch(launchboxProvider.select((s) => s.importing));
    return SettingsActionRow(
      title: 'LaunchBox metadata',
      subtitle: 'Removing it turns metadata off',
      action: 'Remove',
      danger: true,
      // Deleting under a running import would only have it write the files back.
      onPressed: importing ? null : () => confirmLaunchboxTurnOff(context, ref),
    );
  }
}

/// [console]'s own settings: each says whether it follows Downloads or is
/// changed here (with Reset, X on a controller), plus its conversion, sign-in
/// and cache.
List<Widget> consoleSettingsRows(Console console, WidgetRef ref) {
  ref.watch(settingsProvider);
  final notifier = ref.read(settingsProvider.notifier);
  final changed = notifier.changedKeys(console.id);
  return [
    if (changed.isEmpty)
      const SettingsInfo('This console follows Downloads. Anything changed here is marked Changed, with Reset to follow Downloads again.')
    else
      SettingsActionRow(
        title: '${_changesCount(changed.length)} from Downloads',
        subtitle: 'Reset puts one back; X resets the focused row',
        action: 'Reset all ${changed.length}',
        onPressed: () => notifier.resetConsoleSettings(console.id, changed),
      ),
    const SettingsHeader('Downloads'),
    DownloadFolderRow(console: console),
    BoolSettingRow(settingKey: AppSettings.autoExtract, defaultValue: true, title: 'Extract archives', console: console),
    if (notifier.getAutoExtract(console.id))
      BoolSettingRow(settingKey: AppSettings.extractToFolder, defaultValue: false, title: 'Extract into a subfolder', console: console, indent: true),
    DiscGroupingSetting(console: console),
    if (console.applicableHandlers.isNotEmpty) ...[
      const SettingsHeader('Conversion'),
      HandlerSetting(console: console),
      if (notifier.activeHandler(console.id) == GameHandler.nszDecompress) const SettingsPanel(indent: true, child: NszSetting()),
    ],
    if (console.hasTokenAuth) ...[
      const SettingsHeader('Authentication'),
      SettingsPanel(child: ConsoleAuthSetting(console: console)),
    ],
    const SettingsHeader('Storage'),
    ToolsSetting(console: console),
  ];
}
