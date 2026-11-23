import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_result.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/widgets/game_details/launch_picker.dart';

/// Launching [game] and saying what went wrong, with the fix beside it: the
/// details page's Play and Open with, and a game card in launcher mode. The
/// providers are the ones above [context], read once here, so a launch
/// started from a card that rebuilds meanwhile still reports.
class LaunchFlow {
  LaunchFlow(this.context, this.game, {this.onStarting}) : _c = ProviderScope.containerOf(context, listen: false);

  final BuildContext context;
  final Game game;

  /// The emulator a launch is starting, then null once it returned: the Play
  /// button's label.
  final void Function(String? emulator)? onStarting;

  final ProviderContainer _c;

  /// Launches with the resolved choice; with none (several emulators cover
  /// the system and no override was kept), asks which.
  Future<void> play() async {
    await _c.read(launcherSessionProvider.future);
    final choice = _c.read(resolveChoiceProvider(game));
    if (choice == null) return openWith();
    await launch(choice);
  }

  /// "Open with…": the covering emulators, "Just this once" or "Always for
  /// this game" (the per-game override).
  Future<void> openWith() async {
    final session = await _c.read(launcherSessionProvider.future);
    if (!context.mounted) return;
    final emulators = session.covering(_c.read(gameSystemProvider(game.consoleId)).slug);
    if (emulators.isEmpty) return;
    final picked = await showLaunchPicker(context, session, emulators);
    if (picked == null || !context.mounted) return;
    if (picked.always) _c.read(launchOverridesProvider.notifier).set(game.gameId, picked.emulator.choice);
    await launch(picked.emulator.choice);
  }

  Future<void> launch(LaunchChoice choice) async {
    final session = await _c.read(launcherSessionProvider.future);
    final name = session.detectedFor(choice.presetId)?.label ?? session.preset(choice.presetId)?.name ?? choice.presetId;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    onStarting?.call(name);
    LaunchResult result;
    try {
      final owned = await _c.read(ownedGameProvider(game).future);
      final launcher = await _c.read(gameLauncherProvider.future);
      result = owned == null ? const LaunchResult(LaunchCode.romUnreadable) : await launcher.launch(owned, choice);
    } finally {
      if (context.mounted) onStarting?.call(null);
    }
    _report(messenger, result, name);
  }

  void _report(ScaffoldMessengerState? messenger, LaunchResult result, String emulator) {
    final (:text, :fix) = result.describe(emulator);
    if (text == null) return;
    final action = switch (fix) {
      LaunchFix.none => null,
      LaunchFix.detectAgain => SnackBarAction(label: 'Detect again', onPressed: () => _c.read(detectEmulatorsProvider)()),
      LaunchFix.chooseAnother => SnackBarAction(label: 'Choose another', onPressed: () => context.mounted ? openWith() : null),
      LaunchFix.chooseFolder => SnackBarAction(label: 'Choose folder', onPressed: () => context.mounted ? _chooseFolder() : null),
    };
    messenger?.showSnackBar(SnackBar(content: Text(text), action: action));
  }

  /// The library folder, as the setup wizard sets it.
  Future<void> _chooseFolder() async {
    final picked = await pickDirectory(context, title: 'Select download folder');
    if (picked == null) return;
    final notifier = _c.read(settingsProvider.notifier);
    await notifier.saveDownloadDirectory(picked);
    await notifier.setGeneralSetting(AppSettings.downloadDir, picked);
  }
}
