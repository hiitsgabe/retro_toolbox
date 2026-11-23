import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/game_launcher.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_overrides.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_store.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/services/launcher/launcher_gate.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/utils/server_mode.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';

/// Whether this build launches games at all.
final launcherAvailableProvider = Provider<bool>((ref) => launcherSupported(
      isAndroid: Platform.isAndroid,
      isDesktop: Platform.isLinux || Platform.isMacOS || Platform.isWindows,
      handheld: Handheld.current,
      server: ServerMode.current,
    ));

final launchPresetStoreProvider = Provider<LaunchPresetStore>((ref) => LaunchPresetStore(
      url: LaunchPresetsSource.resolve(),
      seed: () => rootBundle.loadString(LaunchPresetStore.seedAsset),
      supportDir: getApplicationSupportDirectory,
    ));

/// Starts the background preset download once per session; reading it again
/// does nothing. The download is for the next session's load.
final presetRefreshProvider = Provider<void>((ref) {
  unawaited(ref.read(launchPresetStoreProvider).refresh());
});

final emulatorDetectorProvider = Provider<EmulatorDetector>((ref) => EmulatorDetector());

final launcherChannelProvider = Provider<LauncherChannel>((ref) => const LauncherChannel());

/// The presets and what of them is installed, detected on first use and kept
/// for the session. "Detect again" invalidates it.
final launcherSessionProvider = FutureProvider<LauncherSession>((ref) async {
  final file = await ref.read(launchPresetStoreProvider).load();
  final detected = await ref.read(emulatorDetectorProvider).detect(file.presets);
  return LauncherSession(presets: file.presets, detected: detected);
});

typedef GameSystem = ({String? slug, String name});

/// A catalog console's art slug, which presets are keyed by, and its name.
final gameSystemProvider = Provider.family<GameSystem, String>((ref, consoleId) {
  final console = CatalogService.consoleByIdSync(consoleId);
  return (slug: console == null ? null : consoleArtSlug(console), name: console?.name ?? consoleId);
});

final launchOverridesProvider = StateNotifierProvider<LaunchOverridesNotifier, Map<String, LaunchChoice>>(
  (ref) => LaunchOverridesNotifier(LaunchOverridesStore(supportDir: getApplicationSupportDirectory)),
);

/// The emulator that opens [game]: its per-game override, else the one
/// detected emulator that covers its system. Null when none or several
/// cover it, or while detection runs. Slice 2 puts the system defaults
/// between the two.
final resolveChoiceProvider = Provider.family<LaunchChoice?, Game>((ref, game) {
  final override = ref.watch(launchOverridesProvider)[game.gameId];
  if (override != null) return override;
  final session = ref.watch(launcherSessionProvider).valueOrNull;
  final covering = session?.covering(ref.watch(gameSystemProvider(game.consoleId)).slug) ?? const [];
  return covering.length == 1 ? covering.single.choice : null;
});

/// [game]'s files on disk, or null when it has none.
final ownedGameProvider = FutureProvider.autoDispose.family<OwnedGame?, Game>((ref, game) async {
  final dir = ref.read(settingsProvider.notifier).getDownloadDir(game.consoleId);
  if (dir.isEmpty) return null;
  final presence = await ref.read(librarySnapshotProvider(dir).notifier).getStatus(game.filename);
  final snapshot = ref.read(librarySnapshotProvider(dir))[dir];
  return snapshot == null ? null : OwnedGame.fromPresence(game, dir, presence, snapshot);
});

final gameLauncherProvider = FutureProvider<GameLauncher>((ref) async {
  final session = await ref.watch(launcherSessionProvider.future);
  return GameLauncher(session: session, systemSlugFor: (consoleId) => ref.read(gameSystemProvider(consoleId)).slug);
});
