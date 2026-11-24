import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/style_provider.dart';
import 'package:retro_toolbox/services/catalog_logins.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/services/key_files.dart';
import 'package:retro_toolbox/services/storage_usage.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/settings/accounts_rows.dart';
import 'package:retro_toolbox/widgets/settings/catalog_source_setting.dart';
import 'package:retro_toolbox/widgets/settings/version_grouping_setting.dart';
import 'package:retro_toolbox/widgets/settings/dual_screen_setting.dart';
import 'package:retro_toolbox/widgets/settings/extra_servers_setting.dart';
import 'package:retro_toolbox/widgets/settings/favorites_settings.dart';
import 'package:retro_toolbox/widgets/settings/handler_setting.dart';
import 'package:retro_toolbox/widgets/settings/keys_setting.dart';
import 'package:retro_toolbox/widgets/settings/launchbox_setting.dart';
import 'package:retro_toolbox/widgets/settings/launcher_setting.dart';
import 'package:retro_toolbox/widgets/settings/library_setting.dart';
import 'package:retro_toolbox/widgets/settings/network_address_setting.dart';
import 'package:retro_toolbox/widgets/settings/on_screen_keyboard_setting.dart';
import 'package:retro_toolbox/widgets/settings/permissions_setting.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/stepper_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';
import 'package:retro_toolbox/widgets/settings/setting_rows.dart';
import 'package:retro_toolbox/widgets/settings/style_setting.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';
import 'package:retro_toolbox/widgets/settings/updates_setting.dart';
import 'package:retro_toolbox/widgets/settings/sports_cache_settings.dart';
import 'package:retro_toolbox/widgets/settings/tools_setting.dart';

/// The parts of Settings, in rail order. [icon]: SVG elements for SettingsIcon;
/// [pixel]: the same in the pixel set.
enum SettingsSection {
  library('Library', 'Catalog, metadata, favorites', SettingsIcons.library, PixelIcons.library),
  style('Style', 'Background and cards', SettingsIcons.style, PixelIcons.style),
  downloads('Downloads', 'Folder, extraction, discs', SettingsIcons.downloads, PixelIcons.downloads),
  consoles('Consoles', 'Changes for one console', SettingsIcons.consoles, PixelIcons.consoles),
  screens('Screens & controls', 'Dual screen, keyboard', SettingsIcons.screens, PixelIcons.screens),
  network('Network & servers', 'Address, install servers', SettingsIcons.network, PixelIcons.network),
  keys('Keys', 'Switch keys, 3DS boot9', SettingsIcons.keys, PixelIcons.keys),
  accounts('Accounts & sync', 'Catalog logins, Google', SettingsIcons.accounts, PixelIcons.accounts),
  sports('Sports', 'Roster patcher', SettingsIcons.sports, PixelIcons.roster),
  storage('Storage', 'Caches, space, permissions', SettingsIcons.storage, PixelIcons.storage);

  const SettingsSection(this.label, this.hint, this.icon, this.pixel);

  final String label;
  final String hint;
  final String icon;
  final PixelGlyph pixel;
}

/// A section's icon: the pixel one in a style that draws with the pixel set,
/// else the line one.
class SectionIcon extends StatelessWidget {
  const SectionIcon(this.section, {super.key, this.size = 20, this.color});

  final SettingsSection section;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => StyleTokens.of(context).pixelIcons
      ? PixelIcon(section.pixel, size: size, color: color)
      : SettingsIcon(section.icon, size: size, color: color);
}

/// Where a settings row can send the user: a console's page, another section.
class SettingsLinks {
  const SettingsLinks({required this.openConsole, required this.openSection});

  final ValueChanged<Console> openConsole;
  final ValueChanged<SettingsSection> openSection;
}

String _plural(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// How a console's change reads in its line in Consoles.
String _changeName(String key, Console console, SettingsNotifier n) {
  switch (key) {
    case AppSettings.downloadDir:
      return 'folder';
    case AppSettings.autoExtract:
      return 'extraction';
    case AppSettings.extractToFolder:
      return 'subfolder';
    case AppSettings.groupVersions:
      return 'grouping';
    case AppSettings.downloadAllDiscs:
      return 'every disc';
    case AppSettings.additionalHandler:
      final h = n.activeHandler(console.id);
      return h == null ? 'no conversion' : 'conversion to ${h.output.substring(1).toUpperCase()}';
    case AppSettings.chdIsoAsCd:
      return 'CHD type';
    case AppSettings.updatesDir:
      return 'updates folder';
    case AppSettings.updateDecompress:
      return 'update unpacking';
    case AppSettings.updateHandler:
      return 'update conversion';
    default:
      return key;
  }
}

String _changesLine(List<String> keys, Console console, SettingsNotifier n) {
  final names = keys.map((k) => _changeName(k, console, n)).join(', ');
  return names.isEmpty ? names : names[0].toUpperCase() + names.substring(1);
}

/// What Settings > Accounts lists for the loaded catalog: the Internet
/// Archive consoles and the token logins, each from the consoles alone.
({List<Console> archive, List<CatalogLogin> logins}) _catalogAccounts(WidgetRef ref, bool library) {
  if (!library) return (archive: const [], logins: const []);
  final consoles = ref.watch(appStateProvider.select((s) => s.consolesList));
  return (archive: internetArchiveConsoles(consoles), logins: catalogLogins(consoles));
}

/// The rows of [section], built from what is on now; empty when it has none
/// to show (the section is then left out). Watches what decides that.
List<Widget> settingsSectionRows(SettingsSection section, WidgetRef ref, {required SettingsLinks links}) {
  final settings = ref.watch(settingsProvider);
  final library = settings.isLibraryEnabled;
  final notifier = ref.read(settingsProvider.notifier);
  switch (section) {
    case SettingsSection.library:
      return [
        const SettingsHeader('Games Library'),
        const LibrarySetting(),
        if (library) ...[
          const CatalogSourceRow(),
          const SettingsHeader('Grouping'),
          const VersionGroupingSetting(console: null),
          const SettingsHeader('Game metadata (LaunchBox)'),
          const LaunchboxSetting(),
          const SettingsHeader('Favorites'),
          const FavoritesRows(),
          if (ref.watch(launcherCardProvider)) ...[const SettingsHeader('Launcher mode'), const LauncherSetting()],
        ],
      ];
    case SettingsSection.style:
      return const [StyleSettingRows()];
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
              key: ValueKey('console ${c.id}'),
              title: c.name,
              subtitle: _changesLine(changed[c.id]!, c, notifier),
              value: _plural(changed[c.id]!.length, 'change'),
              onTap: () => links.openConsole(c),
            ),
        ],
        if (plain.isNotEmpty) ...[
          const SettingsHeader('Using the defaults'),
          for (final c in plain)
            SettingsValueRow(
              key: ValueKey('console ${c.id}'),
              title: c.name,
              subtitle: 'Follows Downloads',
              value: 'Defaults',
              onTap: () => links.openConsole(c),
            ),
        ],
      ];
    case SettingsSection.screens:
      final dual = ref.watch(dualScreenCardProvider);
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
    case SettingsSection.keys:
      return [
        const SettingsInfo('Files the converters need. Each one is copied into the app, so the original can be moved or deleted.'),
        for (final k in KeyFile.values) ...[SettingsHeader(k.header), KeyFileRow(file: k)],
      ];
    case SettingsSection.accounts:
      final (:archive, :logins) = _catalogAccounts(ref, library);
      final saveSync = ref.watch(saveSyncAvailableProvider);
      final catalogRows = archive.isNotEmpty || logins.isNotEmpty;
      return [
        if (catalogRows) ...[
          const SettingsInfo('Every login the loaded catalog asks for shows here, and changes with the catalog.'),
          const SettingsHeader('Catalog logins'),
          if (archive.isNotEmpty) InternetArchiveRow(count: archive.length),
          for (final l in logins) CatalogLoginRow(login: l),
        ],
        if (saveSync) ...[
          const SettingsHeader('Save Sync'),
          const GoogleDriveRow(),
          const RecipesSourceRow(),
        ],
      ];
    case SettingsSection.sports:
      return const [
        SettingsHeader('Roster patcher'),
        BoolSettingRow(
          settingKey: AppSettings.autoApplyFormations,
          defaultValue: true,
          title: 'Auto-apply saved formations',
          subtitle: 'Reuse the formation saved for the same club',
        ),
      ];
    case SettingsSection.storage:
      final metadata = library && ref.watch(launchboxProvider.select((s) => s.manifest != null));
      final usage = ref.watch(storageUsageProvider).valueOrNull;
      return [
        const SettingsHeader('Space used'),
        if (library) ToolsSetting(console: null, size: usage?.catalog),
        if (metadata) _RemoveLaunchboxRow(size: usage?.launchbox),
        SportsCacheSettings(size: usage?.sports),
        if (PermissionsSetting.shown) ...[const SettingsHeader('Permissions'), const PermissionsSetting()],
      ];
  }
}

class _RemoveLaunchboxRow extends ConsumerWidget {
  const _RemoveLaunchboxRow({this.size});

  final int? size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importing = ref.watch(launchboxProvider.select((s) => s.importing));
    return SettingsActionRow(
      title: 'LaunchBox metadata',
      subtitle: size != null && size! > 0 ? '${storageSize(size!)}. Removing it turns metadata off' : 'Removing it turns metadata off',
      action: 'Remove',
      danger: true,
      // Deleting under a running import would only have it write the files back.
      onPressed: importing ? null : () => confirmLaunchboxTurnOff(context, ref),
    );
  }
}

/// [section] in one line for the narrow list, from what is set now.
String settingsSectionSummary(SettingsSection section, WidgetRef ref) {
  final settings = ref.watch(settingsProvider);
  final notifier = ref.read(settingsProvider.notifier);
  final library = settings.isLibraryEnabled;
  switch (section) {
    case SettingsSection.library:
      if (!library) return 'Games Library off';
      final lb = ref.watch(launchboxProvider.select((s) => s.manifest != null));
      final favorites = ref.watch(favoritesProvider.select((f) => f.count));
      return 'LaunchBox ${lb ? 'on' : 'off'}, ${_plural(favorites, 'favorite')}';
    case SettingsSection.style:
      final style = ref.watch(styleProvider);
      return '${style.shownBackdrop.kind.label}, ${style.cards.label} cards';
    case SettingsSection.downloads:
      final dir = notifier.getGeneralSetting<String>(AppSettings.downloadDir) ?? '';
      final extract = notifier.getGeneralSetting<bool>(AppSettings.autoExtract) ?? true;
      return [
        dir.isEmpty ? 'No folder' : '/${p.basename(dir)}',
        'extract ${extract ? 'on' : 'off'}',
        '${notifier.getMaxParallelDownloads()} at a time',
      ].join(', ');
    case SettingsSection.consoles:
      final consoles = ref.watch(appStateProvider.select((s) => s.consolesList));
      final n = consoles.where((c) => notifier.changedKeys(c.id).isNotEmpty).length;
      return n == 0 ? 'All follow Downloads' : '${_plural(n, 'console')} changed';
    case SettingsSection.screens:
      final parts = <String>[
        if (ref.watch(dualScreenCardProvider))
          switch (ref.watch(dualScreenProvider.select((s) => s.mode))) {
            DualScreenMode.off => 'One screen',
            DualScreenMode.mainOnTop => 'Main on top',
            DualScreenMode.mainOnBottom => 'Main on bottom',
          },
        if (!Handheld.current) settings.useOnScreenKeyboard ? 'built-in keyboard' : 'system keyboard',
      ];
      final line = parts.join(', ');
      return line.isEmpty ? section.hint : line[0].toUpperCase() + line.substring(1);
    case SettingsSection.network:
      final servers = [
        if (settings.isTinfoilEnabled) 'Tinfoil',
        if (settings.isFbiEnabled) 'FBI',
        if (settings.isFpkgiEnabled) 'FPKGi',
      ];
      return [
        if (!Handheld.current) settings.preferredLocalIp ?? 'Automatic',
        servers.isEmpty ? 'no install servers' : '${servers.join(', ')} on',
      ].join(', ');
    case SettingsSection.keys:
      return [for (final k in KeyFile.values) '${k.short} ${k.pathIn(settings) == null ? 'missing' : 'set'}'].join(', ');
    case SettingsSection.accounts:
      final (:archive, :logins) = _catalogAccounts(ref, library);
      final google = ref.watch(saveSyncAvailableProvider);
      final total = (archive.isNotEmpty ? 1 : 0) + logins.length + (google ? 1 : 0);
      final signedIn = (archive.isNotEmpty && settings.hasIaCredentials ? 1 : 0) +
          logins.where((l) => l.signedInWith(settings)).length +
          (google && ref.watch(saveSyncProvider.select((s) => s.hubKind)) == HubKind.drive ? 1 : 0);
      return '${_plural(total, 'account')}, $signedIn signed in';
    case SettingsSection.sports:
      return (notifier.getGeneralSetting<bool>(AppSettings.autoApplyFormations) ?? true) ? 'Auto-apply formations' : 'Formations not auto-applied';
    case SettingsSection.storage:
      final usage = ref.watch(storageUsageProvider).valueOrNull;
      return usage == null || usage.total == 0 ? section.hint : '${storageSize(usage.total)} of caches';
  }
}

/// [console]'s own settings: each says whether it follows Downloads or is
/// changed here (with Reset, X on a controller), plus its conversion and its
/// catalog cache. Logins live in Accounts.
List<Widget> consoleSettingsRows(Console console, WidgetRef ref, {VoidCallback? onOpenKeys}) {
  ref.watch(settingsProvider);
  final notifier = ref.read(settingsProvider.notifier);
  final changed = notifier.changedKeys(console.id);
  return [
    _ConsoleIntro(console: console, changed: changed),
    const SettingsHeader('Downloads', top: 14),
    DownloadFolderRow(console: console),
    BoolSettingRow(settingKey: AppSettings.autoExtract, defaultValue: true, title: 'Extract archives', console: console),
    if (notifier.getAutoExtract(console.id))
      BoolSettingRow(settingKey: AppSettings.extractToFolder, defaultValue: false, title: 'Extract into a subfolder', console: console, indent: true),
    VersionGroupingSetting(console: console),
    if (console.applicableHandlers.isNotEmpty) ...[
      const SettingsHeader('Conversion', top: 14),
      HandlerSetting(console: console, onOpenKeys: onOpenKeys),
    ],
    if (console.hasUpdates) ...[
      const SettingsHeader('Updates', top: 14),
      UpdatesSetting(console: console),
    ],
    if (ref.watch(launcherCardProvider) && ref.watch(launchConfigProvider.select((c) => c.enabled))) ...[
      const SettingsHeader('Launcher', top: 14),
      DefaultEmulatorRow(console: console),
      FolderGamesRow(console: console),
    ],
    const SettingsHeader('Storage', top: 14),
    _ConsoleCacheRow(console: console),
  ];
}

class _ConsoleCacheRow extends ConsumerWidget {
  const _ConsoleCacheRow({required this.console});

  final Console console;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToolsSetting(console: console, size: ref.watch(storageUsageProvider).valueOrNull?.consoles[console.id]);
}

/// The line on top of a console's page, with Reset all when it changes
/// something.
class _ConsoleIntro extends ConsumerWidget {
  const _ConsoleIntro({required this.console, required this.changed});

  final Console console;
  final List<String> changed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4 + settingsHalfGap, 4, 8 + settingsHalfGap),
      child: Row(children: [
        Expanded(
          child: Text(
            'Rows marked Changed differ from Downloads. Reset puts one back; everything else follows Downloads as it changes.',
            style: TextStyle(fontSize: 13, height: 1.5, color: scheme.onSurfaceVariant),
          ),
        ),
        if (changed.isNotEmpty) ...[
          const SizedBox(width: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              side: BorderSide(color: scheme.outline),
              foregroundColor: scheme.onSurface,
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () => ref.read(settingsProvider.notifier).resetConsoleSettings(console.id, changed),
            child: Text('Reset all ${changed.length}'),
          ),
        ],
      ]),
    );
  }
}
