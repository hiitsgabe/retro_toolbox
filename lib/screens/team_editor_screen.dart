import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/widgets/menu_grid/sport_slug.dart';

/// Edits one team's squad: reorder, add, remove, edit players (incl. stats), and
/// set the team color for games that use it. Player order is the ROM order, so
/// the list is split into starting lineup, bench, and extras the ROM won't
/// store. Mutates the [RosterTeam] in place.
class TeamEditorScreen extends StatefulWidget {
  final RosterTeam team;
  final String gameId;
  final String sport;
  const TeamEditorScreen({super.key, required this.team, required this.gameId, required this.sport});

  @override
  State<TeamEditorScreen> createState() => _TeamEditorScreenState();
}

class _TeamEditorScreenState extends State<TeamEditorScreen> {
  RosterTeam get team => widget.team;
  late final GameRoster _roster = gameRoster(widget.gameId);
  int get _starters => _roster.starters;
  int get _rosterSize => _roster.rosterSize;
  bool get _usesColor => gameUsesTeamColor(widget.gameId);

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
    setState(() {
      if (from != i) {
        final players = team.players;
        final a = players[from];
        players[from] = players[i];
        players[i] = a;
      }
      _swapFrom = null;
    });
    _focusOn(i);
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
    setState(() => team.players.removeAt(i));
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
    });
  }

  static String _prettyStat(String key) => key.replaceAll('_', ' ');

  static const List<Color> _palette = [
    Color(0xFFD32F2F), Color(0xFFC2185B), Color(0xFF7B1FA2), Color(0xFF512DA8),
    Color(0xFF303F9F), Color(0xFF1976D2), Color(0xFF0288D1), Color(0xFF0097A7),
    Color(0xFF00796B), Color(0xFF388E3C), Color(0xFF689F38), Color(0xFFAFB42B),
    Color(0xFFFBC02D), Color(0xFFFFA000), Color(0xFFF57C00), Color(0xFFE64A19),
    Color(0xFF5D4037), Color(0xFF616161), Color(0xFF000000), Color(0xFFFFFFFF),
  ];

  static String _toHex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

  Future<void> _pickColorFor(String hex, void Function(String) onPicked) async {
    final current = _hexToColor(hex);
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Team color'),
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
    if (picked != null) setState(() => onPicked(_toHex(picked)));
  }

  Color? _hexToColor(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  Widget _colorRow(ThemeData theme) => _compact ? _compactColorRow(theme) : Padding(
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
        : CircleAvatar(radius: 20, backgroundColor: Colors.transparent, child: ClipOval(
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
          if (compact && !swapping)
            IconButton(icon: const Icon(Icons.person_add), tooltip: 'Add player', onPressed: () => _editPlayer(null)),
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
                              _sectionLabel(theme, 'Starting lineup', Colors.green),
                            ],
                          ),
                    buildDefaultDragHandles: !swapping && !Handheld.current,
                    itemBuilder: (context, i) {
                      final p = players[i];
                      final starter = i < _starters;
                      final extra = i >= _rosterSize;
                      final showBenchLabel = i == _starters && players.length > _starters;
                      final showExtraLabel = i == _rosterSize && players.length > _rosterSize;
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
                          if (showExtraLabel && !swapping)
                            _sectionLabel(theme, 'Extra (not stored by this game)', theme.colorScheme.error),
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
                                          if (!Handheld.current)
                                            ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
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
