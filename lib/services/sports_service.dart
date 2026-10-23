import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/services/python_worker.dart';

/// One league's edited rosters and the run of team slots it fills.
typedef RostersFile = ({String file, int firstSlot, int count});

/// Kit preview PNGs by request key, the kit spec each null (default) KIT
/// stands for (empty from an older worker or library), plus the game's own
/// jersey designs when they were asked for.
typedef KitPreviews = ({Map<String, String> kits, Map<String, Map<String, dynamic>> defaults, List<KitTemplate> templates});

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

  /// The image's slots and per-slot extras; [codes] also asks where those
  /// team codes land, for games that slot teams by code.
  static Future<RomInfo> analyzeRom({required String gameId, required String romPath, List<String> codes = const []}) async {
    final out = _tmp('rominfo');
    final data = await _runData(
      // Each analysis its own progress file: the wizard may ask again while
      // an earlier one still runs.
      tag: 'analyze_${gameId.hashCode.abs()}_${_kitJob++}',
      job: {'type': 'sports_analyze', 'game_id': gameId, 'rom_path': romPath, 'codes': codes, 'cache_dir': await _cacheDir()},
      outputFile: out,
    );
    return RomInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Fetches rosters and returns the parsed data plus the on-disk JSON path to
  /// feed back into [patchRom].
  static Future<(LeagueData, String)> fetchRosters({
    required String gameId,
    required String provider,
    required int? season,
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
        // Null for soccer: the worker picks the league's own current season.
        if (season != null) 'season': season,
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

  /// A fresh folder under the system temp dir for one batch of images.
  static Future<String> _imageDir(String kind) async {
    final dir = p.join(Directory.systemTemp.path, 'rrp_images', '${kind}_${DateTime.now().microsecondsSinceEpoch}');
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// The ROM's current screen art, one PNG per slot: {slot: path}.
  static Future<Map<String, String>> exportImages({required String gameId, required String romPath}) async {
    final out = _tmp('images');
    final data = await _runData(
      tag: 'images_${gameId.hashCode.abs()}',
      job: {
        'type': 'sports_images',
        'game_id': gameId,
        'rom_path': romPath,
        'out_dir': await _imageDir('rom'),
        'cache_dir': await _cacheDir(),
      },
      outputFile: out,
    );
    return Map<String, String>.from(data as Map);
  }

  /// Retro Toolbox-branded art for every slot, with the league and season
  /// drawn in: {slot: path}.
  static Future<Map<String, String>> defaultImages({
    required String gameId,
    required String league,
    required int season,
  }) async {
    final out = _tmp('default_images');
    final data = await _runData(
      tag: 'default_images_${gameId.hashCode.abs()}',
      job: {
        'type': 'sports_default_images',
        'game_id': gameId,
        'league': league,
        'season': season,
        'out_dir': await _imageDir('branded'),
      },
      outputFile: out,
    );
    return Map<String, String>.from(data as Map);
  }

  /// A ZIP of template PNGs for the game's screen art (red borders mark
  /// where the content shows): its path, named `<game_id>-templates.zip`.
  static Future<String> templatesZip(String gameId, {String? romPath}) =>
      _templatesJob(gameId, {if (romPath != null) 'rom_path': romPath});

  /// A ZIP of kit template PNGs for one team [slot]; [template] is the game
  /// design the kit uses, when it uses one.
  static Future<String> kitTemplateZip(String gameId, {required String romPath, required int slot, int? template}) =>
      _templatesJob(gameId, {'kind': 'kits', 'slot': slot, 'which': null, 'template': template, 'rom_path': romPath});

  static Future<String> _templatesJob(String gameId, Map<String, dynamic> extra) async {
    final out = _tmp('templates');
    final data = await _runData(
      tag: 'templates_${gameId.hashCode.abs()}',
      job: {
        'type': 'sports_templates',
        'game_id': gameId,
        'out_dir': await _imageDir('templates'),
        'cache_dir': await _cacheDir(),
        ...extra,
      },
      outputFile: out,
    );
    return '${(data as Map)['zip']}';
  }

  /// Numbers jobs that may overlap (kit previews, analyses).
  static var _kitJob = 0;

  /// 96x128 PNG previews of [kits] ({key: KIT}, where KIT is a kit spec, an
  /// `image` or `template` choice, or null for the default): {key: path}.
  /// [colours] ({key: [shirt, alternate]}) is what a null KIT is drawn from,
  /// unless the library's kit catalogue knows the team ([teams], {key: {id, name}}).
  /// With a ROM, [slots] ({key: team slot}) and [which] ({key: home|away})
  /// let the worker draw the kit as the game mounts it. With [templates] and
  /// a ROM, also the game's own jersey designs. [home] ({away key: the
  /// team's home KIT}) gives an away kit the home kit's chest design (ISS).
  /// Each null KIT's resolved spec comes back in `defaults`.
  static Future<KitPreviews> kitPreviews({
    required String gameId,
    required Map<String, dynamic> kits,
    bool templates = false,
    String? romPath,
    Map<String, int>? slots,
    Map<String, String>? which,
    Map<String, List<String>>? colours,
    Map<String, Map<String, Object?>>? teams,
    Map<String, dynamic>? home,
  }) async {
    final out = _tmp('kit_previews');
    final data = await _runData(
      // Previews are requested while another batch may still be rendering;
      // each needs its own progress file.
      tag: 'kits_${gameId.hashCode.abs()}_${_kitJob++}',
      job: {
        'type': 'sports_kit_previews',
        'game_id': gameId,
        'out_dir': await _imageDir('kits'),
        'kits': kits,
        'templates': templates && romPath != null,
        if (romPath != null) 'rom_path': romPath,
        if (slots != null && slots.isNotEmpty) 'slots': slots,
        if (which != null && which.isNotEmpty) 'which': which,
        if (colours != null && colours.isNotEmpty) 'colours': colours,
        if (teams != null && teams.isNotEmpty) 'teams': teams,
        if (home != null && home.isNotEmpty) 'home': home,
        'cache_dir': await _cacheDir(),
      },
      outputFile: out,
    );
    final m = Map<String, dynamic>.from(data as Map);
    return (
      kits: Map<String, String>.from((m['kits'] as Map?) ?? const {}),
      defaults: {
        for (final e in ((m['defaults'] as Map?) ?? const {}).entries) '${e.key}': Map<String, dynamic>.from(e.value as Map),
      },
      templates: [
        for (final t in ((m['templates'] as List?) ?? const []))
          KitTemplate.fromJson(Map<String, dynamic>.from(t as Map)),
      ],
    );
  }

  /// [rostersFiles] (one league per slot group) replaces [rostersFile];
  /// [slotMapping] indices are then absolute. Kit choices normally travel in
  /// each team's `extra.kits`; [kits] ({slot: {home, away}}) overrides them.
  static Future<PatchResult> patchRom({
    required String gameId,
    required String provider,
    required String romPath,
    required String outputDir,
    required String label,
    String? rostersFile,
    List<RostersFile>? rostersFiles,
    List<SlotMapping>? slotMapping,
    String? language,
    bool? logos,
    bool blankUnused = false,
    bool nationals = false,
    Map<String, String> images = const {},
    Map<int, String> teamLogos = const {},
    Map<String, dynamic>? kits,
    void Function(double)? onProgress,
    void Function(String)? onStatus,
  }) async {
    assert(rostersFile != null || rostersFiles != null);
    final out = _tmp('patchresult');
    final data = await _runData(
      tag: 'patch_${gameId.hashCode.abs()}',
      job: {
        'type': 'sports_patch',
        'game_id': gameId,
        'provider': provider,
        'rom_path': romPath,
        'output_dir': outputDir,
        'label': label,
        if (language != null) 'language': language,
        if (logos != null) 'logos': logos,
        if (blankUnused) 'blank_unused': true,
        if (nationals) 'nationals': true,
        if (images.isNotEmpty) 'images': images,
        if (teamLogos.isNotEmpty) 'team_logos': {for (final e in teamLogos.entries) '${e.key}': e.value},
        if (kits != null && kits.isNotEmpty) 'kits': kits,
        if (rostersFiles != null)
          'rosters_files': [
            for (final r in rostersFiles) {'file': r.file, 'first_slot': r.firstSlot, 'count': r.count},
          ]
        else
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
