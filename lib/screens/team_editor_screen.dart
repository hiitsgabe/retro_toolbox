import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/services/sports_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/kit_picker.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';

/// Edits one team's squad: reorder, add, remove, edit players (incl. stats),
/// set the team color for games that use it, and its kits for games whose
/// patch draws them. Player order is the ROM order, so the list is split into
/// starting lineup, bench, and extras the ROM won't store, with a warning when
/// the game will start someone else. Baseball keeps pitchers after the
/// position players, as the game writes them. Mutates the [RosterTeam] in place.
class TeamEditorScreen extends StatefulWidget {
  final RosterTeam team;
  final String gameId;
  final String sport;

  /// The game; its `supportsKits` adds the Kits section. Null: no kits.
  final PatcherInfo? info;

  /// The ROM being patched: the game's own kit designs come from it.
  final String? romPath;

  /// The team's ROM slot (absolute); null when it has none.
  final int? slot;

  /// NHL '94: the (goalies, forwards, defencemen) the slot keeps, from the
  /// image; null for the game's usual 2, 14 and 7.
  final List<int>? rosterCounts;

  /// The wizard's team id -> logo PNG overrides, edited from the header;
  /// null when the game draws no logos.
  final Map<int, String>? teamLogos;

  /// Replaces the worker's kit preview job. Tests and screenshots only.
  @visibleForTesting
  final KitPreviewLoader? kitLoader;

  /// Replaces the worker's kit template job. Tests only.
  @visibleForTesting
  final KitTemplateZip? kitTemplateZip;

  const TeamEditorScreen({
    super.key,
    required this.team,
    required this.gameId,
    required this.sport,
    this.info,
    this.romPath,
    this.slot,
    this.rosterCounts,
    this.teamLogos,
    this.kitLoader,
    this.kitTemplateZip,
  });

  @override
  State<TeamEditorScreen> createState() => _TeamEditorScreenState();
}

class _TeamEditorScreenState extends State<TeamEditorScreen> {
  RosterTeam get team => widget.team;
  late final GameRoster _roster = gameRoster(widget.gameId);
  late final int _starters = (team.extraRaw['lineup_size'] as num?)?.toInt() ?? _roster.starters;
  int get _rosterSize => _roster.rosterSize;
  bool get _splitsPitchers => gameSplitsPitchers(widget.gameId);
  bool get _usesColor => gameUsesTeamColor(widget.gameId);
  bool get _hasKits => widget.info?.supportsKits == true;

  /// Baseball: regroups the list the way the game writes it, so the labels
  /// show who is stored where. Call after every change to the order.
  void _regroup() {
    if (_splitsPitchers) team.players.setAll(0, splitPitchers(team.players));
  }

  // -- Kits ---------------------------------------------------------------

  /// The game's jersey designs, exported once per ROM.
  static final _templatesFor = <String, List<KitTemplate>>{};

  late final KitPreviewLoader _loadKits = widget.kitLoader ??
      (kits, {templates = false, slots, which, colours, teams, home}) => SportsService.kitPreviews(
            gameId: widget.gameId,
            kits: kits,
            templates: templates,
            romPath: widget.romPath,
            slots: slots,
            which: which,
            colours: colours,
            teams: teams,
            home: home,
          );

  /// 'home' / 'away' -> png.
  final _kitPreviews = <String, String>{};
  List<KitTemplate> _templates = const [];
  bool _loadingKits = false;
  String? _kitError;

  @override
  void initState() {
    super.initState();
    _regroup();
    if (_hasKits) _refreshKits();
  }

  /// Re-renders both kits in one job, mounted on the player when the ROM and
  /// slot are known; the first job for a ROM also exports the game's designs.
  Future<void> _refreshKits() async {
    final info = widget.info!, rom = widget.romPath, slot = widget.slot;
    final cached = rom == null ? null : _templatesFor[rom];
    if (cached != null) _templates = cached;
    final needTemplates = info.kitTemplates && rom != null && cached == null;
    const sides = ['home', 'away'];
    // The raw choice (null = default): the worker draws it from the colours.
    final kits = {for (final s in sides) s: kitChoice(team, home: s == 'home')};
    setState(() {
      _loadingKits = true;
      _kitError = null;
    });
    try {
      final r = await _loadKits(
        kits,
        templates: needTemplates,
        slots: slot == null ? null : {for (final s in sides) s: slot},
        which: {for (final s in sides) s: s},
        colours: {for (final s in sides) s: teamColours(team)},
        teams: {for (final s in sides) s: teamIdentity(team)},
        home: {'away': kits['home']},
      );
      if (!mounted) return;
      setState(() {
        if (needTemplates) _templates = _templatesFor[rom] = r.templates;
        // Replace, never merge: a choice the worker did not render (a game
        // design, say) must not keep the old thumbnail; it gets the design's own.
        for (final s in sides) {
          final path = r.kits[s] ?? kitTemplatePath(kits[s], _templates);
          if (path == null) {
            _kitPreviews.remove(s);
          } else {
            _kitPreviews[s] = path;
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _kitError = 'Kit previews: $e');
    } finally {
      if (mounted) setState(() => _loadingKits = false);
    }
  }

  Future<void> _editKit(bool home) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => KitPickerSheet(
        team: team,
        info: widget.info!,
        templates: _templates,
        loader: _loadKits,
        romPath: widget.romPath,
        slot: widget.slot,
        initialHome: home,
        kitTemplateZip: widget.kitTemplateZip,
      ),
    ));
    if (mounted) _refreshKits();
  }

  /// One kit, as the game shows it; opens the picker on that side.
  Widget _kitTile(ThemeData theme, bool home) => InkWell(
        focusColor: Colors.transparent, // DpadScope draws the one outline
        borderRadius: BorderRadius.circular(8),
        onTap: () => _editKit(home),
        child: SizedBox(
          width: 96,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 85,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: kitPreview(_kitPreviews[home ? 'home' : 'away'], loading: _loadingKits),
                ),
                const SizedBox(height: 4),
                Text(home ? 'Home kit' : 'Away kit', style: theme.textTheme.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  kitLabel(kitChoice(team, home: home)),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );

  /// Both kits side by side; the template download lives in the picker's
  /// Custom tab.
  Widget _kitsSection(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _kitTile(theme, true),
                    const SizedBox(width: 8),
                    _kitTile(theme, false),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => _editKit(true),
                      icon: const Icon(Icons.checkroom),
                      label: const Text('Change kits'),
                    ),
                  ],
                ),
                if (_kitError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Text(_kitError!, style: TextStyle(color: theme.colorScheme.error)),
                  ),
              ],
            ),
          ),
        ),
      );

  // -- Name and logo --------------------------------------------------------

  /// The short name is the team's code, which the slot-by-order games write
  /// as the 3 letters they show; the others find the team's slot by it.
  bool get _codeEditable => widget.info?.requiresSlotMapping == true;

  /// Renames the team (the patch writes `team.name`, and `team.code` where
  /// [_codeEditable]) and swaps its logo in the wizard's overrides.
  Future<void> _editTeam() async {
    final logos = widget.teamLogos;
    final nameCtrl = TextEditingController(text: team.name);
    final codeCtrl = TextEditingController(text: team.code);
    var logo = logos?[team.id];
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit team'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (logos != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 56, height: 56, child: teamCrest(team, override: logo)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.upload_file, size: 18),
                                  label: const Text('Choose logo…'),
                                  onPressed: () async {
                                    final path = await pickFile(ctx, title: 'Select a logo PNG for ${team.name}', extensions: ['png']);
                                    if (path != null) setLocal(() => logo = path);
                                  },
                                ),
                                if (logo != null)
                                  TextButton.icon(
                                    icon: const Icon(Icons.restart_alt, size: 18),
                                    label: const Text('Downloaded logo'),
                                    onPressed: () => setLocal(() => logo = null),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
                  if (_codeEditable)
                    TextField(
                      controller: codeCtrl,
                      maxLength: 3,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Short name', helperText: 'The 3 letters the game shows'),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      final name = nameCtrl.text.trim();
      if (name.isNotEmpty) team.name = name;
      if (_codeEditable) team.teamRaw['code'] = codeCtrl.text.trim().toUpperCase();
      if (logos != null) {
        if (logo == null) {
          logos.remove(team.id);
        } else {
          logos[team.id] = logo!;
        }
      }
    });
  }

  /// Logo, name and details, with the button that renames the team and
  /// changes its logo.
  Widget _teamHeader(ThemeData theme, String details) => Card(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        child: Padding(
          padding: EdgeInsets.all(_compact ? 8 : 12),
          child: Row(
            children: [
              SizedBox(width: _compact ? 40 : 56, height: _compact ? 40 : 56, child: teamCrest(team, override: widget.teamLogos?[team.id])),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(team.name, style: _compact ? theme.textTheme.titleMedium : theme.textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                    Text(
                      [if (team.code.isNotEmpty) team.code, details].join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: widget.teamLogos == null ? 'Rename team' : 'Rename or change logo',
                onPressed: _editTeam,
              ),
            ],
          ),
        ),
      );

  /// Short screens: no FAB over the list, colors scroll with it, dense rows.
  bool get _compact => MediaQuery.sizeOf(context).height < 640;

  /// Index of the player picked to swap; the next row tapped trades places
  /// with it. Null when not swapping.
  int? _swapFrom;

  /// Focus follows the swap: the picked row loses its buttons, so it takes
  /// focus, and afterwards the row the pick landed on.
  final _rowFocus = FocusNode();
  int? _focusRow;

  /// The picked row's move buttons: focus stays on the one pressed as the
  /// row travels.
  final _upFocus = FocusNode(), _downFocus = FocusNode();

  @override
  void dispose() {
    _rowFocus.dispose();
    _upFocus.dispose();
    _downFocus.dispose();
    super.dispose();
  }

  /// Moves the picked player one place up ([delta] -1) or down, keeping it
  /// picked: the d-pad's way to reorder without a drag.
  void _moveBy(int delta) {
    final players = team.players;
    final p = players[_swapFrom!];
    setState(() {
      players.insert(_swapFrom! + delta, players.removeAt(_swapFrom!));
      _regroup();
      _swapFrom = players.indexOf(p);
    });
    final at = _focusRow = _swapFrom!;
    // At the end of the list the button goes off: the row takes focus.
    final node = delta < 0 ? (at > 0 ? _upFocus : _rowFocus) : (at < players.length - 1 ? _downFocus : _rowFocus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) node.requestFocus();
    });
  }

  void _focusOn(int i) {
    _focusRow = i;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rowFocus.requestFocus();
    });
  }

  void _startSwap(int i) {
    setState(() => _swapFrom = i);
    _focusOn(i);
  }

  void _onRowTap(int i, RosterPlayer p) {
    final from = _swapFrom;
    if (from == null) {
      _editPlayer(p);
      return;
    }
    final players = team.players;
    final picked = players[from];
    setState(() {
      players[from] = players[i];
      players[i] = picked;
      _regroup();
      _swapFrom = null;
    });
    _focusOn(players.indexOf(picked));
  }

  Future<void> _removePlayer(int i) async {
    final name = team.players[i].name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove player?'),
        content: Text('Remove $name from this team?'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      team.players.removeAt(i);
      _regroup();
    });
    final n = team.players.length;
    if (n > 0) _focusOn(i < n ? i : n - 1);
  }

  Future<void> _editPlayer(RosterPlayer? player) async {
    final isNew = player == null;
    final nameCtrl = TextEditingController(text: player?.name ?? '');
    final posCtrl = TextEditingController(text: player?.position ?? '');
    final numCtrl = TextEditingController(text: player?.number?.toString() ?? '');

    // Stats are game-agnostic here: whatever numeric fields the fetched
    // player_stats holds become editable, so this works across every sport.
    final stats = player != null ? (team.statsFor(player.id) ?? {}) : <String, dynamic>{};
    final statCtrls = <String, TextEditingController>{
      for (final e in stats.entries)
        if (e.value is num) e.key: TextEditingController(text: '${e.value}'),
    };

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNew ? 'Add player' : 'Edit player'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: posCtrl, decoration: const InputDecoration(labelText: 'Position')),
                TextField(controller: numCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number')),
                if (statCtrls.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Statistics'),
                    children: [
                      for (final e in statCtrls.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: TextField(
                            controller: e.value,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(labelText: _prettyStat(e.key), isDense: true),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      final pl = player ?? team.addPlayer(name);
      pl.name = name;
      pl.position = posCtrl.text.trim();
      pl.number = int.tryParse(numCtrl.text.trim());
      if (statCtrls.isNotEmpty) {
        for (final e in statCtrls.entries) {
          final orig = stats[e.key];
          final parsed = num.tryParse(e.value.text.trim());
          if (parsed != null) stats[e.key] = orig is int ? parsed.toInt() : parsed;
        }
        team.setStats(pl.id, stats);
      }
      _regroup(); // a new player, or a new position
    });
  }

  static String _prettyStat(String key) => key.replaceAll('_', ' ');

  Future<void> _pickColorFor(String hex, void Function(String) onPicked) async {
    final picked = await showPaletteDialog(context, current: hexToColor(hex));
    if (picked == null) return;
    setState(() => onPicked(colorToHex(picked)));
    // The default kits are drawn from the colours.
    if (_hasKits) _refreshKits();
  }

  Color? _hexToColor(String hex) => hexToColor(hex);

  Widget _colorRow(ThemeData theme) => _compact
      ? _compactColorRow(theme)
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Card(
            child: Column(
              children: [
                _colorTile(theme, 'Primary color', team.color, (v) => team.color = v),
                const Divider(height: 1),
                _colorTile(theme, 'Alternate color', team.alternateColor, (v) => team.alternateColor = v),
              ],
            ),
          ),
        );

  /// Both colors on one line: a swatch per color, tap to change.
  Widget _compactColorRow(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            Text('Colors', style: theme.textTheme.labelLarge),
            const SizedBox(width: 12),
            _swatch(theme, 'Primary', team.color, (v) => team.color = v),
            const SizedBox(width: 8),
            _swatch(theme, 'Alternate', team.alternateColor, (v) => team.alternateColor = v),
          ],
        ),
      );

  Widget _swatch(ThemeData theme, String label, String hex, void Function(String) onPicked) {
    final c = _hexToColor(hex);
    return ActionChip(
      avatar: CircleAvatar(backgroundColor: c ?? theme.colorScheme.surfaceContainerHighest),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onPressed: () => _pickColorFor(hex, onPicked),
    );
  }

  Widget _colorTile(ThemeData theme, String label, String hex, void Function(String) onPicked) {
    final c = _hexToColor(hex);
    return ListTile(
      dense: _compact,
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c ?? theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: c == null ? const Icon(Icons.help_outline, size: 18) : null,
      ),
      title: Text(label),
      subtitle: Text(c == null ? 'Not set. Tap to choose' : 'Tap to change'),
      trailing: const Icon(Icons.palette),
      onTap: () => _pickColorFor(hex, onPicked),
    );
  }

  Widget _avatar(RosterPlayer p, bool starter) {
    final ring = starter ? Colors.green : Colors.grey;
    final url = p.photoUrl.isNotEmpty ? p.photoUrl : espnHeadshot(p.id, widget.sport);
    final fallback = CircleAvatar(radius: 20, child: Text(p.number?.toString() ?? p.name.characters.firstOrNull ?? '?'));
    Widget inner = url == null
        ? fallback
        : CircleAvatar(
            radius: 20,
            backgroundColor: Colors.transparent,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: url,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => fallback,
              ),
            ));
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
      child: inner,
    );
  }

  // B while swapping cancels the swap instead of leaving.
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: _swapFrom == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _swapFrom = null);
        },
        child: _scaffold(context),
      );

  Widget _scaffold(BuildContext context) {
    final theme = Theme.of(context);
    final players = team.players;
    final compact = _compact;
    final swapping = _swapFrom != null;
    final mlSize = masterLeagueSize(widget.gameId, widget.slot);
    final kept = widget.rosterCounts;
    final uses = kept == null || kept.length != 3 ? '$_rosterSize' : '${kept[0]} G, ${kept[1]} F, ${kept[2]} D';
    final countLine = '${players.length} players · ROM uses $uses${mlSize == null ? '' : ', Master League $mlSize'} (first $_starters start)';
    final warnings = lineupWarnings(widget.gameId, [for (final p in players) p.position], _starters);
    // Baseball stores up to 15 position players, then the pitchers. The
    // leftovers top up a short block, so up to 25 are stored either way.
    final pitchers = _splitsPitchers ? players.where((p) => isPitcher(p.position)).length : 0;
    final batters = _splitsPitchers ? min(battersStored, players.length - pitchers) : players.length;
    final pitchersKept = min(pitchersStored, pitchers);
    final leftovers = batters + pitchersKept; // baseball: rows that fill a short block
    final lineup = min(_starters, batters);
    final notes = [
      ...lineupNotes(widget.gameId),
      if (widget.gameId == 'nhl94-snes' && widget.slot != null && kept == null) "This slot's own counts are not known: marking as if it keeps 2 G, 14 F and 7 D.",
    ];
    // NHL 94 stores per position, not by row: each row it leaves out is
    // marked on its own, since stored rows may follow it. Everyone else
    // stores the first rows, so one heading marks where the rest start.
    final stored = gameStoresByPosition(widget.gameId) ? nhl94StoredRows([for (final p in players) p.position], widget.rosterCounts) : null;
    // The team, its colours and kits, and the notes, above the squad.
    Widget top(Widget last) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _teamHeader(theme, countLine),
            if (_usesColor) _colorRow(theme),
            if (_hasKits) _kitsSection(theme),
            for (final w in warnings) _warning(theme, w),
            for (final n in notes) _note(theme, n),
            last,
          ],
        );
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compact ? 48 : null,
        title: Text(team.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (compact && !swapping) IconButton(icon: const Icon(Icons.person_add), tooltip: 'Add player', onPressed: () => _editPlayer(null)),
        ],
      ),
      floatingActionButton: compact || swapping
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _editPlayer(null),
              icon: const Icon(Icons.person_add),
              label: const Text('Add player'),
            ),
      body: Column(
        children: [
          if (swapping)
            Material(
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    const Icon(Icons.swap_vert, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Tap a player to swap with ${players[_swapFrom!].name}, or move it with the arrows', overflow: TextOverflow.ellipsis),
                    ),
                    TextButton(
                      onPressed: () {
                        final from = _swapFrom!;
                        setState(() => _swapFrom = null);
                        _focusOn(from);
                      },
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: players.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    children: [top(const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No players. Add one.'))))],
                  )
                : ReorderableListView.builder(
                    padding: EdgeInsets.fromLTRB(12, compact ? 4 : 8, 12, compact ? 12 : 88),
                    itemCount: players.length,
                    onReorder: (oldI, newI) => setState(() {
                      if (newI > oldI) newI--;
                      players.insert(newI, players.removeAt(oldI));
                      _regroup();
                    }),
                    // Colors live in the header so they scroll away instead of
                    // pinning two tall tiles above the squad.
                    // While swapping, only the players: no colors, no labels.
                    header: swapping ? null : top(_sectionLabel(theme, startersLabel(widget.gameId), Colors.green)),
                    buildDefaultDragHandles: !swapping && !Handheld.current,
                    itemBuilder: (context, i) {
                      final p = players[i];
                      final starter = i < lineup;
                      final extra = stored == null ? i >= _rosterSize : !stored.contains(i);
                      final showBenchLabel = i == lineup && batters > lineup;
                      final showRotationLabel = _splitsPitchers && i == batters && pitchersKept > 0;
                      final showBullpenLabel = _splitsPitchers && i == batters + rotationSize && pitchersKept > rotationSize;
                      final showLeftoverLabel = _splitsPitchers && i == leftovers && i < _rosterSize && i < players.length;
                      final showExtraLabel = stored == null && i == _rosterSize;
                      final showNationalLabel = i == mlSize;
                      final picked = _swapFrom == i;
                      final subtitle = [
                        if (p.position.isNotEmpty) p.position,
                        if (p.nationality.isNotEmpty) p.nationality,
                        if (stored != null && extra) 'not stored',
                      ].join(' · ');
                      return Column(
                        key: ValueKey('player_${p.id}_$i'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showBenchLabel && !swapping) _sectionLabel(theme, 'Bench', Colors.grey),
                          if (showRotationLabel && !swapping) _sectionLabel(theme, 'Rotation', Colors.blue),
                          if (showBullpenLabel && !swapping) _sectionLabel(theme, 'Bullpen', Colors.blueGrey),
                          if (showLeftoverLabel && !swapping) _sectionLabel(theme, leftoverSection(widget.gameId, pitcher: isPitcher(p.position)), Colors.grey),
                          if (showNationalLabel && !swapping) _sectionLabel(theme, 'National team only (not in the Master League)', Colors.blueGrey),
                          if (showExtraLabel && !swapping) _sectionLabel(theme, 'Extra (not stored by this game)', theme.colorScheme.error),
                          Opacity(
                            opacity: extra ? 0.5 : 1,
                            child: Card(
                              margin: EdgeInsets.symmetric(vertical: compact ? 2 : 3),
                              shape: picked
                                  ? RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: BorderSide(color: theme.colorScheme.primary, width: 2),
                                    )
                                  : null,
                              color: starter ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : null,
                              // The buttons sit beside the tile, not in it: the
                              // d-pad only moves to what lies past the tile's edge.
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ListTile(
                                      focusNode: _focusRow == i ? _rowFocus : null,
                                      dense: compact,
                                      visualDensity: compact ? VisualDensity.compact : null,
                                      leading: _avatar(p, starter),
                                      title: Text(p.name, overflow: TextOverflow.ellipsis),
                                      subtitle: subtitle.isEmpty ? null : Text(subtitle, overflow: TextOverflow.ellipsis),
                                      onTap: () => _onRowTap(i, p),
                                    ),
                                  ),
                                  if (!swapping) ...[
                                    IconButton(
                                      icon: const Icon(Icons.swap_vert),
                                      tooltip: 'Move or swap',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _startSwap(i),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: 'Remove',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _removePlayer(i),
                                    ),
                                    if (!Handheld.current) ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                                  ],
                                  if (picked) ...moveButtons(i, players.length, _moveBy, up: _upFocus, down: _downFocus),
                                  const SizedBox(width: 8),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _warning(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber, size: 18, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
          ],
        ),
      );

  Widget _note(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 8, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          ],
        ),
      );

  Widget _sectionLabel(ThemeData theme, String text, Color dot) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4, left: 4),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(text.toUpperCase(), style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1)),
          ],
        ),
      );
}

const List<Color> _palette = [
  Color(0xFFD32F2F),
  Color(0xFFC2185B),
  Color(0xFF7B1FA2),
  Color(0xFF512DA8),
  Color(0xFF303F9F),
  Color(0xFF1976D2),
  Color(0xFF0288D1),
  Color(0xFF0097A7),
  Color(0xFF00796B),
  Color(0xFF388E3C),
  Color(0xFF689F38),
  Color(0xFFAFB42B),
  Color(0xFFFBC02D),
  Color(0xFFFFA000),
  Color(0xFFF57C00),
  Color(0xFFE64A19),
  Color(0xFF5D4037),
  Color(0xFF616161),
  Color(0xFF000000),
  Color(0xFFFFFFFF),
];

/// "RRGGBB" (upper case, no hash): the roster JSON's colour form.
String colorToHex(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

/// Parses "RRGGBB" or "#rrggbb"; null when it is not a 6-digit colour.
Color? hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// A d-pad friendly swatch grid; resolves to the picked colour, null when
/// dismissed. [current] is outlined.
Future<Color?> showPaletteDialog(BuildContext context, {Color? current, String title = 'Team color'}) => showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (n, c) in _palette.indexed)
              InkWell(
                customBorder: const CircleBorder(),
                focusColor: Colors.transparent, // DpadScope draws the one outline
                autofocus: n == 0,
                onTap: () => Navigator.pop(ctx, c),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: current?.toARGB32() == c.toARGB32() ? Theme.of(ctx).colorScheme.primary : Colors.black26,
                      width: current?.toARGB32() == c.toARGB32() ? 3 : 1,
                    ),
                  ),
                  child: current?.toARGB32() == c.toARGB32() ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              ),
          ],
        ),
      ),
    );

/// Up / down buttons for the row picked to move ([i] of [count]).
List<Widget> moveButtons(int i, int count, void Function(int delta) move, {FocusNode? up, FocusNode? down}) => [
      IconButton(
        focusNode: up,
        icon: const Icon(Icons.arrow_upward),
        tooltip: 'Move up',
        visualDensity: VisualDensity.compact,
        onPressed: i > 0 ? () => move(-1) : null,
      ),
      IconButton(
        focusNode: down,
        icon: const Icon(Icons.arrow_downward),
        tooltip: 'Move down',
        visualDensity: VisualDensity.compact,
        onPressed: i < count - 1 ? () => move(1) : null,
      ),
    ];

/// A team's logo: the user's PNG [override], else the downloaded one, else
/// its initial.
Widget teamCrest(RosterTeam t, {String? override}) {
  final fallback = CircleAvatar(child: Text(t.name.isEmpty ? '?' : t.name[0]));
  if (override != null) return Image.file(File(override), fit: BoxFit.contain, errorBuilder: (_, __, ___) => fallback);
  if (t.logoUrl.isEmpty) return fallback;
  return CachedNetworkImage(
    imageUrl: t.logoUrl,
    fit: BoxFit.contain,
    placeholder: (_, __) => const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
    errorWidget: (_, __, ___) => fallback,
  );
}
