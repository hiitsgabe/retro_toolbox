import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:roms_downloader/models/patcher_info.dart';
import 'package:roms_downloader/models/roster_doc.dart';
import 'package:roms_downloader/services/python_worker.dart';

/// Drives the retro_roster_patcher library over the shared [PythonWorker].
///
/// Data-returning jobs hand the worker an `output_file`; we read and parse it
/// after the job reports DONE. The fetched-rosters JSON is deliberately kept on
/// disk so [patchRom] can reuse it without re-fetching.
class SportsService {
  static Future<String> _cacheDir() async {
    final dir = p.join((await getApplicationSupportDirectory()).path, 'rrp_cache');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  static File _tmp(String name) =>
      File(p.join(Directory.systemTemp.path, '${name}_${DateTime.now().microsecondsSinceEpoch}.json'));

  static Future<dynamic> _runData({
    required String tag,
    required Map<String, dynamic> job,
    required File outputFile,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
    bool deleteAfter = true,
  }) async {
    await PythonWorker.runJob(
      tag: tag,
      job: {...job, 'output_file': outputFile.path},
      onProgress: onProgress,
      onStatus: onStatus,
    );
    final decoded = jsonDecode(await outputFile.readAsString());
    if (deleteAfter) {
      try {
        await outputFile.delete();
      } catch (_) {}
    }
    return decoded;
  }

  static Future<List<PatcherInfo>> listPatchers() async {
    final out = _tmp('patchers');
    final data = await _runData(tag: 'list_patchers', job: {'type': 'list_patchers'}, outputFile: out);
    return (data as List)
        .map((e) => PatcherInfo.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<List<League>> listLeagues() async {
    final out = _tmp('leagues');
    final data = await _runData(tag: 'list_leagues', job: {'type': 'list_leagues'}, outputFile: out);
    return (data as List)
        .map((e) => League.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// User-defined leagues, read from a JSON file in app support. Missing or
  /// malformed file yields an empty list — custom leagues are optional.
  static Future<File> _customLeaguesFile() async {
    final dir = (await getApplicationSupportDirectory()).path;
    return File(p.join(dir, 'sports_custom_leagues.json'));
  }

  static Future<List<League>> loadCustomLeagues() async {
    try {
      final f = await _customLeaguesFile();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      return (data as List)
          .map((e) => League.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Validates and copies a user-picked JSON file into app support.
  static Future<void> importCustomLeagues(String sourcePath) async =>
      importCustomLeaguesJson(await File(sourcePath).readAsString());

  /// Validates a leagues JSON string (array, or a single league object) and
  /// stores it. Throws [FormatException] on the wrong shape.
  static Future<void> importCustomLeaguesJson(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    final raw = decoded is List ? decoded : [decoded];
    for (final e in raw) {
      if (e is! Map || e['id'] == null || e['code'] == null || e['name'] == null) {
        throw const FormatException('Each league needs id, code and name');
      }
    }
    await (await _customLeaguesFile()).writeAsString(jsonEncode(raw));
  }

  static Future<RomInfo> analyzeRom({required String gameId, required String romPath}) async {
    final out = _tmp('rominfo');
    final data = await _runData(
      tag: 'analyze_${gameId.hashCode.abs()}',
      job: {'type': 'sports_analyze', 'game_id': gameId, 'rom_path': romPath, 'cache_dir': await _cacheDir()},
      outputFile: out,
    );
    return RomInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Fetches rosters and returns the parsed data plus the on-disk JSON path to
  /// feed back into [patchRom].
  static Future<(LeagueData, String)> fetchRosters({
    required String gameId,
    required String provider,
    required int season,
    League? league,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    final out = _tmp('rosters');
    final data = await _runData(
      tag: 'fetch_${gameId.hashCode.abs()}',
      job: {
        'type': 'sports_fetch',
        'game_id': gameId,
        'provider': provider,
        'season': season,
        'league_id': league?.id,
        if (league != null) 'league': league.toJson(),
        'cache_dir': await _cacheDir(),
      },
      outputFile: out,
      onProgress: onProgress,
      onStatus: onStatus,
      deleteAfter: false,
    );
    return (LeagueData.fromJson(Map<String, dynamic>.from(data as Map)), out.path);
  }

  /// Loads the full, editable roster document from a fetched rosters file.
  static Future<RosterDoc> loadRoster(String path) async {
    final data = jsonDecode(await File(path).readAsString());
    return RosterDoc.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Writes an edited roster document to a temp file for patching.
  static Future<String> saveRoster(RosterDoc doc) async {
    final f = _tmp('rosters_edited');
    await f.writeAsString(jsonEncode(doc.toJson()));
    return f.path;
  }

  static Future<PatchResult> patchRom({
    required String gameId,
    required String provider,
    required String romPath,
    required String outputPath,
    required String rostersFile,
    List<SlotMapping>? slotMapping,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    final out = _tmp('patchresult');
    final data = await _runData(
      tag: 'patch_${gameId.hashCode.abs()}',
      job: {
        'type': 'sports_patch',
        'game_id': gameId,
        'provider': provider,
        'rom_path': romPath,
        'output_path': outputPath,
        'rosters_file': rostersFile,
        'slot_mapping': slotMapping?.map((m) => m.toJson()).toList(),
        'cache_dir': await _cacheDir(),
      },
      outputFile: out,
      onProgress: onProgress,
      onStatus: onStatus,
    );
    return PatchResult.fromJson(Map<String, dynamic>.from(data as Map));
  }
}
