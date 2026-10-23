import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
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
  bool _downloadingKit = false;
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

  /// The kit template pack for this slot, drawn around the game design the
  /// team uses when it uses one (home first).
  Future<void> _downloadKitTemplate() async {
    final rom = widget.romPath, slot = widget.slot;
    if (rom == null || slot == null) return;
    // One job at a time: a second press would reuse the worker tag.
    setState(() {
      _downloadingKit = true;
      _kitError = null;
    });
    try {
      await downloadKitTemplate(
        context,
        gameId: widget.gameId,
        romPath: rom,
        slot: slot,
        template: kitTemplateIndex(kitChoice(team, home: true)) ?? kitTemplateIndex(kitChoice(team, home: false)),
        job: widget.kitTemplateZip,
      );
    } catch (e) {
      if (mounted) setState(() => _kitError = 'Kit template: $e');
    } finally {
      if (mounted) setState(() => _downloadingKit = false);
    }
  }

  Widget _kitRow(ThemeData theme, bool home) => InkWell(
        focusColor: Colors.transparent, // DpadScope draws the one outline
        onTap: () => _editKit(home),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(home ? 'Home kit' : 'Away kit', style: theme.textTheme.bodyLarge),
                    Text(kitLabel(kitChoice(team, home: home)), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );

  Widget _kitsSection(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _kitRow(theme, true),
              const Divider(height: 1),
              _kitRow(theme, false),
              if (_kitError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(_kitError!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              // Discreet: a ZIP of this slot's kit templates with the areas outlined.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: theme.textTheme.labelSmall),
                    onPressed: widget.romPath == null || widget.slot == null || _downloadingKit ? null : _downloadKitTemplate,
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Download kit template'),
                  ),
                ),
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

  @override
  void dispose() {
    _rowFocus.dispose();
    super.dispose();
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
    final countLine = '${players.length} players · ROM uses $_rosterSize (first $_starters start)';
    final warnings = lineupWarnings(widget.gameId, [for (final p in players) p.position], _starters);
    // Baseball stores up to 15 position players, then the pitchers. The
    // leftovers top up a short block, so up to 25 are stored either way.
    final pitchers = _splitsPitchers ? players.where((p) => isPitcher(p.position)).length : 0;
    final batters = _splitsPitchers ? min(battersStored, players.length - pitchers) : players.length;
    final pitchersKept = min(pitchersStored, pitchers);
    final leftovers = batters + pitchersKept; // baseball: rows that fill a short block
    final lineup = min(_starters, batters);
    final notes = lineupNotes(widget.gameId);
    // NHL 94 stores per position, not by row; everyone else the first rows.
    final stored = gameStoresByPosition(widget.gameId) ? nhl94StoredRows([for (final p in players) p.position]) : null;
    final firstExtra =
        stored == null ? _rosterSize : Iterable<int>.generate(players.length).firstWhere((i) => !stored.contains(i), orElse: () => players.length);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: compact ? 48 : null,
        title: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name, style: theme.textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                  Text(countLine, style: theme.textTheme.bodySmall),
                ],
              )
            : Text(team.name),
        bottom: compact
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(countLine, style: theme.textTheme.bodySmall),
                ),
              ),
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
                    Expanded(child: Text('Tap a player to swap with ${players[_swapFrom!].name}', overflow: TextOverflow.ellipsis)),
                    TextButton(
                      onPressed: () {
                        final from = _swapFrom!;
                        setState(() => _swapFrom = null);
                        _focusOn(from);
                      },
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: players.isEmpty
                ? const Center(child: Text('No players. Add one.'))
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
                    header: swapping
                        ? null
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_usesColor) _colorRow(theme),
                              if (_hasKits) _kitsSection(theme),
                              for (final w in warnings) _warning(theme, w),
                              for (final n in notes) _note(theme, n),
                              _sectionLabel(theme, 'Starting lineup', Colors.green),
                            ],
                          ),
                    buildDefaultDragHandles: !swapping && !Handheld.current,
                    itemBuilder: (context, i) {
                      final p = players[i];
                      final starter = i < lineup;
                      final extra = stored == null ? i >= _rosterSize : !stored.contains(i);
                      final showBenchLabel = i == lineup && batters > lineup;
                      final showRotationLabel = _splitsPitchers && i == batters && pitchersKept > 0;
                      final showBullpenLabel = _splitsPitchers && i == batters + rotationSize && pitchersKept > rotationSize;
                      final showLeftoverLabel = _splitsPitchers && i == leftovers && i < _rosterSize && i < players.length;
                      final showExtraLabel = i == firstExtra && players.length > firstExtra;
                      final picked = _swapFrom == i;
                      final subtitle = [
                        if (p.position.isNotEmpty) p.position,
                        if (p.nationality.isNotEmpty) p.nationality,
                      ].join(' · ');
                      return Column(
                        key: ValueKey('player_${p.id}_$i'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showBenchLabel && !swapping) _sectionLabel(theme, 'Bench', Colors.grey),
                          if (showRotationLabel && !swapping) _sectionLabel(theme, 'Rotation', Colors.blue),
                          if (showBullpenLabel && !swapping) _sectionLabel(theme, 'Bullpen', Colors.blueGrey),
                          if (showLeftoverLabel && !swapping) _sectionLabel(theme, leftoverSection(widget.gameId, pitcher: isPitcher(p.position)), Colors.grey),
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
                              child: ListTile(
                                focusNode: _focusRow == i ? _rowFocus : null,
                                dense: compact,
                                visualDensity: compact ? VisualDensity.compact : null,
                                leading: _avatar(p, starter),
                                title: Text(p.name, overflow: TextOverflow.ellipsis),
                                subtitle: subtitle.isEmpty ? null : Text(subtitle, overflow: TextOverflow.ellipsis),
                                trailing: swapping
                                    ? null
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.swap_vert),
                                            tooltip: 'Swap with another player',
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
                                      ),
                                onTap: () => _onRowTap(i, p),
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
