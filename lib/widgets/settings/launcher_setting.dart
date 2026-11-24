import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/screens/launcher_command_screen.dart';
import 'package:retro_toolbox/screens/launcher_wizard_screen.dart';
import 'package:retro_toolbox/screens/settings_screen.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/services/launcher/home_role.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launcher_gate.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/launcher_wizard_plan.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/utils/server_mode.dart';
import 'package:retro_toolbox/widgets/kit/row_menu_sheet.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/switch_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';

/// The Launcher mode card shows where launching works: Android or desktop,
/// never the PortMaster handheld or the Docker server.
bool showLauncherCard({required bool isAndroid, required bool isDesktop, required bool handheld, required bool server}) =>
    launcherSupported(isAndroid: isAndroid, isDesktop: isDesktop, handheld: handheld, server: server);

/// [showLauncherCard] for this build, as a provider tests can set.
final launcherCardProvider = Provider<bool>((ref) => showLauncherCard(
      isAndroid: Platform.isAndroid,
      isDesktop: Platform.isLinux || Platform.isMacOS || Platform.isWindows,
      handheld: Handheld.current,
      server: ServerMode.current,
    ));

/// Pushes the launcher wizard; true when it finished.
Future<bool?> openLauncherWizard(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<bool>(fullscreenDialog: true, builder: (_) => const LauncherWizardScreen()));

/// Settings > Library: the mode switch, on Android the home screen switch,
/// Set up, and Consoles, a page of its own with each console's emulator and
/// folder choice and the emulators added by hand.
class LauncherSetting extends ConsumerWidget {
  const LauncherSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(launchConfigProvider);
    final consoles = ref.watch(appStateProvider.select((s) => s.consoles));
    final mainOnBottom = ref.watch(dualScreenProvider.select((s) => s.mode)) == DualScreenMode.mainOnBottom;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SettingsSwitchRow(
        title: 'Launcher mode',
        subtitle: 'Play opens the games you have in an emulator',
        value: config.enabled,
        onChanged: (on) async {
          // With no console set up there is nothing to launch with: the
          // wizard asks first and turns the mode on at Finish.
          if (on && config.defaults.isEmpty) {
            await openLauncherWizard(context);
            return;
          }
          await ref.read(launchConfigProvider.notifier).setEnabled(on);
        },
      ),
      if (config.enabled && ref.watch(homeRoleAvailableProvider))
        SettingsSwitchRow(
          title: homeSwitchTitle,
          subtitle: mainOnBottom ? homeLockedReason : 'The Home button opens your games',
          value: config.home,
          onChanged: mainOnBottom
              ? null
              : (on) {
                  final role = ref.read(homeRoleProvider);
                  if (on) {
                    role.turnOn();
                  } else {
                    role.turnOff();
                  }
                },
        ),
      SettingsActionRow(
        title: 'Emulators',
        subtitle: 'Find the installed ones and pick one per console',
        action: 'Set up',
        onPressed: () => openLauncherWizard(context),
      ),
      SettingsValueRow(
        key: const ValueKey('launcher-consoles'),
        title: 'Consoles',
        subtitle: 'The emulator of each console, its folders, the emulators you added',
        value: '${[for (final id in config.defaults.keys) if (consoles[id] != null) id].length} set',
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LauncherConsolesPage())),
      ),
    ]);
  }
}

/// Launcher mode's page under Settings: a console with a default emulator or
/// games on disk gets its emulator and its folder choice, then the emulators
/// added by hand, each with its menu.
class LauncherConsolesPage extends ConsumerWidget {
  const LauncherConsolesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(launchConfigProvider);
    final shown = [
      for (final c in ref.watch(appStateProvider.select((s) => s.consolesList)))
        if (config.defaults.containsKey(c.id) || ref.watch(gamesOnDiskProvider(c.id)).valueOrNull == true) c,
    ];
    final session = ref.watch(launcherSessionProvider).valueOrNull;
    return Scaffold(
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SettingsTopBar(crumbs: ['Launcher mode', 'Consoles'], back: true, page: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (shown.isEmpty) const SettingsHeader('No console with games or an emulator yet', top: 4),
                for (final c in shown) ...[
                  SettingsHeader(c.name, top: c == shown.first ? 4 : 14),
                  DefaultEmulatorRow(console: c, title: 'Emulator'),
                  FolderGamesRow(console: c),
                ],
                if (config.manual.isNotEmpty) ...[
                  const SettingsHeader('Added by you', top: 14),
                  for (final m in config.manual)
                    SettingsValueRow(
                      key: ValueKey('launcher-manual ${m.id}'),
                      title: m.label,
                      subtitle: session != null && session.detectedFor(m.id) == null ? 'Not found on this device' : null,
                      value: m.isGeneric ? 'Just open the file' : (session?.preset(m.recipe)?.name ?? m.recipe),
                      onTap: () => _manualMenu(context, ref, m),
                    ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _manualMenu(BuildContext context, WidgetRef ref, ManualEmulator m) => showRowMenu(context, title: m.label, subtitle: 'Added by you', items: [
        if (m.isGeneric) RowMenuItem('Edit command', () => editManualCommand(context, ref, m), icon: Icons.terminal, subtitle: 'How the game is handed to it'),
        RowMenuItem(
          'Remove',
          () => ref.read(removeManualEmulatorProvider)(m.id),
          icon: Icons.delete_outline,
          destructive: true,
          subtitle: 'Consoles and games set to it choose again',
        ),
      ]);
}

/// Whether a folder in [console]'s library can be a game. Off for a console
/// that keeps add-ons in folders (Switch updates and DLC), so no folder shows
/// as a game of its own.
class FolderGamesRow extends ConsumerWidget {
  const FolderGamesRow({super.key, required this.console});

  final Console console;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingsSwitchRow(
        key: ValueKey('folder-games ${console.id}'),
        title: 'Folders are games',
        subtitle: 'Off: a folder in its library is never a game, as for Switch updates and DLC',
        value: ref.watch(launchConfigProvider.select((c) => c.folderGames(console.id))),
        onChanged: (on) => ref.read(launchConfigProvider.notifier).setFolderGames(console.id, on),
      );
}

/// A console's default emulator, which a menu of the detected ones that open
/// it changes; "None" drops it. In the card under the console's name, and on
/// the console's own page as "Default emulator".
class DefaultEmulatorRow extends ConsumerWidget {
  const DefaultEmulatorRow({super.key, required this.console, this.title = 'Default emulator'});

  final Console console;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(launcherSessionProvider).valueOrNull;
    final choice = ref.watch(launchConfigProvider.select((c) => c.defaults[console.id]));
    return SettingsValueRow(
      key: ValueKey('default-emulator ${console.id}'),
      title: title,
      subtitle: choice != null && session != null && session.detectedFor(choice.presetId) == null ? 'Not found on this device: Play uses another one' : null,
      value: choice == null ? 'None' : choiceName(session, choice),
      onTap: session == null ? null : () => _choose(context, ref, session),
    );
  }

  Future<void> _choose(BuildContext context, WidgetRef ref, LauncherSession session) {
    final config = ref.read(launchConfigProvider.notifier);
    final slug = ref.read(gameSystemProvider(console.id)).slug;
    void set(LaunchChoice? choice) => config.setDefault(console.id, choice);
    return showRowMenu(context, title: console.name, subtitle: 'Opens its games', items: [
      for (final d in session.covering(slug))
        // RetroArch: one entry per core, so the core is chosen here too.
        for (final core in session.preset(d.presetId)?.usesRetroarchCore ?? false ? session.preset(d.presetId)!.systems[slug]!.cores : const <String?>[null])
          RowMenuItem(
            core == null ? d.label : '${d.label} ($core)',
            () => set(LaunchChoice(presetId: d.presetId, variant: d.variant, core: core)),
          ),
      RowMenuItem('None', () => set(null), subtitle: 'Play asks when more than one emulator opens it'),
    ]);
  }
}
