import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/screens/launcher_wizard_screen.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/services/launcher/home_role.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launcher_gate.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/launcher_wizard_plan.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/utils/server_mode.dart';
import 'package:retro_toolbox/widgets/kit/row_menu_sheet.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
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
/// Set up, and a line per console with a default emulator.
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
      for (final id in config.defaults.keys)
        if (consoles[id] != null) DefaultEmulatorRow(console: consoles[id]!, title: consoles[id]!.name),
    ]);
  }
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
