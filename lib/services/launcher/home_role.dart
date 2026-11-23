import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';

/// The switch that makes Retro Toolbox the home app, in the launcher wizard
/// and the Launcher mode card.
const homeSwitchTitle = 'Use Retro Toolbox as the home screen';

/// Why that switch is off with dual screen on Main on bottom: moving the main
/// screen would end the home app and start a second one.
const homeLockedReason = 'Not with dual screen on Main on bottom';

/// Why the dual screen card's Main on bottom is off while Retro Toolbox is
/// the home app.
const mainOnBottomLockedReason = 'Main on bottom is off while Retro Toolbox is the home screen';

/// Retro Toolbox as Android's home app: asks Android for it, gives it up,
/// and keeps `LaunchConfig.home` to what Android says, since the user can
/// pick another home app in system Settings at any time.
class HomeRole {
  const HomeRole({required this.channel, required this.config, required this.available});

  final LauncherChannel channel;
  final LaunchConfigNotifier config;

  /// Android, where launching works: anywhere else nothing is asked.
  final bool available;

  /// True once Retro Toolbox is the home app. The user may say no, which
  /// leaves `home` off.
  Future<bool> turnOn() async {
    if (!available) return false;
    final held = await channel.setHome(true);
    await config.setHome(held);
    return held;
  }

  /// No longer offered as a home app: Android goes back to the previous one,
  /// or asks.
  Future<void> turnOff() async {
    if (available) await channel.setHome(false);
    await config.setHome(false);
  }

  /// `home` as Android has it now.
  Future<void> sync() async {
    if (!available) return;
    await config.setHome(await channel.isHomeHeld());
  }
}
