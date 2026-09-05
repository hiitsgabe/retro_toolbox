import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/patcher_info.dart';
import 'package:roms_downloader/services/sports_service.dart';

/// The list of roster-patchable games, loaded once from the library and cached.
/// Both the sports grid and the per-sport games grid read from this — level 2
/// filters the cached list, so it never re-fetches.
// ponytail: FutureProvider is enough for load-once + cache; upgrade to a
// StateNotifier only if the list needs mutation (e.g. user-added patchers).
final patchersProvider =
    FutureProvider<List<PatcherInfo>>((ref) => SportsService.listPatchers());
