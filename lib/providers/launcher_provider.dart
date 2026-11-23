import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/library_snapshot_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/emulator_detector.dart';
import 'package:retro_toolbox/services/launcher/game_launcher.dart';
import 'package:retro_toolbox/services/launcher/games_on_disk.dart';
import 'package:retro_toolbox/services/launcher/home_role.dart';
import 'package:retro_toolbox/services/launcher/launch_choice.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/services/launcher/launch_overrides.dart';
import 'package:retro_toolbox/services/launcher/launch_preset.dart';
import 'package:retro_toolbox/services/launcher/launch_preset_store.dart';
import 'package:retro_toolbox/services/launcher/launcher_channel.dart';
import 'package:retro_toolbox/services/launcher/launcher_gate.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';
import 'package:retro_toolbox/services/launcher/manual_emulator.dart';
import 'package:retro_toolbox/services/launcher/owned_game.dart';
import 'package:retro_toolbox/services/launcher/owned_library.dart';
import 'package:retro_toolbox/services/pick.dart';
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

/// Launcher mode is on: a build that launches, and the config says so. False
/// until the saved config is in.
final launcherModeProvider = Provider<bool>((ref) => ref.watch(launcherAvailableProvider) && ref.watch(launchConfigProvider.select((c) => c.enabled)));

/// Whether this build can be the device's home app: Android, where
/// launching works.
final homeRoleAvailableProvider = Provider<bool>((ref) => ref.watch(launcherAvailableProvider) && Platform.isAndroid);

final homeRoleProvider = Provider<HomeRole>((ref) => HomeRole(
      channel: ref.watch(launcherChannelProvider),
      config: ref.watch(launchConfigProvider.notifier),
      available: ref.watch(homeRoleAvailableProvider),
    ));

/// Retro Toolbox is the home app: Android, launcher mode on, and HOME on.
final homeModeProvider = Provider<bool>(
  (ref) => ref.watch(homeRoleAvailableProvider) && ref.watch(launcherModeProvider) && ref.watch(launchConfigProvider.select((c) => c.home)),
);

/// `Platform.operatingSystem`, as a provider tests can set: the wizard's
/// Android-only rows and step follow it.
final launcherOsProvider = Provider<String>((ref) => Platform.operatingSystem);

/// Android's internal storage root, `/storage/emulated/<user>`. Android only.
final primaryStorageRootProvider = FutureProvider<String>((ref) => primaryStorageRoot());

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

/// The preset file in use, the seed or the cache, read once a session.
final launchPresetsProvider = FutureProvider<LaunchPresetFile>((ref) => ref.read(launchPresetStoreProvider).load());

/// The detection running now, which a second caller joins: the wizard's
/// step 1 and a session with nothing saved would otherwise both detect.
class _Detection {
  Future<List<DetectedEmulator>>? running;
}

final _detectionProvider = Provider<_Detection>((ref) => _Detection());

/// [fresh] never joins a detection already running: that one read its
/// presets before the caller's change (an emulator just added), so this waits
/// for it and then detects again.
Future<List<DetectedEmulator>> _detect(Ref ref, {bool fresh = false}) async {
  final detection = ref.read(_detectionProvider);
  final stale = fresh ? detection.running : null;
  if (stale != null) {
    try {
      await stale;
    } catch (_) {
      // Its own caller hears of the failure; this one only needs it over.
    }
  }
  return detection.running ??= () async {
    try {
      final file = await ref.read(launchPresetsProvider.future);
      final config = ref.read(launchConfigProvider.notifier);
      // The manual emulators are presets too, and they are in the saved config.
      await config.loaded;
      final presets = _presetsInUse(ref, file.presets, ref.read(launchConfigProvider).manual);
      final detected = await ref.read(emulatorDetectorProvider).detect(presets);
      await config.setDetected(detected);
      return detected;
    } finally {
      detection.running = null;
    }
  }();
}

/// The presets in use: the file's, then one per manual emulator, built for
/// this OS. A generic one takes its consoles' formats from the catalog as it
/// is now: the catalog loads at start, and a slug it does not know yet opens
/// any file.
List<LaunchPreset> _presetsInUse(Ref ref, List<LaunchPreset> file, List<ManualEmulator> manual) {
  if (manual.isEmpty) return file;
  final extensions = manual.any((m) => m.isGeneric) ? ref.read(consoleExtensionsProvider) : const <String, List<String>>{};
  return presetsWithManual(file, manual, os: ref.read(launcherOsProvider), extensions: extensions);
}

/// Runs a detection, keeps it as the config's lastDetected and rebuilds the
/// session on it: wizard step 1, "Detect again", and a resume in launcher
/// mode call it.
final detectEmulatorsProvider = Provider<Future<List<DetectedEmulator>> Function()>((ref) => () async {
      final detected = await _detect(ref);
      ref.invalidate(launcherSessionProvider);
      return detected;
    });

/// Saves a manual emulator, then detects again, so its row comes with what a
/// detection brings (the icon, the version) and the session lists it. The
/// detection is a fresh one: a resume may have started one before the save,
/// which would find everything but the new emulator.
final addManualEmulatorProvider = Provider<Future<void> Function(ManualEmulator manual)>((ref) => (manual) async {
      await ref.read(launchConfigProvider.notifier).addManual(manual);
      await _detect(ref, fresh: true);
      ref.invalidate(launcherSessionProvider);
    });

/// Removes the manual emulator [id] with every console default and per-game
/// override that names it. The overrides are read in first: one dropped
/// before its file loaded would come back with it.
final removeManualEmulatorProvider = Provider<Future<void> Function(String id)>((ref) => (id) async {
      final overrides = ref.read(launchOverridesProvider.notifier);
      await overrides.loaded;
      overrides.dropPreset(id);
      await ref.read(launchConfigProvider.notifier).removeManual(id);
    });

/// The presets and what of them is installed. The detection is the saved
/// lastDetected, so opening a page never detects again; only with none saved
/// yet does this detect, and it saves what it found.
final launcherSessionProvider = FutureProvider<LauncherSession>((ref) async {
  final file = await ref.watch(launchPresetsProvider.future);
  final config = ref.read(launchConfigProvider.notifier);
  // Until the saved config is in, its lastDetected is not known to be empty.
  await config.loaded;
  // A manual emulator added or removed is a preset more or less. Watched only
  // once the saved config is in: watched before, the load itself would mark
  // this build stale while it waits.
  final manual = ref.watch(launchConfigProvider.select((c) => c.manual));
  final state = ref.read(launchConfigProvider);
  final presets = _presetsInUse(ref, file.presets, manual);
  final saved = state.lastDetected;
  return LauncherSession(presets: presets, detected: saved == null ? await _detect(ref) : _asTheFileReads(saved, presets));
});

/// [saved] as the preset file in use has it. The detection may be older than
/// the file: a preset there may open a system it did not, or be gone, and
/// with launcher mode off nothing detects again on its own.
List<DetectedEmulator> _asTheFileReads(List<DetectedEmulator> saved, List<LaunchPreset> presets) => [
      for (final p in presets)
        for (final d in saved)
          if (d.presetId == p.id) d.withSystems(p.systems.keys.toList()),
    ];

typedef GameSystem = ({String? slug, String name});

/// A catalog console's art slug, which presets are keyed by, and its name.
final gameSystemProvider = Provider.family<GameSystem, String>((ref, consoleId) {
  final console = CatalogService.consoleByIdSync(consoleId);
  return (slug: console == null ? null : consoleArtSlug(console), name: console?.name ?? consoleId);
});

/// Each console art slug of the catalog and the formats its consoles' games
/// take on disk, lowercase with no dot, merged where consoles share a slug:
/// what a generic manual emulator opens for a console it was ticked for.
final consoleExtensionsProvider = Provider<Map<String, List<String>>>((ref) {
  final bySlug = <String, Set<String>>{};
  for (final c in ref.watch(appStateProvider.select((s) => s.consoles)).values) {
    final slug = ref.watch(gameSystemProvider(c.id)).slug;
    if (slug == null) continue;
    bySlug.putIfAbsent(slug, () => <String>{}).addAll([
      for (final f in c.onDiskFormats)
        if (f.replaceFirst('.', '').isNotEmpty) f.replaceFirst('.', ''),
    ]);
  }
  return {for (final e in bySlug.entries) e.key: e.value.toList()..sort()};
});

/// Launcher mode's settings: on or off, the console defaults, the last
/// detection.
final launchConfigProvider = StateNotifierProvider<LaunchConfigNotifier, LaunchConfig>((ref) => LaunchConfigNotifier(LaunchConfigStore()));

final launchOverridesProvider = StateNotifierProvider<LaunchOverridesNotifier, Map<String, LaunchChoice>>(
  (ref) => LaunchOverridesNotifier(LaunchOverridesStore(supportDir: getApplicationSupportDirectory)),
);

/// The emulator that opens [game]: its per-game override, else its
/// console's default, else the one detected emulator that covers its system.
/// An override or a default counts while its emulator is detected or
/// detection runs. Null when none or several cover it, or while detection
/// runs with neither.
final resolveChoiceProvider = Provider.family<LaunchChoice?, Game>((ref, game) {
  final override = ref.watch(launchOverridesProvider)[game.gameId];
  final session = ref.watch(launcherSessionProvider).valueOrNull;
  // A choice for an emulator that is gone would fail every Play the same
  // way. It is skipped, not deleted, so it comes back with the emulator.
  bool detected(LaunchChoice c) => session == null || session.detectedFor(c.presetId) != null;
  if (override != null && detected(override)) return override;
  final fallback = ref.watch(launchConfigProvider.select((c) => c.defaults[game.consoleId]));
  if (fallback != null && detected(fallback)) {
    // A default names a preset: the variant is the one installed now, so a
    // move from com.retroarch to com.retroarch.aarch64 keeps it.
    final now = session?.detectedFor(fallback.presetId);
    return now == null ? fallback : LaunchChoice(presetId: fallback.presetId, variant: now.variant, core: fallback.core);
  }
  final covering = session?.covering(ref.watch(gameSystemProvider(game.consoleId)).slug) ?? const [];
  return covering.length == 1 ? covering.single.choice : null;
});

/// The loose games of a console's library dir, by console id, as its last
/// catalog load in launcher mode found them: the catalog writes it, and a
/// launch of a loose game reads its files from it.
final ownedLibraryProvider = StateProvider.family<OwnedLibrary, String>((ref, consoleId) => OwnedLibrary.empty);

/// [game]'s files on disk, or null when it has none.
final ownedGameProvider = FutureProvider.autoDispose.family<OwnedGame?, Game>((ref, game) async {
  final dir = ref.read(settingsProvider.notifier).getDownloadDir(game.consoleId);
  if (dir.isEmpty) return null;
  // A loose game's real names are in the side map: sanitizeForFat may have
  // changed the one its gameId carries.
  if (game.isLocal) return OwnedGame.fromLoose(game, dir, ref.read(ownedLibraryProvider(game.consoleId)).paths);
  final presence = await ref.read(librarySnapshotProvider(dir).notifier).getStatus(game.filename);
  final snapshot = ref.read(librarySnapshotProvider(dir))[dir];
  return snapshot == null ? null : OwnedGame.fromPresence(game, dir, presence, snapshot);
});

/// Whether [consoleId]'s library dir holds any of its games, as
/// [hasGamesOnDisk] counts them; consoles sharing the dir split it by
/// [ownFormats]. Wizard step 2 lists the consoles it holds for.
final gamesOnDiskProvider = FutureProvider.autoDispose.family<bool, String>((ref, consoleId) async {
  final consoles = ref.watch(appStateProvider.select((s) => s.consoles));
  ref.watch(settingsProvider);
  final settings = ref.read(settingsProvider.notifier);
  final console = consoles[consoleId];
  if (console == null) return false;
  final dir = settings.getDownloadDir(consoleId);
  if (dir.isEmpty) return false;
  final sharing = [
    for (final c in consoles.values)
      if (p.equals(settings.getDownloadDir(c.id), dir)) c,
  ];
  return hasGamesOnDisk(dir, ownFormats(console, sharing));
});

final gameLauncherProvider = FutureProvider<GameLauncher>((ref) async {
  final session = await ref.watch(launcherSessionProvider.future);
  return GameLauncher(session: session, systemSlugFor: (consoleId) => ref.read(gameSystemProvider(consoleId)).slug);
});

/// The ROM mode a launch of [game] with its resolved choice would use, for
/// the details page's folder-access hint. Null on desktop, or when nothing
/// would launch.
final launchModeProvider = FutureProvider.autoDispose.family<RomMode?, Game>((ref, game) async {
  final choice = ref.watch(resolveChoiceProvider(game));
  if (choice == null) return null;
  final owned = await ref.watch(ownedGameProvider(game).future);
  final launcher = await ref.watch(gameLauncherProvider.future);
  return owned == null ? null : launcher.modeFor(owned, choice);
});
