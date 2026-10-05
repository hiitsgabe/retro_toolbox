import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/services/sports_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';

/// The list of roster-patchable games, loaded once from the library and cached.
/// Both the sports grid and the per-sport games grid read from this — level 2
/// filters the cached list, so it never re-fetches.
// ponytail: FutureProvider is enough for load-once + cache; upgrade to a
// StateNotifier only if the list needs mutation (e.g. user-added patchers).
final patchersProvider = FutureProvider<List<PatcherInfo>>(
    (ref) async => visiblePatchers(await SportsService.listPatchers(), handheld: Handheld.current));

/// Disc-image patches too heavy for Linux handhelds (1-2 GB RAM): a PS1 patch
/// was OOM-killed on one, and PS2 games don't run on them anyway.
const handheldHiddenPlatforms = {'psx', 'ps2'};

List<PatcherInfo> visiblePatchers(List<PatcherInfo> all, {required bool handheld}) =>
    handheld ? all.where((p) => !handheldHiddenPlatforms.contains(p.platform)).toList() : all;
