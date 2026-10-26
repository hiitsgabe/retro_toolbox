import 'dart:convert';
import 'dart:io';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/settings_model.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/download_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart';
import 'package:retro_toolbox/services/sports_rom_lookup.dart';
import 'package:retro_toolbox/services/sports_service.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/game_trivia.dart';
import 'package:retro_toolbox/widgets/kit_picker.dart' show saveTemplateZip;
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/game_model.dart';
import 'package:retro_toolbox/services/boxart_service.dart';
import 'package:retro_toolbox/utils/rom_search.dart';
import 'package:retro_toolbox/widgets/menu_grid/console_slug.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';
import 'package:retro_toolbox/services/formation_cache_service.dart';
import 'package:retro_toolbox/services/pick.dart';

/// One patch flow per game, in the app's own wizard idiom: step dots up top,
/// one focused step at a time, Back/Next footer. The ROM comes first so the
/// team editor can show the game's own kit designs.
///
/// After fetch the rosters become a full editor (reorder teams, add/delete
/// teams, edit each squad). Team order is the ROM slot order, so it replaces a
/// separate slot-mapping step.
class SportPatcherWizardScreen extends ConsumerStatefulWidget {
  final PatcherInfo info;

  /// Start on [initialStep] with rosters already fetched. Lets tests and
  /// screenshots render later steps without the Python worker.
  @visibleForTesting
  final RosterDoc? initialDoc;

  /// Several leagues already fetched (multi-league games); wins over
  /// [initialDoc].
  @visibleForTesting
  final List<RosterDoc>? initialDocs;
  @visibleForTesting
  final int initialStep;

  /// Leagues to offer instead of asking the worker. Tests only.
  @visibleForTesting
  final List<League>? initialLeagues;

  /// Replaces the worker's template-pack job. Tests only.
  @visibleForTesting
  final Future<String> Function(String gameId, {String? romPath})? templatesZip;

  /// Replaces the worker's ROM analysis. Tests only.
  @visibleForTesting
  final Future<RomInfo> Function({required String gameId, required String romPath, List<String> codes})? analyzeRom;

  /// A ROM already chosen. Tests only.
  @visibleForTesting
  final String? initialRomPath;

  /// A patch already done, shown on the Patch step. Tests and screenshots only.
  @visibleForTesting
  final PatchResult? initialResult;

  /// Screen art previews ({slot: png path}) to show on the Look step instead
  /// of exporting them from [initialRomPath]. Tests and screenshots only.
  @visibleForTesting
  final Map<String, String>? initialImages;

  const SportPatcherWizardScreen({
    super.key,
    required this.info,
    this.initialDoc,
    this.initialDocs,
    this.initialStep = 0,
    this.initialImages,
    this.initialLeagues,
    this.templatesZip,
    this.analyzeRom,
    this.initialRomPath,
    this.initialResult,
  });

  @override
  ConsumerState<SportPatcherWizardScreen> createState() => _WizardState();
}

enum _Step { rom, rosters, teams, look, patch }

/// A screen art slot's replacement: a PNG the user picked, or the branded
/// art the app generated.
typedef _ImagePick = ({String path, bool branded});

class _WizardState extends ConsumerState<SportPatcherWizardScreen> {
  // The look step exists only for games whose logos or screen art the patch
  // can change.
  late final List<_Step> _steps = [
    _Step.rom,
    _Step.rosters,
    _Step.teams,
    if (widget.info.hasVisuals) _Step.look,
    _Step.patch,
  ];
  late int _stepIndex = widget.initialStep;
  int get _index => _stepIndex;
  // A swap armed on the teams step must not outlive the step.
  set _index(int v) {
    _stepIndex = v;
    _teamSwapFrom = null;
  }

  late String _provider = widget.info.defaultProvider;
  late int _season = defaultSeason(_provider);
  // In-game language for games that ship translations; null when there's none.
  late String? _language = info.languages.isEmpty ? null : info.languages.first;

  bool get _isSoccer => widget.info.sport == 'soccer';
  late List<League> _leagues = widget.initialLeagues ?? [];
  League? _selectedLeague;

  /// Multi-league games: the leagues ticked, in tick order (league k fills
  /// slot group k).
  final List<League> _selectedLeagues = [];
  bool _nationals = false;
  bool _loadingLeagues = false;

  /// One fetched league per selected league; a single one for most games.
  late List<RosterDoc> _docs = widget.initialDocs ?? [if (widget.initialDoc != null) widget.initialDoc!];
  RosterDoc? get _doc => _docs.firstOrNull;
  String get _leagueLabel => _docs.map((d) => d.leagueName).join(' + ');
  late String? _romPath = widget.initialRomPath;
  String? _outputDir;

  // -- Look step state ----------------------------------------------------
  bool _useLogos = true;
  bool _blankUnused = false;
  bool _matchLooks = true;

  /// The ROM's current art per slot, exported for [_romImagesFor].
  late Map<String, String> _romImages = widget.initialImages ?? const {};
  late String? _romImagesFor = widget.initialImages == null ? null : widget.initialRomPath;
  bool _loadingImages = false;
  bool _downloadingTemplates = false;

  /// Per slot, the image replacing the ROM's; absent = keep the original.
  final Map<String, _ImagePick> _imagePicks = {};

  /// Branded art generated for the current league and season, by slot.
  Map<String, String>? _brandedImages;
  String? _brandedFor;

  /// Team id → PNG path replacing that team's downloaded logo.
  final Map<int, String> _teamLogos = {};

  // Catalog lookup: if the user's console catalog has this game, offer a
  // download instead of a manual file pick.
  RomCatalogMatch? _catalogMatch;
  String? _catalogDownloadDir;

  /// A file of this game already on the device (see [_findLocalRom]), and its
  /// cover art when the console has a box-art source.
  String? _localRomPath;
  String? _localRomBoxart;

  /// Lookups ([_lookupRom], [_findLocalRom]) still running: the ROM step
  /// holds a placeholder where their card will appear.
  int _romLookups = 0;

  /// Team picked to swap on the teams step (its league in [_teamSwapDoc]);
  /// the next row chosen trades places with it. Null when not swapping.
  int? _teamSwapFrom;
  int _teamSwapDoc = 0;
  final _teamFocus = FocusNode();
  int? _teamFocusRow;
  int _teamFocusDoc = 0;

  /// The picked row's move buttons: focus stays on the one pressed.
  final _teamUpFocus = FocusNode(), _teamDownFocus = FocusNode();

  @override
  void dispose() {
    _teamFocus.dispose();
    _teamUpFocus.dispose();
    _teamDownFocus.dispose();
    super.dispose();
  }

  /// Moves the picked team one place up ([delta] -1) or down in its league,
  /// keeping it picked: the d-pad's way to reorder without a drag.
  void _moveTeamBy(int delta) {
    final teams = _docs[_teamSwapDoc].teams, from = _teamSwapFrom!, to = from + delta;
    setState(() {
      teams.insert(to, teams.removeAt(from));
      _teamSwapFrom = to;
    });
    _teamFocusDoc = _teamSwapDoc;
    _teamFocusRow = to;
    final node = delta < 0 ? (to > 0 ? _teamUpFocus : _teamFocus) : (to < teams.length - 1 ? _teamDownFocus : _teamFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _focusTeam(int d, int i) {
    _teamFocusDoc = d;
    _teamFocusRow = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _teamFocus.requestFocus();
    });
  }

  void _startTeamSwap(int d, int i) {
    setState(() {
      _teamSwapDoc = d;
      _teamSwapFrom = i;
    });
    _focusTeam(d, i);
  }

  Future<void> _removeTeam(int d, int i) async {
    final teams = _docs[d].teams;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove team?'),
        content: Text('Remove ${teams[i].name} from the roster?'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => teams.removeAt(i));
    _loadSlotInfo();
    if (teams.isNotEmpty) _focusTeam(d, i < teams.length ? i : teams.length - 1);
  }

  bool _busy = false;
  double _progress = 0;
  String? _status;
  String? _error;
  late PatchResult? _result = widget.initialResult;

  /// Games that slot teams by code (NHL '94): the ROM's per-slot counts and
  /// the slot each team's code lands in, asked once per ROM and set of codes.
  /// [_slotInfo] is null until known; a failed ask is not kept, so the next
  /// tap asks again (the editor meanwhile says it does not know the counts).
  RomInfo? _slotInfo;
  Future<RomInfo?>? _slotJob;
  String? _slotInfoFor;
  bool _openingTeam = false;

  Future<RomInfo?> _loadSlotInfo() {
    final rom = _romPath;
    if (rom == null || !gameStoresByPosition(info.gameId)) return Future.value(null);
    final codes = ({for (final d in _docs) for (final t in d.teams) t.code}..remove('')).toList()..sort();
    final key = '$rom|${codes.join(',')}';
    if (_slotInfoFor != key) {
      _slotInfoFor = key;
      _slotInfo = null;
      _slotJob = (widget.analyzeRom ?? SportsService.analyzeRom)(gameId: info.gameId, romPath: rom, codes: codes).then<RomInfo?>(
        (r) {
          if (mounted && _slotInfoFor == key) setState(() => _slotInfo = r);
          return r;
        },
        onError: (_) {
          if (_slotInfoFor == key) _slotInfoFor = null;
          return null;
        },
      );
    }
    return _slotJob!;
  }

  bool get _slotsPending => _slotInfoFor != null && _slotInfo == null;

  /// A team the patch leaves out: this ROM has no slot for its code.
  bool _slotless(RosterTeam t) => _slotInfo != null && !_slotInfo!.teamSlots.containsKey(t.code);

  PatcherInfo get info => widget.info;
  _Step get _step => _steps[_index];

  /// Short screens (small handhelds): the full header, paddings and footer
  /// left almost no room for the step itself.
  bool get _compact => MediaQuery.sizeOf(context).height < 640;

  /// Very short screens (a 16:9 handheld in landscape is ~360dp tall): the
  /// Back/Next buttons move into the top bar and step blurbs are dropped.
  bool get _short => MediaQuery.sizeOf(context).height < 480;

  /// The rosters step has something to choose only for soccer (league), a
  /// multi-source game, or a source that exposes a season. Otherwise there's
  /// nothing to pick, so we fetch immediately and skip to the editor.
  bool get _rostersHasOptions => _isSoccer || info.providers.length > 1 || providerHasSeason(_provider);

  @override
  void initState() {
    super.initState();
    if (_isSoccer && widget.initialLeagues == null) _loadLeagues();
    _startRomLookups();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enterStep();
    });
  }

  /// Work a step starts on arrival: Look exports the ROM's art; Rosters with
  /// nothing to choose fetches at once.
  void _enterStep() {
    if (_step == _Step.teams) _loadSlotInfo();
    if (_step == _Step.look) _loadRomImages();
    if (_step == _Step.rosters && !_rostersHasOptions && _docs.isEmpty) _fetch();
  }

  /// The lookups need the saved settings (download folders, library on) and
  /// the console list. Opened first thing after launch, neither may be loaded
  /// yet (the app state is only created by its first reader): the lookups
  /// would search nowhere and never run again. The placeholder shows meanwhile.
  Future<void> _startRomLookups() async {
    _romLookups++;
    try {
      await Future.wait([ref.read(settingsProvider.notifier).loaded, ref.read(appStateProvider.notifier).loaded]);
    } catch (_) {
      // Look with whatever is there.
    }
    if (!mounted) return;
    _lookupRom();
    _findLocalRom();
    setState(() => _romLookups--);
  }

  /// Search the console catalog for this game so the ROM step can offer a
  /// download. Best-effort — any failure just leaves the manual file picker.
  Future<void> _lookupRom() async {
    if (!ref.read(settingsProvider).isLibraryEnabled) return;
    final consoles = ref.read(appStateProvider).consolesList;
    if (consoles.isEmpty) return;
    _romLookups++;
    try {
      final match = await SportsRomLookup.find(
        consoles: consoles,
        gameId: info.gameId,
        platform: info.platform,
      );
      if (match != null && mounted) {
        setState(() {
          _catalogMatch = match;
          _catalogDownloadDir = ref.read(settingsProvider.notifier).getDownloadDir(match.console.id);
        });
      }
    } catch (_) {
      // ignore — manual pick remains
    } finally {
      if (mounted) setState(() => _romLookups--);
    }
  }

  /// Look for the game among the files already on this device: every download
  /// folder of the consoles that run it, then the general download folder
  /// (loose files, and folders named after the game), by fuzzy name, as a
  /// .bin/.cue/.iso/... or an archive. Runs off the UI isolate, whether or
  /// not the online library is on.
  Future<void> _findLocalRom() async {
    final settings = ref.read(settingsProvider.notifier);
    final wantSlug = consoleArtSlugForText(info.platform);
    final consoles = [
      for (final console in ref.read(appStateProvider).consolesList)
        if (wantSlug != null && consoleArtSlug(console) == wantSlug) console,
    ];
    final dirs = [for (final console in consoles) settings.getDownloadDir(console.id)];
    final general = [settings.getDownloadDir(null)];
    // Console folders usually sit inside the general one; the other consoles'
    // copies of the same title (a PS2 disc for the PSP game) are not this ROM.
    final skip = [for (final console in ref.read(appStateProvider).consolesList) settings.getDownloadDir(console.id)];
    final gameId = info.gameId;
    _romLookups++;
    try {
      final found = await SportsRomLookup.findLocalInBackground(dirs: dirs, gameId: gameId, looseDirs: general, skip: skip);
      if (found == null || !mounted) return;
      setState(() => _localRomPath = found);
      await _loadLocalBoxart(found, consoles);
    } catch (_) {
      // ignore — manual pick remains
    } finally {
      if (mounted) setState(() => _romLookups--);
    }
  }

  /// The game's name as the found file, or the folder it was extracted to,
  /// spells it: the closer of the two to the game's search terms.
  String _localRomTitle(String path) {
    final terms = gameSearchTerms(info.gameId);
    final own = p.basenameWithoutExtension(path);
    final folder = p.basename(p.dirname(path));
    return romBestScore(own, terms) >= romBestScore(folder, terms) ? own : folder;
  }

  /// Cover art for the file found on the device, from the first console of
  /// this platform that has a box-art source, matched by name as the catalog
  /// matches its games.
  Future<void> _loadLocalBoxart(String path, List<Console> consoles) async {
    final console = consoles.where((c) => c.boxarts != null).firstOrNull;
    if (console == null) return;
    final title = _localRomTitle(path);
    final game = Game(title: title, url: Uri.file('$title.bin').toString(), size: 0, consoleId: console.id);
    final art = (await BoxartService().mutateGamesWithBoxarts([game], console)).first.boxart;
    if (art != null && mounted) setState(() => _localRomBoxart = art);
  }

  /// The catalog game once downloaded: what its archive was extracted to, or
  /// the archive itself. A file found by name elsewhere is offered on its own
  /// card, under its own name, never as this game.
  String? get _downloadedPath {
    final m = _catalogMatch, dir = _catalogDownloadDir;
    if (m == null || dir == null) return null;
    final extracted = SportsRomLookup.extractedFor(dir: dir, archiveName: m.game.filename, gameId: info.gameId);
    if (extracted != null) return extracted;
    final path = p.join(dir, m.game.filename);
    return File(path).existsSync() ? path : null;
  }

  void _downloadCatalogGame() {
    final m = _catalogMatch, dir = _catalogDownloadDir;
    if (m == null || dir == null) return;
    ref.read(taskQueueProvider.notifier).enqueue(m.game.gameId, TaskType.download, {
      'game': m.game.toJson(),
      'downloadDir': dir,
      'group': m.console.id,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Download added to the task list. Come back here when it finishes.')),
    );
  }

  Future<void> _loadLeagues() async {
    setState(() => _loadingLeagues = true);
    try {
      final builtin = await SportsService.listLeagues();
      final custom = await SportsService.loadCustomLeagues();
      final byId = {for (final l in builtin) l.id: l};
      for (final l in custom) {
        byId[l.id] = l;
      }
      if (mounted) setState(() => _leagues = byId.values.toList());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loadingLeagues = false);
    }
  }

  final _leaguePasteCtrl = TextEditingController();

  Future<void> _pasteCustomLeagues() async {
    final js = _leaguePasteCtrl.text.trim();
    if (js.isEmpty) return;
    try {
      await SportsService.importCustomLeaguesJson(js);
      _leaguePasteCtrl.clear();
      await _loadLeagues();
    } catch (e) {
      if (mounted) setState(() => _error = 'Custom leagues: $e');
    }
  }

  Future<void> _importCustomLeagues() async {
    try {
      final path = await pickFile(context, title: 'Select a leagues JSON file', extensions: ['json']);
      if (path == null || !mounted) return;
      await SportsService.importCustomLeagues(path);
      await _loadLeagues();
    } catch (e) {
      if (mounted) setState(() => _error = 'Custom leagues: $e');
    }
  }

  Future<void> _fetch() async {
    // One worker job per league; multi-league games fetch each ticked league
    // in turn and the loader names the one in flight.
    final leagues = info.multiLeague ? List<League?>.of(_selectedLeagues) : <League?>[_selectedLeague];
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Contacting the provider…';
      _error = null;
    });
    try {
      final docs = <RosterDoc>[];
      for (final (n, league) in leagues.indexed) {
        final prefix = leagues.length > 1 ? '${league?.name} (${n + 1}/${leagues.length}) · ' : '';
        setState(() {
          _progress = 0;
          _status = '${prefix}Contacting the provider…';
        });
        final (_, file) = await SportsService.fetchRosters(
          gameId: info.gameId,
          provider: _provider,
          // Soccer leagues keep their own calendars (August to May, or the
          // calendar year): the worker picks each league's current season.
          season: _isSoccer ? null : _season,
          league: league,
          onProgress: (v) => setState(() => _progress = v),
          onStatus: (s) => setState(() => _status = '$prefix$s'),
        );
        final doc = await SportsService.loadRoster(file);
        await _applySavedFormations(doc);
        docs.add(doc);
      }
      // Fetch is the step's forward action — on success go straight to the
      // editor instead of making the user press a separate Next.
      setState(() {
        _docs = docs;
        // The art and the patch label name the season actually fetched.
        if (_isSoccer) _season = docs.first.season ?? _season;
        if (_step == _Step.rosters) _index++;
      });
      _loadSlotInfo();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _applySavedFormations(RosterDoc doc) async {
    final auto = ref.read(settingsProvider).generalSettings.getSetting<bool>(AppSettings.autoApplyFormations) ?? true;
    if (!auto) return;
    final saved = await FormationCacheService.load();
    if (saved.isEmpty) return;
    for (final team in doc.teams) {
      final ids = saved[team.id];
      if (ids == null || ids.isEmpty) continue;
      final byId = {for (final p in team.players) p.id: p};
      final ordered = <RosterPlayer>[];
      for (final id in ids) {
        final p = byId[id];
        if (p != null && !ordered.contains(p)) ordered.add(p);
      }
      for (final p in team.players) {
        if (!ordered.contains(p)) ordered.add(p);
      }
      team.players
        ..clear()
        ..addAll(ordered);
    }
  }

  Future<void> _pickRom() async {
    // Android's system picker (SAF) for the ROM: one file, so its cache copy
    // is fine. Handhelds keep the in-app browser (no native dialog, d-pad).
    final path = await pickFile(
      context,
      title: 'Select the ROM to patch',
      initialDir: _romPath != null ? p.dirname(_romPath!) : null,
      androidNative: true,
    );
    if (path == null || !mounted) return;
    // Format only: the extension the game takes, and a zip must hold a file
    // of that type inside. The file's name never matters.
    final problem = await romPickProblem(path, info.gameId);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _error = null;
      _romPath = path;
    });
  }

  /// Select a lookup's ROM and move on at once: with the file in hand the ROM
  /// step has nothing left to choose (its Next does the same).
  void _useFoundRom(String path) {
    setState(() => _romPath = path);
    _next();
  }

  /// Export the chosen ROM's screen art for the look step's previews, once
  /// per ROM. Failure leaves the cards without a preview and shows the error.
  Future<void> _loadRomImages() async {
    final rom = _romPath;
    if (rom == null || info.imageSlots.isEmpty || _romImagesFor == rom || _loadingImages) return;
    setState(() {
      _loadingImages = true;
      _error = null;
    });
    try {
      final images = await SportsService.exportImages(gameId: info.gameId, romPath: rom);
      if (!mounted) return;
      setState(() {
        _romImages = images;
        _romImagesFor = rom;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Screen art preview: $e');
    } finally {
      if (mounted) setState(() => _loadingImages = false);
    }
  }

  /// The branded art for the current league(s) and season, generated once.
  Future<Map<String, String>> _brandedArt() async {
    final key = '$_leagueLabel|$_season';
    if (_brandedImages != null && _brandedFor == key) return _brandedImages!;
    final images = await SportsService.defaultImages(
      gameId: info.gameId,
      league: _leagueLabel,
      season: _season,
    );
    _brandedImages = images;
    _brandedFor = key;
    return images;
  }

  Future<void> _useBranded(Iterable<String> slots) async {
    setState(() {
      _loadingImages = true;
      _error = null;
    });
    try {
      final art = await _brandedArt();
      if (!mounted) return;
      setState(() {
        for (final slot in slots) {
          final path = art[slot];
          if (path != null) _imagePicks[slot] = (path: path, branded: true);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Retro Toolbox art: $e');
    } finally {
      if (mounted) setState(() => _loadingImages = false);
    }
  }

  /// Builds the screen-art template pack and copies it where the user says
  /// (handhelds: the output folder).
  Future<void> _downloadTemplates() async {
    // One job at a time: a second press would reuse the worker tag.
    setState(() {
      _downloadingTemplates = true;
      _error = null;
    });
    try {
      final zip = await (widget.templatesZip ?? SportsService.templatesZip)(info.gameId, romPath: _romPath);
      if (!mounted) return;
      await saveTemplateZip(context, zip, defaultDir: _outputDir ?? _defaultOutputDir());
    } catch (e) {
      if (mounted) setState(() => _error = 'Templates: $e');
    } finally {
      if (mounted) setState(() => _downloadingTemplates = false);
    }
  }

  Future<void> _replaceImage(String slot) async {
    final path = await pickFile(context, title: 'Select a PNG for the ${imageSlotLabel(slot, info.gameId).$1.toLowerCase()}', extensions: ['png']);
    if (path == null || !mounted) return;
    setState(() => _imagePicks[slot] = (path: path, branded: false));
  }

  /// Pick a PNG for a team's logo, or go back to the downloaded one.
  Future<void> _changeTeamLogo(RosterTeam t) async {
    final current = _teamLogos[t.id];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Choose a PNG…'),
              subtitle: Text('Replaces the logo drawn for ${t.name}.'),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
            if (current != null)
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('Use the downloaded logo'),
                onTap: () => Navigator.pop(ctx, 'reset'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'reset') {
      setState(() => _teamLogos.remove(t.id));
      return;
    }
    final path = await pickFile(context, title: 'Select a logo PNG for ${t.name}', extensions: ['png']);
    if (path == null || !mounted) return;
    setState(() => _teamLogos[t.id] = path);
  }

  /// Default output folder: the console's download dir when the ROM came from
  /// the library, otherwise next to the picked ROM.
  String _defaultOutputDir() {
    final m = _catalogMatch;
    if (m != null) return ref.read(settingsProvider.notifier).getDownloadDir(m.console.id);
    return _romPath != null ? p.dirname(_romPath!) : '';
  }

  Future<void> _patch() async {
    final romPath = _romPath, doc = _doc;
    if (romPath == null || doc == null) return;
    final dir = _outputDir ?? _defaultOutputDir();

    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Preparing…';
      _error = null;
    });
    try {
      String? rostersFile;
      List<RostersFile>? rostersFiles;
      List<SlotMapping>? slotMapping;
      if (info.multiLeague) {
        // One file per league, each filling its slot group in team order;
        // the mapping is absolute and drops teams past the group's size.
        rostersFiles = [];
        slotMapping = [];
        for (final (k, d) in _docs.indexed) {
          if (k >= info.slotGroups.length) break;
          final g = info.slotGroups[k];
          rostersFiles.add((file: await SportsService.saveRoster(d), firstSlot: g.first, count: g.count));
          for (var i = 0; i < d.teams.length && i < g.count; i++) {
            slotMapping.add(SlotMapping(slotIndex: g.first + i, teamId: d.teams[i].id, teamName: d.teams[i].name));
          }
        }
      } else {
        rostersFile = await SportsService.saveRoster(doc);
        // Team order is the slot order for games that need an explicit mapping.
        if (info.requiresSlotMapping) {
          slotMapping = [
            for (var i = 0; i < doc.teams.length; i++) SlotMapping(slotIndex: i, teamId: doc.teams[i].id, teamName: doc.teams[i].name),
          ];
        }
      }
      final result = await SportsService.patchRom(
        gameId: info.gameId,
        provider: _provider,
        romPath: romPath,
        // Output mirrors the input's packaging and is named
        // "<league> <season> - <game>..." by the Python side.
        outputDir: dir,
        label: '$_leagueLabel $_season',
        rostersFile: rostersFile,
        rostersFiles: rostersFiles,
        slotMapping: slotMapping,
        language: _language,
        logos: info.supportsLogos ? _useLogos : null,
        blankUnused: info.supportsBlankUnused && _blankUnused,
        looks: info.supportsLooks ? _matchLooks : null,
        nationals: info.supportsNationals && _nationals,
        images: {for (final e in _imagePicks.entries) e.key: e.value.path},
        teamLogos: info.supportsLogos && _useLogos ? _teamLogos : const {},
        onProgress: (v) => setState(() => _progress = v),
        onStatus: (s) => setState(() => _status = s),
      );
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canAdvance {
    switch (_step) {
      // Next on the rosters step triggers the fetch; enabled once a league is
      // chosen (soccer) or immediately (other sports use a fixed league).
      case _Step.rosters:
        if (!_isSoccer) return true;
        return info.multiLeague ? _selectedLeagues.isNotEmpty : _selectedLeague != null;
      case _Step.teams:
        return _docs.isNotEmpty && _docs.every((d) => d.teams.isNotEmpty);
      case _Step.rom:
        return _romPath != null;
      case _Step.look:
        return true;
      case _Step.patch:
        return false;
    }
  }

  /// The enabled primary of [_navButtons]; what Start does.
  VoidCallback? get _primary {
    if (_step == _Step.patch) {
      if (_result != null) return () => Navigator.of(context).pop();
      return (_busy || _romPath == null) ? null : _patch;
    }
    return (_canAdvance && !_busy) ? _next : null;
  }

  // On the rosters step Next runs the fetch (which advances on success);
  // elsewhere it just moves forward.
  void _next() {
    if (_step == _Step.rosters && _docs.isEmpty) {
      _fetch();
      return;
    }
    setState(() => _index++);
    _enterStep();
  }

  @override
  Widget build(BuildContext context) {
    final primary = _primary;
    // B steps back; on the first step (nothing to lose yet) it leaves. Never
    // while busy.
    return PopScope(
      canPop: _index == 0 && !_busy && _teamSwapFrom == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        if (_teamSwapFrom != null) {
          final from = _teamSwapFrom!;
          setState(() => _teamSwapFrom = null);
          _focusTeam(_teamSwapDoc, from);
        } else if (_index > 0) {
          setState(() => _index--);
        }
      },
      child: Actions(
        actions: {
          if (primary != null) PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(onInvoke: (_) => primary()),
        },
        child: _scaffold(),
      ),
    );
  }

  Widget _scaffold() {
    final theme = Theme.of(context);
    final accent = sportBrandColor(info.sport);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(theme, accent),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: AbsorbPointer(absorbing: _busy, child: _body(theme)),
                ),
              ),
            ),
            if (!_short) _footer(theme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, Color accent) {
    if (_compact) {
      // One row: back, game, and the step as text instead of the dot rail.
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
        child: Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
            Icon(sportIcon(info.sport), color: accent, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(gameName(info), style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis)),
            Text('${_index + 1}/${_steps.length} · ${_label(_step)}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
            if (_short) ...[const SizedBox(width: 12), ..._navButtons()],
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.maybePop(context)),
              Icon(sportIcon(info.sport), color: accent),
              const SizedBox(width: 10),
              Expanded(child: Text(gameName(info), style: theme.textTheme.titleLarge)),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              for (var i = 0; i < _steps.length; i++) ...[
                _stepDot(theme, i),
                if (i < _steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: i < _index ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepDot(ThemeData theme, int i) {
    final active = i == _index, done = i < _index;
    final color = done || active ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest;
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: color,
          child: done
              ? const Icon(Icons.check, size: 18, color: Colors.white)
              : Text('${i + 1}', style: TextStyle(color: active ? Colors.white : theme.colorScheme.onSurfaceVariant)),
        ),
        const SizedBox(height: 6),
        Text(_label(_steps[i]), style: theme.textTheme.labelSmall),
      ],
    );
  }

  static String _label(_Step s) => switch (s) {
        _Step.rom => 'ROM',
        _Step.rosters => 'Rosters',
        _Step.teams => 'Teams',
        _Step.look => 'Look',
        _Step.patch => 'Patch',
      };

  Widget _sectionTitle(ThemeData theme, IconData icon, String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: theme.textTheme.titleMedium))
          ]),
          if (!_short) ...[
            SizedBox(height: _compact ? 2 : 6),
            Text(
              subtitle,
              maxLines: _compact ? 2 : null,
              overflow: _compact ? TextOverflow.ellipsis : null,
              style: (_compact ? theme.textTheme.bodySmall : theme.textTheme.bodyMedium)?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          SizedBox(height: _compact ? 8 : 16),
        ],
      );

  Widget _body(ThemeData theme) {
    final content = switch (_step) {
      _Step.rom => _romStep(theme),
      _Step.rosters => _rostersStep(theme),
      _Step.teams => _teamsStep(theme),
      _Step.look => _lookStep(theme),
      _Step.patch => _patchStep(theme),
    };
    return Padding(
      padding: _compact ? const EdgeInsets.fromLTRB(16, 8, 16, 4) : const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: content),
          if (_error != null) ...[
            const SizedBox(height: 12),
            _statusRow(theme, Icons.error_outline, theme.colorScheme.error, _error!),
          ],
        ],
      ),
    );
  }

  // -- Step 2: source / season / league / fetch ---------------------------

  Widget _rostersStep(ThemeData theme) {
    // While fetching (auto or manual), fill the step with the trivia loader.
    if (_busy) return GameTriviaLoader(status: _status, seed: info.gameId.hashCode.abs());
    return ListView(
      children: [
        _sectionTitle(theme, Icons.tune, 'Rosters', 'Pick your options, then Next downloads the league data.'),
        _sourceAndSeason(theme),
        if (_isSoccer) info.multiLeague ? _leagueChecklist(theme) : _leaguePicker(theme),
      ],
    );
  }

  Widget _sourceAndSeason(ThemeData theme) {
    final multi = info.providers.length > 1;
    final showSeason = providerHasSeason(_provider);
    if (!multi && !showSeason) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (multi)
            Row(
              children: [
                Text('Source', style: theme.textTheme.labelLarge),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _provider,
                  items: [for (final pr in info.providers) DropdownMenuItem(value: pr, child: Text(pr.toUpperCase()))],
                  onChanged: (v) => setState(() {
                    _provider = v ?? _provider;
                    _season = defaultSeason(_provider);
                    _docs = [];
                  }),
                ),
              ],
            ),
          if (showSeason) ...[
            const SizedBox(height: 8),
            Text('Season', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton.filledTonal(
                    onPressed: () => setState(() {
                          _season--;
                          _docs = [];
                        }),
                    icon: const Icon(Icons.remove)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('$_season', style: theme.textTheme.headlineSmall),
                ),
                IconButton.filledTonal(
                    onPressed: () => setState(() {
                          _season++;
                          _docs = [];
                        }),
                    icon: const Icon(Icons.add)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _leaguePicker(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('League', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (_loadingLeagues)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
            else
              DropdownButton<League>(
                value: _selectedLeague,
                isExpanded: true,
                hint: const Text('Select a league'),
                items: [
                  for (final l in _leagues) DropdownMenuItem(value: l, child: Text(l.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _selectedLeague = v;
                  _docs = [];
                }),
              ),
            _customLeaguesHelp(theme),
          ],
        ),
      );

  /// Multi-league games: tick one league per slot group, in the order they
  /// fill the groups, up to the game's league cap; plus the national sides
  /// when the patch can do them.
  Widget _leagueChecklist(ThemeData theme) {
    final groups = info.slotGroups;
    final cap = info.leagueCap;
    final full = _selectedLeagues.length >= cap;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Leagues', style: theme.textTheme.labelLarge)),
              Text(
                '${_selectedLeagues.length} of $cap leagues',
                style: theme.textTheme.labelLarge?.copyWith(color: full ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          Text(
            'The game holds up to $cap leagues. Each one you tick fills the next group of team slots, in that order.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          if (_loadingLeagues)
            const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
          else
            for (final l in _leagues)
              Builder(builder: (_) {
                // Compared by id: a re-import rebuilds the league objects.
                final k = _selectedLeagues.indexWhere((s) => s.id == l.id);
                final g = k < 0 ? null : groups[k];
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: k >= 0,
                  enabled: k >= 0 || !full,
                  title: Text(l.label, overflow: TextOverflow.ellipsis),
                  subtitle: g == null ? null : Text('${l.name} → Group ${k + 1} (${g.name}, ${g.count} teams)'),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedLeagues.add(l);
                    } else {
                      _selectedLeagues.removeWhere((s) => s.id == l.id);
                    }
                    _docs = [];
                  }),
                );
              }),
          if (info.supportsNationals)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.flag_outlined),
              title: const Text('National teams'),
              subtitle: Text(info.nationalSlotBase == 0
                  // ISS 2000: clubs go in the national slots, so this fills the rest.
                  ? "Update the national teams the clubs don't replace (international friendlies)"
                  : 'Update the national sides too (international friendlies)'),
              value: _nationals,
              onChanged: (v) => setState(() => _nationals = v),
            ),
          _customLeaguesHelp(theme),
        ],
      ),
    );
  }

  Widget _customLeaguesHelp(ThemeData theme) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text('Add your own leagues', style: theme.textTheme.bodyMedium),
        children: [
          Text(
            'Import a JSON file listing extra leagues. Each entry needs an ESPN league code:',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '[\n  { "id": 9001, "code": "eng.2", "name": "Championship", "country": "England" }\n]',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          if (!Handheld.current) ...[
            TextField(
              controller: _leaguePasteCtrl,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Paste league JSON here'),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            children: [
              if (!Handheld.current)
                FilledButton.tonalIcon(
                  onPressed: _pasteCustomLeagues,
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('Add pasted'),
                ),
              OutlinedButton.icon(
                onPressed: _importCustomLeagues,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Import from file'),
              ),
            ],
          ),
        ],
      );

  // -- Step 3: the team editor -------------------------------------------

  Widget _teamsStep(ThemeData theme) {
    if (_docs.isEmpty) return const Center(child: Text('Fetch rosters first.'));
    if (info.multiLeague) return _leagueSections(theme);
    final doc = _doc!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _sectionTitle(theme, Icons.groups, doc.leagueName, _reorderHint)),
            _addButton(doc, iconOnly: _compact),
          ],
        ),
        Expanded(child: _teamList(theme, 0)),
      ],
    );
  }

  String get _reorderHint => gameStoresByPosition(info.gameId)
      // The library slots these by team code, whatever the order.
      ? (_slotsPending ? "Reading the ROM's slots…" : 'Each team goes to its own slot; tap to edit a squad.')
      : Handheld.current
          ? 'Move or swap to reorder (slot order), tap to edit a squad.'
          : 'Drag, move or swap to reorder (slot order), tap to edit a squad.';

  Widget _addButton(RosterDoc doc, {required bool iconOnly}) => iconOnly
      ? IconButton.filledTonal(onPressed: () => _addTeam(doc), icon: const Icon(Icons.add), tooltip: 'Add team')
      : FilledButton.tonalIcon(
          onPressed: () => _addTeam(doc),
          icon: const Icon(Icons.add),
          label: const Text('Add team'),
        );

  /// One section per league: its slot range, its own reorderable list, and
  /// teams past the group's size greyed out with no slot.
  Widget _leagueSections(ThemeData theme) {
    final groups = info.slotGroups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, Icons.groups, 'Teams', _reorderHint),
        Expanded(
          child: ListView(
            children: [
              for (final (d, doc) in _docs.indexed) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(doc.leagueName, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                      _slotsLabel(theme, doc, d < groups.length ? groups[d] : null),
                      const SizedBox(width: 8),
                      _addButton(doc, iconOnly: true),
                    ],
                  ),
                ),
                _teamList(theme, d, shrink: true, slots: d < groups.length ? groups[d].count : 0),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// A league section's slot range; when the league has more teams than its
  /// group has slots, how many the patch leaves out (the greyed rows).
  Widget _slotsLabel(ThemeData theme, RosterDoc doc, SlotGroup? g) {
    final over = g == null ? 0 : doc.teams.length - g.count;
    final range = g == null ? 'no slots' : 'slots ${g.first + 1}–${g.first + g.count}';
    return Text(
      over > 0 ? '$range · $over ${over == 1 ? 'team gets' : 'teams get'} no slot' : range,
      style: theme.textTheme.bodySmall?.copyWith(color: over > 0 ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
    );
  }

  /// League [d]'s teams; [slots] caps how many get a slot (null: all).
  Widget _teamList(ThemeData theme, int d, {bool shrink = false, int? slots}) {
    final teams = _docs[d].teams;
    return ReorderableListView.builder(
      shrinkWrap: shrink,
      physics: shrink ? const NeverScrollableScrollPhysics() : null,
      // Off while a swap is armed: a drag would shift the armed index.
      buildDefaultDragHandles: !Handheld.current && _teamSwapFrom == null,
      itemCount: teams.length,
      onReorder: (oldI, newI) => setState(() {
        _teamSwapFrom = null;
        if (newI > oldI) newI--;
        teams.insert(newI, teams.removeAt(oldI));
      }),
      itemBuilder: (context, i) => _teamRow(theme, d, i, noSlot: (slots != null && i >= slots) || _slotless(teams[i])),
    );
  }

  Widget _teamRow(ThemeData theme, int d, int i, {bool noSlot = false}) {
    final teams = _docs[d].teams;
    final t = teams[i];
    final swapping = _teamSwapFrom != null;
    final armed = swapping && _teamSwapDoc == d && _teamSwapFrom == i;
    final card = Card(
      key: ValueKey('team_${d}_${t.id}_$i'),
      shape: armed
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      margin: EdgeInsets.symmetric(vertical: _compact ? 2 : 4),
      child: Opacity(
        opacity: noSlot ? 0.5 : 1,
        // The crest and buttons sit beside the tile, not in it: the d-pad
        // only moves to what lies past the tile's edge.
        child: Row(
          children: [
            Padding(padding: const EdgeInsets.only(left: 12), child: _teamCrest(theme, t)),
            Expanded(
              child: ListTile(
                focusNode: _teamFocusDoc == d && _teamFocusRow == i ? _teamFocus : null,
                dense: _compact,
                visualDensity: _compact ? VisualDensity.compact : null,
                title: Text(t.name),
                subtitle: Text(noSlot ? 'no slot' : '${t.players.length} players'),
                onTap: () async {
                  final from = _teamSwapFrom;
                  if (from != null) {
                    // Swaps work across leagues too: it is just two list slots.
                    setState(() {
                      final fromTeams = _docs[_teamSwapDoc].teams;
                      if (_teamSwapDoc != d || from != i) {
                        final a = fromTeams[from];
                        fromTeams[from] = teams[i];
                        teams[i] = a;
                      }
                      _teamSwapFrom = null;
                    });
                    _focusTeam(d, i);
                    return;
                  }
                  // A game that slots teams by code knows the team's slot better
                  // than its place in the list. One editor at a time while it asks.
                  if (_openingTeam) return;
                  _openingTeam = true;
                  try {
                    final slotInfo = await _loadSlotInfo();
                    if (!mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TeamEditorScreen(
                          team: t,
                          gameId: info.gameId,
                          sport: info.sport,
                          info: info,
                          romPath: _romPath,
                          slot: noSlot ? null : (slotInfo?.teamSlots[t.code] ?? (info.multiLeague ? info.slotGroups[d].first + i : i)),
                          rosterCounts: slotInfo?.countsFor(t.code),
                          teamLogos: info.supportsLogos ? _teamLogos : null,
                        ),
                      ),
                    );
                  } finally {
                    _openingTeam = false;
                  }
                  if (mounted) setState(() {});
                },
              ),
            ),
            if (!swapping) ...[
              IconButton(
                icon: const Icon(Icons.swap_vert),
                tooltip: 'Move or swap',
                onPressed: () => _startTeamSwap(d, i),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: () => _removeTeam(d, i),
              ),
              if (!Handheld.current) const Icon(Icons.drag_handle),
            ],
            if (armed) ...moveButtons(i, teams.length, _moveTeamBy, up: _teamUpFocus, down: _teamDownFocus),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
    // Y swaps this team.
    return Actions(
      key: card.key,
      actions: {
        ItemActionsIntent: CallbackAction<ItemActionsIntent>(onInvoke: (_) {
          if (!swapping) _startTeamSwap(d, i);
          return null;
        }),
      },
      child: card,
    );
  }

  Widget _teamCrest(ThemeData theme, RosterTeam t) {
    final override = _teamLogos[t.id];
    final crest = teamCrest(t, override: override);
    if (!info.supportsLogos) return SizedBox(width: 40, height: 40, child: crest);
    // The crest is a button: the patch draws it into the game, so it can be
    // swapped for the user's own PNG here.
    return Tooltip(
      message: override == null ? 'Replace logo' : 'Custom logo · tap to change',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _changeTeamLogo(t),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Stack(
            children: [
              Positioned.fill(child: Padding(padding: const EdgeInsets.all(2), child: crest)),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: override == null ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.edit, size: 10, color: override == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addTeam(RosterDoc doc) async {
    final nameCtrl = TextEditingController();
    final jsonCtrl = TextEditingController();
    String? err;
    String? importedName;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add team'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Team name')),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(Handheld.current ? 'Or import team JSON' : 'Or paste / import team JSON'),
                    children: [
                      Text(
                        'A team object: {"name": "...", "players": [{"name","position","number"}]} '
                        'Or the full roster shape with a "team" key.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      if (!Handheld.current) ...[
                        TextField(
                          controller: jsonCtrl,
                          maxLines: 6,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '{ "name": "...", "players": [...] }'),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final path = await pickFile(ctx, title: 'Select a team JSON file', extensions: ['json']);
                            if (path == null) return;
                            jsonCtrl.text = await File(path).readAsString();
                            setLocal(() => importedName = p.basename(path));
                          },
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Import from file'),
                        ),
                      ),
                      if (importedName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Loaded $importedName', style: Theme.of(ctx).textTheme.bodySmall),
                        ),
                    ],
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(err!, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final js = jsonCtrl.text.trim();
                if (js.isNotEmpty) {
                  try {
                    final map = Map<String, dynamic>.from(jsonDecode(js) as Map);
                    doc.addTeamFromJson(map);
                  } catch (e) {
                    setLocal(() => err = 'Invalid team JSON: $e');
                    return;
                  }
                } else if (nameCtrl.text.trim().isNotEmpty) {
                  doc.addTeam(nameCtrl.text.trim());
                } else {
                  setLocal(() => err = Handheld.current ? 'Enter a name or import a file' : 'Enter a name or paste JSON');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    setState(() {});
    _loadSlotInfo();
  }

  // -- Step 1: the ROM ---------------------------------------------------

  Widget _romStep(ThemeData theme) {
    // A ROM already chosen: offering the game again is noise.
    final catalog = _catalogMatch != null && _romPath == null;
    final local = _localRomPath != null && _romPath == null && _downloadedPath == null;
    final looking = _romLookups > 0 && _romPath == null && !catalog && !local;
    return ListView(
      children: [
        _sectionTitle(theme, Icons.sd_card, 'Select ROM', 'Choose the game file to patch.'),
        // What the lookups found comes first, so its Use/Download button is the
        // step's first control (and takes focus when nothing has it yet); the
        // file row below stays the alternative. The file on the device before
        // the download: it is instant. Everything keyed: cards and the
        // placeholder come and go above the note and the file row, and a
        // control must keep its focus (A on "Use this file" never turning into
        // a download, "Choose" never dropping focus when the lookup ends).
        if (local) ...[
          KeyedSubtree(key: const ValueKey('rom-local-card'), child: _localRomCard(theme)),
          const SizedBox(height: 16),
        ],
        if (catalog) ...[
          KeyedSubtree(key: const ValueKey('rom-catalog-card'), child: _catalogCard(theme)),
          const SizedBox(height: 16),
        ],
        if (looking) ...[
          KeyedSubtree(key: const ValueKey('rom-lookup-skeleton'), child: _romLookupSkeleton(theme)),
          const SizedBox(height: 16),
        ],
        Container(
          key: const ValueKey('rom-note'),
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  romExpectation(info.gameId),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        // The library's card says how to get the game; the file picker would
        // just repeat it, so it collapses into a small alternative.
        if (catalog)
          Padding(
            key: const ValueKey('rom-pick-instead'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickRom,
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Pick a file instead'),
              ),
            ),
          )
        else
          Container(
            key: const ValueKey('rom-file-row'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_romPath == null ? 'No ROM selected' : p.basename(_romPath!), overflow: TextOverflow.ellipsis)),
                OutlinedButton(
                  onPressed: _pickRom,
                  child: Text(_romPath != null ? 'Change' : (local ? 'Pick a file instead' : 'Choose')),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Where the found card will appear, while the lookups run: the card's
  /// outline in grey bars over a running line.
  Widget _romLookupSkeleton(ThemeData theme) {
    final grey = theme.colorScheme.surfaceContainerHighest;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
          widthFactor: widthFactor,
          alignment: Alignment.centerLeft,
          child: Container(height: height, decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(4))),
        );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 56, height: 78, decoration: BoxDecoration(color: grey, borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Looking for ${gameName(info)}…',
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                      const SizedBox(height: 8),
                      // As tall as the found card's title, file name and button.
                      bar(0.7, 16),
                      const SizedBox(height: 6),
                      bar(0.4, 12),
                      const SizedBox(height: 12),
                      bar(0.35, 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  /// The game found among the device's files, when the catalog has no entry
  /// or its download is not on the device.
  Widget _localRomCard(ThemeData theme) {
    final path = _localRomPath!;
    final boxart = _localRomBoxart;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              height: 78,
              child: boxart != null
                  ? CachedNetworkImage(
                      imageUrl: boxart,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.sd_storage_outlined),
                    )
                  : const Icon(Icons.sd_storage_outlined, size: 40),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Found on this device', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 2),
                  Text(_localRomTitle(path), style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(p.basename(path),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  // Autofocus applies only while nothing in the route has focus,
                  // so a card arriving late never takes it from the user.
                  FilledButton.icon(
                    autofocus: true,
                    onPressed: () => setState(() => _romPath = path),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Use this file'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogCard(ThemeData theme) {
    final m = _catalogMatch!;
    final sizeMb = m.game.size > 0 ? '${(m.game.size / 1000000).toStringAsFixed(0)} MB' : '';
    final dl = ref.watch(downloadProvider);
    final status = dl.taskStatus[m.game.gameId];
    final prog = dl.taskProgress[m.game.gameId]?.progress;
    // Status wins over a file-exists check: the download writes into the target
    // path, so the file can be present-but-partial mid-download.
    final downloading = status == TaskStatus.running || status == TaskStatus.enqueued || (prog != null && prog > 0 && prog < 1);
    final downloaded = downloading ? null : _downloadedPath;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              height: 78,
              child: m.game.boxart != null
                  ? CachedNetworkImage(
                      imageUrl: m.game.boxart!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(Icons.videogame_asset),
                    )
                  : const Icon(Icons.videogame_asset, size: 40),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Found in your library', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 2),
                  Text(m.game.title, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text([m.console.name, sizeMb].where((s) => s.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  if (downloaded != null)
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => _useFoundRom(downloaded),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Use downloaded file'),
                    )
                  else if (downloading)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(value: (prog != null && prog > 0) ? prog : null),
                        const SizedBox(height: 4),
                        Text(
                          prog != null && prog > 0 ? 'Downloading ${(prog * 100).round()}%' : 'Starting download…',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    )
                  else
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: _downloadCatalogGame,
                      icon: const Icon(Icons.download, size: 18),
                      label: Text(sizeMb.isEmpty ? 'Download' : 'Download ($sizeMb)'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Look: logos, unused slots, screen art -----------------------------

  Widget _lookStep(ThemeData theme) {
    final slots = info.imageSlots;
    return ListView(
      children: [
        _sectionTitle(theme, Icons.palette_outlined, 'Look', 'Choose the team logos and screen art the patch draws into the game.'),
        if (info.supportsLogos || info.supportsBlankUnused || info.supportsLooks)
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                if (info.supportsLooks)
                  SwitchListTile(
                    secondary: const Icon(Icons.face_outlined),
                    title: const Text('Try to match player visual'),
                    subtitle: const Text('Each player\'s look follows his photo: complexion, hair and build where the game has them. Off gives everyone one plain look.'),
                    value: _matchLooks,
                    onChanged: (v) => setState(() => _matchLooks = v),
                  ),
                if (info.supportsLogos)
                  SwitchListTile(
                    secondary: const Icon(Icons.shield_outlined),
                    title: const Text('Team logos'),
                    subtitle: Text(logosNote(info.gameId)),
                    value: _useLogos,
                    onChanged: (v) => setState(() => _useLogos = v),
                  ),
                if (info.supportsBlankUnused)
                  SwitchListTile(
                    secondary: const Icon(Icons.layers_clear_outlined),
                    title: const Text('Blank unused slots'),
                    subtitle: const Text('Teams the league does not fill get an empty name and flag instead of the game\'s originals.'),
                    value: _blankUnused,
                    onChanged: (v) => setState(() => _blankUnused = v),
                  ),
              ],
            ),
          ),
        if (slots.isNotEmpty) ...[
          Row(
            children: [
              Expanded(child: Text('Screen art', style: theme.textTheme.titleSmall)),
              if (_loadingImages)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              FilledButton.tonalIcon(
                onPressed: _loadingImages ? null : () => _useBranded(slots),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('Retro Toolbox art everywhere'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Each screen keeps its layout: edit the exported PNG in place, or let the app draw Retro Toolbox art with the league and season.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          // Discreet: a ZIP of template PNGs with the content area outlined.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: theme.textTheme.labelSmall),
              onPressed: _downloadingTemplates ? null : _downloadTemplates,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download templates'),
            ),
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 520 ? 2 : 1;
              final width = (c.maxWidth - 12 * (columns - 1)) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [for (final slot in slots) SizedBox(width: width, child: _slotCard(theme, slot))],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _slotCard(ThemeData theme, String slot) {
    final (name, description) = imageSlotLabel(slot, info.gameId);
    final pick = _imagePicks[slot];
    final shown = pick?.path ?? _romImages[slot];
    final status = pick == null ? 'Original' : (pick.branded ? 'Retro Toolbox' : 'Custom PNG');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              color: const Color(0xFF0E0A1C),
              padding: const EdgeInsets.all(8),
              child: shown == null
                  ? Center(
                      child: _loadingImages
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.image_outlined, color: theme.colorScheme.onSurfaceVariant),
                    )
                  : Image.file(
                      File(shown),
                      key: ValueKey(shown),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, color: theme.colorScheme.onSurfaceVariant),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Expanded(child: Text(name, style: theme.textTheme.titleSmall)),
                Chip(
                  label: Text(status),
                  visualDensity: VisualDensity.compact,
                  labelStyle: theme.textTheme.labelSmall,
                  backgroundColor: pick == null ? null : theme.colorScheme.primaryContainer,
                  side: BorderSide.none,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            // Wraps on narrow cards instead of overflowing.
            child: OverflowBar(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _replaceImage(slot),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Replace'),
                ),
                TextButton.icon(
                  onPressed: _loadingImages ? null : () => _useBranded([slot]),
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: const Text('Branded'),
                ),
                if (pick != null)
                  IconButton(
                    tooltip: 'Back to the original',
                    onPressed: () => setState(() => _imagePicks.remove(slot)),
                    icon: const Icon(Icons.restart_alt),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _patchStep(ThemeData theme) {
    if (_busy) {
      return GameTriviaLoader(status: _status, progress: _progress, seed: info.gameId.hashCode.abs() + 1);
    }
    if (_result != null) {
      return ListView(
        children: [
          _sectionTitle(theme, Icons.check_circle, 'Done', 'The patched ROM has been written.'),
          Card(
            color: theme.colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.basename(_result!.outputPath), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('Teams: ${_result!.teamsPatched}   Players: ${_result!.playersPatched}'),
                  for (final note in _result!.notes) ...[
                    const SizedBox(height: 6),
                    Text(note, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    }
    final outDir = _outputDir ?? _defaultOutputDir();
    return ListView(
      children: [
        _sectionTitle(theme, Icons.build, 'Patch', 'Choose where to save, then Patch writes the edited rosters.'),
        Text('Output folder', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(outDir.isEmpty ? 'No folder' : outDir, overflow: TextOverflow.ellipsis)),
              OutlinedButton(
                onPressed: () async {
                  final dir = await pickDirectory(context, title: 'Select output folder');
                  if (dir != null && mounted) setState(() => _outputDir = dir);
                },
                child: const Text('Change'),
              ),
            ],
          ),
        ),
        if (_language != null) ...[
          const SizedBox(height: 16),
          Text('Game language', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          DropdownButton<String>(
            value: _language,
            isExpanded: true,
            items: [for (final l in info.languages) DropdownMenuItem(value: l, child: Text(languageName(l)))],
            onChanged: (v) => setState(() => _language = v ?? _language),
          ),
        ],
      ],
    );
  }

  Widget _statusRow(ThemeData theme, IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color))),
        ],
      );

  /// Back (when there is a previous step) and the step's primary action.
  List<Widget> _navButtons() {
    final isPatch = _step == _Step.patch;
    final dense = _short ? VisualDensity.compact : null;
    return [
      if (_index > 0)
        TextButton(
          style: TextButton.styleFrom(visualDensity: dense),
          onPressed: _busy ? null : () => setState(() => _index--),
          child: const Text('Back'),
        ),
      if (_short) const SizedBox(width: 4) else const Spacer(),
      if (isPatch && _result != null)
        FilledButton.icon(
          style: FilledButton.styleFrom(visualDensity: dense),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check),
          label: const Text('Close'),
        )
      else if (isPatch)
        FilledButton.icon(
          style: FilledButton.styleFrom(visualDensity: dense),
          onPressed: (_busy || _romPath == null) ? null : _patch,
          icon: const Icon(Icons.build),
          label: const Text('Patch ROM'),
        )
      else
        FilledButton(
          style: FilledButton.styleFrom(visualDensity: dense),
          onPressed: (_canAdvance && !_busy) ? _next : null,
          child: const Text('Next'),
        ),
    ];
  }

  Widget _footer(ThemeData theme) {
    return Container(
      padding: _compact ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4) : const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(children: _navButtons()),
    );
  }
}
