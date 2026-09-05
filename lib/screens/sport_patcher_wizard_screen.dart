import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/patcher_info.dart';
import 'package:roms_downloader/models/roster_doc.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:roms_downloader/models/task_queue_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/download_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/task_queue_provider.dart';
import 'package:roms_downloader/screens/team_editor_screen.dart';
import 'package:roms_downloader/services/sports_rom_lookup.dart';
import 'package:roms_downloader/services/sports_service.dart';
import 'package:roms_downloader/widgets/game_trivia.dart';
import 'package:roms_downloader/widgets/menu_grid/sport_slug.dart';

/// One patch flow per game, in the app's own wizard idiom: step dots up top,
/// one focused step at a time, Back/Next footer.
///
/// After fetch the rosters become a full editor (reorder teams, add/delete
/// teams, edit each squad). Team order is the ROM slot order, so it replaces a
/// separate slot-mapping step.
class SportPatcherWizardScreen extends ConsumerStatefulWidget {
  final PatcherInfo info;
  const SportPatcherWizardScreen({super.key, required this.info});

  @override
  ConsumerState<SportPatcherWizardScreen> createState() => _WizardState();
}

enum _Step { rosters, teams, rom, patch }

class _WizardState extends ConsumerState<SportPatcherWizardScreen> {
  final List<_Step> _steps = const [_Step.rosters, _Step.teams, _Step.rom, _Step.patch];
  int _index = 0;

  late String _provider = widget.info.defaultProvider;
  int _season = DateTime.now().year;

  bool get _isSoccer => widget.info.sport == 'soccer';
  List<League> _leagues = [];
  League? _selectedLeague;
  bool _loadingLeagues = false;

  RosterDoc? _doc;
  String? _romPath;
  String? _outputDir;

  // Catalog lookup: if the user's console catalog has this game, offer a
  // download instead of a manual file pick.
  RomCatalogMatch? _catalogMatch;
  String? _catalogDownloadDir;

  bool _busy = false;
  double _progress = 0;
  String? _status;
  String? _error;
  PatchResult? _result;

  PatcherInfo get info => widget.info;
  _Step get _step => _steps[_index];

  /// The rosters step has something to choose only for soccer (league), a
  /// multi-source game, or a source that exposes a season. Otherwise there's
  /// nothing to pick, so we fetch immediately and skip to the editor.
  bool get _rostersHasOptions =>
      _isSoccer || info.providers.length > 1 || providerHasSeason(_provider);

  @override
  void initState() {
    super.initState();
    if (_isSoccer) _loadLeagues();
    _lookupRom();
    if (!_rostersHasOptions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
    }
  }

  /// Search the console catalog for this game so the ROM step can offer a
  /// download. Best-effort — any failure just leaves the manual file picker.
  Future<void> _lookupRom() async {
    final consoles = ref.read(appStateProvider).consolesList;
    if (consoles.isEmpty) return;
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
    }
  }

  String? get _downloadedPath {
    final m = _catalogMatch, dir = _catalogDownloadDir;
    if (m == null || dir == null) return null;
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
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Select a leagues JSON file',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = result?.files.firstOrNull?.path;
      if (path == null) return;
      await SportsService.importCustomLeagues(path);
      await _loadLeagues();
    } catch (e) {
      if (mounted) setState(() => _error = 'Custom leagues: $e');
    }
  }

  Future<void> _fetch() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Contacting the provider…';
      _error = null;
    });
    try {
      final (_, file) = await SportsService.fetchRosters(
        gameId: info.gameId,
        provider: _provider,
        season: _season,
        league: _selectedLeague,
        onProgress: (v) => setState(() => _progress = v),
        onStatus: (s) => setState(() => _status = s),
      );
      final doc = await SportsService.loadRoster(file);
      // Fetch is the step's forward action — on success go straight to the
      // editor instead of making the user press a separate Next.
      setState(() {
        _doc = doc;
        if (_step == _Step.rosters) _index++;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickRom() async {
    final result = await FilePicker.platform.pickFiles(dialogTitle: 'Select the ROM to patch');
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    setState(() => _romPath = path);
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
    final base = p.basenameWithoutExtension(romPath);
    final ext = p.extension(romPath);
    final outputPath = p.join(dir, '$base [${doc.leagueName} $_season]$ext');

    setState(() {
      _busy = true;
      _progress = 0;
      _status = 'Preparing…';
      _error = null;
    });
    try {
      final rostersFile = await SportsService.saveRoster(doc);
      // Team order is the slot order for games that need an explicit mapping.
      final slotMapping = info.requiresSlotMapping
          ? [
              for (var i = 0; i < doc.teams.length; i++)
                SlotMapping(slotIndex: i, teamId: doc.teams[i].id, teamName: doc.teams[i].name),
            ]
          : null;
      final result = await SportsService.patchRom(
        gameId: info.gameId,
        provider: _provider,
        romPath: romPath,
        outputPath: outputPath,
        rostersFile: rostersFile,
        slotMapping: slotMapping,
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
        return !_isSoccer || _selectedLeague != null;
      case _Step.teams:
        return _doc != null && _doc!.teams.isNotEmpty;
      case _Step.rom:
        return _romPath != null;
      case _Step.patch:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _footer(theme),
          ],
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, Color accent) {
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
        _Step.rosters => 'Rosters',
        _Step.teams => 'Teams',
        _Step.rom => 'ROM',
        _Step.patch => 'Patch',
      };

  Widget _sectionTitle(ThemeData theme, IconData icon, String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: theme.colorScheme.primary), const SizedBox(width: 10), Expanded(child: Text(title, style: theme.textTheme.titleMedium))]),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
        ],
      );

  Widget _body(ThemeData theme) {
    final content = switch (_step) {
      _Step.rosters => _rostersStep(theme),
      _Step.teams => _teamsStep(theme),
      _Step.rom => _romStep(theme),
      _Step.patch => _patchStep(theme),
    };
    return Padding(
      padding: const EdgeInsets.all(24),
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

  // -- Step 1: source / season / league / fetch ---------------------------

  Widget _rostersStep(ThemeData theme) {
    // While fetching (auto or manual), fill the step with the trivia loader.
    if (_busy) return GameTriviaLoader(status: _status, seed: info.gameId.hashCode.abs());
    return ListView(
      children: [
        _sectionTitle(theme, Icons.tune, 'Rosters',
            'Pick your options, then Next downloads the league data.'),
        _sourceAndSeason(theme),
        if (_isSoccer) _leaguePicker(theme),
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
                    _doc = null;
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
                IconButton.filledTonal(onPressed: () => setState(() { _season--; _doc = null; }), icon: const Icon(Icons.remove)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('$_season', style: theme.textTheme.headlineSmall),
                ),
                IconButton.filledTonal(onPressed: () => setState(() { _season++; _doc = null; }), icon: const Icon(Icons.add)),
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
                  for (final l in _leagues)
                    DropdownMenuItem(value: l, child: Text(l.label, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() {
                  _selectedLeague = v;
                  _doc = null;
                }),
              ),
            _customLeaguesHelp(theme),
          ],
        ),
      );

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
          TextField(
            controller: _leaguePasteCtrl,
            maxLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Paste league JSON here'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
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

  // -- Step 2: the team editor -------------------------------------------

  Widget _teamsStep(ThemeData theme) {
    final doc = _doc;
    if (doc == null) return const Center(child: Text('Fetch rosters first.'));
    final teams = doc.teams;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(theme, Icons.groups, doc.leagueName,
                  'Drag to reorder (slot order), tap to edit a squad, swipe options to delete.'),
            ),
            FilledButton.tonalIcon(
              onPressed: _addTeam,
              icon: const Icon(Icons.add),
              label: const Text('Add team'),
            ),
          ],
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: teams.length,
            onReorder: (oldI, newI) => setState(() {
              if (newI > oldI) newI--;
              teams.insert(newI, teams.removeAt(oldI));
            }),
            itemBuilder: (context, i) {
              final t = teams[i];
              return Card(
                key: ValueKey('team_${t.id}_$i'),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: _teamCrest(theme, t),
                  title: Text(t.name),
                  subtitle: Text('${t.players.length} players'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => teams.removeAt(i)),
                      ),
                      const Icon(Icons.drag_handle),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => TeamEditorScreen(team: t, gameId: info.gameId, sport: info.sport)),
                    );
                    setState(() {});
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _teamCrest(ThemeData theme, RosterTeam t) {
    final url = t.logoUrl;
    if (url.isEmpty) {
      return CircleAvatar(child: Text(t.name.isEmpty ? '?' : t.name[0]));
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
        errorWidget: (_, __, ___) => CircleAvatar(child: Text(t.name.isEmpty ? '?' : t.name[0])),
      ),
    );
  }

  Future<void> _addTeam() async {
    final nameCtrl = TextEditingController();
    final jsonCtrl = TextEditingController();
    String? err;
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
                    title: const Text('Or paste / import team JSON'),
                    children: [
                      Text(
                        'A team object: {"name": "...", "players": [{"name","position","number"}]} '
                        'Or the full roster shape with a "team" key.',
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: jsonCtrl,
                        maxLines: 6,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                        decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '{ "name": "...", "players": [...] }'),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
                            final path = r?.files.firstOrNull?.path;
                            if (path != null) jsonCtrl.text = await File(path).readAsString();
                          },
                          icon: const Icon(Icons.upload_file, size: 18),
                          label: const Text('Import from file'),
                        ),
                      ),
                    ],
                  ),
                  if (err != null) Padding(
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
                    _doc!.addTeamFromJson(map);
                  } catch (e) {
                    setLocal(() => err = 'Invalid team JSON: $e');
                    return;
                  }
                } else if (nameCtrl.text.trim().isNotEmpty) {
                  _doc!.addTeam(nameCtrl.text.trim());
                } else {
                  setLocal(() => err = 'Enter a name or paste JSON');
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
    if (result == true) setState(() {});
  }

  // -- Step 3 / 4 --------------------------------------------------------

  Widget _romStep(ThemeData theme) => ListView(
        children: [
          _sectionTitle(theme, Icons.sd_card, 'Select ROM', 'Choose the game file to patch.'),
          Container(
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
          Container(
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
                OutlinedButton(onPressed: _pickRom, child: Text(_catalogMatch == null ? 'Choose' : 'Pick a file instead')),
              ],
            ),
          ),
          if (_catalogMatch != null) ...[
            const SizedBox(height: 16),
            _catalogCard(theme),
          ],
        ],
      );

  Widget _catalogCard(ThemeData theme) {
    final m = _catalogMatch!;
    final sizeMb = m.game.size > 0 ? '${(m.game.size / 1000000).toStringAsFixed(0)} MB' : '';
    final dl = ref.watch(downloadProvider);
    final status = dl.taskStatus[m.game.gameId];
    final prog = dl.taskProgress[m.game.gameId]?.progress;
    // Status wins over a file-exists check: the download writes into the target
    // path, so the file can be present-but-partial mid-download.
    final downloading = status == TaskStatus.running || status == TaskStatus.enqueued ||
        (prog != null && prog > 0 && prog < 1);
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
                      onPressed: () => setState(() => _romPath = downloaded),
                      icon: const Icon(Icons.check, size: 18),
                      label: Text(_romPath == downloaded ? 'Selected' : 'Use downloaded file'),
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
                  final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select output folder');
                  if (dir != null) setState(() => _outputDir = dir);
                },
                child: const Text('Change'),
              ),
            ],
          ),
        ),
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

  Widget _footer(ThemeData theme) {
    final isPatch = _step == _Step.patch;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))),
      child: Row(
        children: [
          if (_index > 0)
            TextButton(onPressed: _busy ? null : () => setState(() => _index--), child: const Text('Back')),
          const Spacer(),
          if (isPatch && _result != null)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check),
              label: const Text('Close'),
            )
          else if (isPatch)
            FilledButton.icon(
              onPressed: (_busy || _romPath == null) ? null : _patch,
              icon: const Icon(Icons.build),
              label: const Text('Patch ROM'),
            )
          else
            FilledButton(
              // On the rosters step Next runs the fetch (which advances on
              // success); elsewhere it just moves forward.
              onPressed: (_canAdvance && !_busy)
                  ? () {
                      if (_step == _Step.rosters && _doc == null) {
                        _fetch();
                      } else {
                        setState(() => _index++);
                      }
                    }
                  : null,
              child: const Text('Next'),
            ),
        ],
      ),
    );
  }
}
