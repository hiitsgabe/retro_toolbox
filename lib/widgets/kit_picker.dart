import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/models/patcher_info.dart';
import 'package:retro_toolbox/models/roster_doc.dart';
import 'package:retro_toolbox/screens/team_editor_screen.dart' show colorToHex, hexToColor, showPaletteDialog;
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/services/sports_service.dart';
import 'package:retro_toolbox/utils/handheld.dart';

/// The shirt patterns the patch can draw, in the order the picker shows them.
const kitPatterns = ['plain', 'stripes', 'hoops', 'halves', 'sash', 'pinstripes', 'chevron', 'sleeves'];

/// Renders kit previews: {key: KIT} -> {key: png path}. A null KIT is the
/// team's default: its real kit when the library's catalogue knows the team
/// ([teams], per key: {id, name}), else drawn from [colours] (per key).
/// [slots] and [which] let the worker mount the kit on the player. Injected
/// so tests run without the worker.
typedef KitPreviewLoader = Future<KitPreviews> Function(
  Map<String, dynamic> kits, {
  bool templates,
  Map<String, int>? slots,
  Map<String, String>? which,
  Map<String, List<String>>? colours,
  Map<String, Map<String, Object?>>? teams,
});

/// Who the team is, for the worker's kit catalogue lookup.
Map<String, Object?> teamIdentity(RosterTeam t) => {'id': t.id, 'name': t.name};

String _hex(String teamHex, String fallback) {
  final h = teamHex.replaceAll('#', '').toLowerCase();
  return h.length == 6 ? '#$h' : fallback;
}

/// The team's colours as `#rrggbb`: shirt (grey when unset) and alternate.
/// A missing alternate is the shirt's contrast — black on a light shirt
/// (relative luminance above 0.3), white on a dark one — the library's rule.
List<String> teamColours(RosterTeam t) {
  final shirt = _hex(t.color, '#777777');
  final contrast = hexToColor(shirt)!.computeLuminance() > 0.3 ? '#000000' : '#ffffff';
  return [shirt, _hex(t.alternateColor, contrast)];
}

/// The kit the patch draws when the team has no choice, mirroring the
/// library's `default_kits`: a plain shirt in the team's colour (the
/// alternate away), white shorts unless the shirt is white (then the
/// secondary), socks like the shirt.
Map<String, dynamic> defaultKitSpec(RosterTeam t, {required bool home, String pattern = 'plain'}) {
  final [a, b] = teamColours(t);
  final shirt = home ? a : b, secondary = home ? b : a;
  return {
    'shirt': shirt,
    'secondary': secondary,
    'pattern': pattern,
    'shorts': shirt == '#ffffff' ? secondary : '#ffffff',
    'socks': shirt,
    'sleeves': null,
  };
}

/// The team's stored choice for its [home] or away kit: a kit spec,
/// `{image}`, `{template}` or null (the default).
dynamic kitChoice(RosterTeam t, {required bool home}) => (t.extraRaw['kits'] as Map?)?[home ? 'home' : 'away'];

/// Stores [kit] as the team's [home] or away choice; the patch reads it from
/// the roster JSON (`extra.kits`).
void setKitChoice(RosterTeam t, {required bool home, required dynamic kit}) {
  final kits = Map<String, dynamic>.from((t.extraRaw['kits'] as Map?) ?? const {'home': null, 'away': null});
  kits[home ? 'home' : 'away'] = kit;
  t.extraRaw['kits'] = kits;
}

/// A game design's own thumbnail, for a `{template}` choice the worker
/// returned no preview for; null for any other choice.
String? kitTemplatePath(dynamic kit, List<KitTemplate> templates) {
  if (kit is! Map || kit['template'] == null) return null;
  return templates.where((t) => t.index == kit['template']).firstOrNull?.path;
}

/// Short name of a choice: Default, Stripes, Design 44, Custom PNG.
String kitLabel(dynamic kit) {
  if (kit is! Map) return 'Default';
  if (kit['image'] != null) return 'Custom PNG';
  if (kit['template'] != null) return 'Design ${kit['template']}';
  final p = '${kit['pattern'] ?? 'plain'}';
  return '${p[0].toUpperCase()}${p.substring(1)}';
}

bool _isSpec(dynamic kit) => kit is Map && kit['shirt'] != null;

/// A kit preview PNG, or a placeholder (a spinner while [loading]).
Widget kitPreview(String? path, {bool loading = false, Widget? empty}) => path == null
    ? Center(
        child: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : empty ?? const Icon(Icons.checkroom),
      )
    : Image.file(
        File(path),
        key: ValueKey(path),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
      );

/// Builds a kit template ZIP; [SportsService.kitTemplateZip]'s shape, so
/// tests can stand in for the worker.
typedef KitTemplateZip = Future<String> Function(String gameId, {required String romPath, required int slot, int? template});

/// The game design [kit] uses, if it is one.
int? kitTemplateIndex(dynamic kit) => kit is Map && kit['template'] != null ? (kit['template'] as num).toInt() : null;

/// Builds the kit template pack for [slot] (drawn around [template] when the
/// kit uses a game design) and saves it next to the ROM on handhelds, else
/// where the user says. Throws when the worker fails.
Future<void> downloadKitTemplate(
  BuildContext context, {
  required String gameId,
  required String romPath,
  required int slot,
  int? template,
  KitTemplateZip? job,
}) async {
  final zip = await (job ?? SportsService.kitTemplateZip)(gameId, romPath: romPath, slot: slot, template: template);
  if (!context.mounted) return;
  await saveTemplateZip(context, zip, defaultDir: p.dirname(romPath), what: 'Kit template');
}

/// Copies a template [zip] where the user says and confirms in a SnackBar.
/// Handhelds have no native dialog: with a [defaultDir] the file lands there.
Future<void> saveTemplateZip(BuildContext context, String zip, {String? defaultDir, String what = 'Templates'}) async {
  final known = defaultDir != null && defaultDir.isNotEmpty;
  final dir = Handheld.current && known ? defaultDir : await pickDirectory(context, title: 'Save the templates to', initialDir: known ? defaultDir : null);
  if (dir == null || !context.mounted) return;
  final dest = p.join(dir, p.basename(zip));
  await File(zip).copy(dest);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what saved to $dest')));
}

/// Chooses one team's home and away kit: a pattern in its colours, one of the
/// game's designs, the user's PNG, or the default. Writes the choice into the
/// team as it is made.
/// A named run of a game's designs, by index: the picker shows one group at
/// a time so a disc's whole catalogue never floods the sheet.
typedef DesignGroup = ({String name, int first, int last});

/// WE2002's 95 jersey files: the national sides, then the classic and
/// all-star teams, then the Master League clubs.
const we2002DesignGroups = <DesignGroup>[
  (name: 'Nations', first: 0, last: 53),
  (name: 'Classics', first: 54, last: 62),
  (name: 'Master League', first: 63, last: 94),
];

/// Designs shown per page of a group: one row on a desktop-wide sheet.
const designsPerPage = 8;

/// The groups [templates] fall into for [gameId]; one unnamed group for a
/// game without a known catalogue, and only groups that hold a design.
List<DesignGroup> designGroups(String gameId, List<KitTemplate> templates) {
  final known = gameId == 'we2002' ? we2002DesignGroups : const <DesignGroup>[];
  final groups = [
    for (final g in known)
      if (templates.any((t) => t.index >= g.first && t.index <= g.last)) g,
  ];
  if (groups.isEmpty && templates.isNotEmpty) {
    groups.add((name: 'All', first: templates.first.index, last: templates.last.index));
  }
  return groups;
}

/// A design's label without the colour note in brackets ("Ireland (green)"
/// -> "Ireland").
String designLabel(KitTemplate t) {
  if (t.name.isEmpty) return 'Design ${t.index}';
  final cut = t.name.indexOf(' (');
  return cut > 0 ? t.name.substring(0, cut) : t.name;
}

class KitPickerSheet extends StatefulWidget {
  final RosterTeam team;
  final PatcherInfo info;
  final List<KitTemplate> templates;
  final KitPreviewLoader loader;

  /// Known ROM; without one the game's designs cannot be shown.
  final String? romPath;

  /// The team's ROM slot, so the preview is drawn as the game mounts it.
  final int? slot;

  /// Which side to open on.
  final bool initialHome;

  /// Replaces the worker's kit template job. Tests only.
  @visibleForTesting
  final KitTemplateZip? kitTemplateZip;

  const KitPickerSheet({
    super.key,
    required this.team,
    required this.info,
    this.templates = const [],
    required this.loader,
    this.romPath,
    this.slot,
    this.initialHome = true,
    this.kitTemplateZip,
  });

  @override
  State<KitPickerSheet> createState() => _KitPickerSheetState();
}

class _KitPickerSheetState extends State<KitPickerSheet> {
  late bool _home = widget.initialHome;
  RosterTeam get team => widget.team;

  /// The editable spec per side: the stored one when it is a spec, else the
  /// default. Colour rows and pattern tiles edit it.
  late final Map<bool, Map<String, dynamic>> _spec = {
    for (final h in [true, false]) h: _specOf(h)
  };

  /// `<side>_<pattern>` -> png.
  final _previews = <String, String>{};
  bool _loading = false;
  String? _error;

  /// side -> png of the current choice, drawn as the game shows it.
  final _currentPng = <String, String>{};
  bool _loadingCurrent = false;
  bool _downloading = false;

  /// The game designs shown: one group, one page of it.
  late List<DesignGroup> _groups = designGroups(widget.info.gameId, widget.templates);
  int _group = 0, _page = 0;

  List<KitTemplate> get _inGroup {
    if (_groups.isEmpty) return const [];
    final g = _groups[_group];
    return [
      for (final t in widget.templates)
        if (t.index >= g.first && t.index <= g.last) t
    ];
  }

  int get _pages => (_inGroup.length + designsPerPage - 1) ~/ designsPerPage;

  /// Opens the designs on the page holding [index], if it is one of them.
  void _showDesign(int? index) {
    if (index == null) return;
    final g = _groups.indexWhere((g) => index >= g.first && index <= g.last);
    if (g < 0) return;
    _group = g;
    final at = _inGroup.indexWhere((t) => t.index == index);
    _page = at < 0 ? 0 : at ~/ designsPerPage;
  }

  Map<String, dynamic> _specOf(bool home) {
    final k = kitChoice(team, home: home);
    return _isSpec(k) ? Map<String, dynamic>.from(k as Map) : defaultKitSpec(team, home: home);
  }

  String get _side => _home ? 'home' : 'away';
  dynamic get _current => kitChoice(team, home: _home);
  Map<String, dynamic> get _cur => _spec[_home]!;

  @override
  void didUpdateWidget(KitPickerSheet old) {
    super.didUpdateWidget(old);
    if (!identical(old.templates, widget.templates)) {
      _groups = designGroups(widget.info.gameId, widget.templates);
      _group = _page = 0;
      _showDesign(kitTemplateIndex(_current));
    }
  }

  @override
  void initState() {
    super.initState();
    _showDesign(kitTemplateIndex(_current));
    _loadPatterns();
    _refreshCurrent();
  }

  /// Re-renders the header: the side's current choice (null = default).
  Future<void> _refreshCurrent() async {
    final side = _side, key = 'current_$side', slot = widget.slot;
    final kit = kitChoice(team, home: _home);
    setState(() => _loadingCurrent = true);
    try {
      final r = await widget.loader(
        {key: kit},
        slots: slot == null ? null : {key: slot},
        which: {key: side},
        colours: {key: teamColours(team)},
        teams: {key: teamIdentity(team)},
      );
      if (!mounted) return;
      setState(() {
        final path = r.kits[key] ?? kitTemplatePath(kit, widget.templates);
        if (path == null) {
          _currentPng.remove(side);
        } else {
          _currentPng[side] = path;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Kit previews: $e');
    } finally {
      if (mounted) setState(() => _loadingCurrent = false);
    }
  }

  /// One job renders every pattern in both sides' colours.
  Future<void> _loadPatterns() async {
    final kits = {
      for (final h in [true, false])
        for (final p in kitPatterns) '${h ? 'home' : 'away'}_$p': {..._spec[h]!, 'pattern': p},
    };
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.loader(kits,
          templates: false, colours: {for (final k in kits.keys) k: teamColours(team)}, teams: {for (final k in kits.keys) k: teamIdentity(team)});
      if (mounted) setState(() => _previews.addAll(r.kits));
    } catch (e) {
      if (mounted) setState(() => _error = 'Kit previews: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _choose(dynamic kit) {
    setState(() => setKitChoice(team, home: _home, kit: kit));
    _refreshCurrent();
  }

  Future<void> _pickPng() async {
    final path = await pickFile(context, title: 'Select a kit PNG', extensions: ['png']);
    if (path == null || !mounted) return;
    _choose({'image': path});
  }

  /// This slot's kit template pack, around the current design if it is one.
  Future<void> _downloadTemplate() async {
    final rom = widget.romPath, slot = widget.slot;
    if (rom == null || slot == null) return;
    // One job at a time: a second press would reuse the worker tag.
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      await downloadKitTemplate(
        context,
        gameId: widget.info.gameId,
        romPath: rom,
        slot: slot,
        template: kitTemplateIndex(_current),
        job: widget.kitTemplateZip,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Kit template: $e');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pickColour(String key, String label) async {
    final c = await showPaletteDialog(context, current: hexToColor('${_cur[key] ?? ''}'), title: label);
    if (c == null || !mounted) return;
    _cur[key] = '#${colorToHex(c).toLowerCase()}';
    _choose(Map<String, dynamic>.from(_cur));
    _loadPatterns();
  }

  Widget _heading(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: theme.textTheme.titleSmall),
      );

  Widget _tile(
    ThemeData theme, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool autofocus = false,
    String? image,
    IconData icon = Icons.checkroom,
  }) =>
      InkWell(
        autofocus: autofocus,
        focusColor: Colors.transparent, // DpadScope draws the one outline
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: 88,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 72,
                height: 96,
                child: kitPreview(image, loading: _loading && icon == Icons.checkroom, empty: Icon(icon)),
              ),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      );

  Widget _colourRow(ThemeData theme, String label, String key) {
    final c = hexToColor('${_cur[key] ?? ''}');
    return ListTile(
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c ?? theme.colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
      ),
      title: Text(label),
      trailing: const Icon(Icons.palette),
      onTap: () => _pickColour(key, label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _current;
    // The default is a plain shirt in the team's colours, so it reads as Plain.
    final pattern = current == null ? 'plain' : (_isSpec(current) ? '${current['pattern']}' : null);
    final image = current is Map ? current['image'] as String? : null;
    final template = current is Map ? current['template'] : null;
    return Scaffold(
      appBar: AppBar(title: Text('${team.name} kits')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // The choice as the game shows it, beside the side toggle.
          Row(
            children: [
              Container(
                width: 96,
                height: 128,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: kitPreview(_currentPng[_side], loading: _loadingCurrent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Home')),
                        ButtonSegment(value: false, label: Text('Away')),
                      ],
                      selected: {_home},
                      onSelectionChanged: (s) {
                        setState(() => _home = s.first);
                        if (_currentPng[_side] == null) _refreshCurrent();
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(kitLabel(current), style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          _heading(theme, 'Pattern'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (n, p) in kitPatterns.indexed)
                _tile(
                  theme,
                  label: kitLabel({'pattern': p}),
                  selected: pattern == p,
                  autofocus: n == 0,
                  image: _previews['${_side}_$p'],
                  onTap: () {
                    _cur['pattern'] = p;
                    _choose(Map<String, dynamic>.from(_cur));
                  },
                ),
            ],
          ),
          if (widget.info.kitTemplates && widget.templates.isEmpty && widget.romPath == null) ...[
            _heading(theme, 'Game designs'),
            Text(
              'Pick the ROM first to see the game\'s own designs.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (widget.templates.isNotEmpty) ...[
            _heading(theme, 'Game designs'),
            if (_groups.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final (n, g) in _groups.indexed)
                      ChoiceChip(
                        label: Text('${g.name} (${widget.templates.where((t) => t.index >= g.first && t.index <= g.last).length})'),
                        selected: n == _group,
                        onSelected: (_) => setState(() {
                          _group = n;
                          _page = 0;
                        }),
                      ),
                  ],
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _inGroup.skip(_page * designsPerPage).take(designsPerPage))
                  Tooltip(
                    message: t.name,
                    child: _tile(
                      theme,
                      label: designLabel(t),
                      selected: template == t.index,
                      image: t.path,
                      onTap: () => _choose({'template': t.index}),
                    ),
                  ),
              ],
            ),
            if (_pages > 1)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous designs',
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('${_page + 1} / $_pages', style: theme.textTheme.labelMedium),
                  IconButton(
                    tooltip: 'More designs',
                    onPressed: _page < _pages - 1 ? () => setState(() => _page++) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
          ],
          _heading(theme, 'Your PNG'),
          Align(
            alignment: Alignment.centerLeft,
            child: _tile(
              theme,
              label: image == null ? 'Choose…' : 'Custom PNG',
              selected: image != null,
              image: image,
              icon: Icons.upload_file,
              onTap: _pickPng,
            ),
          ),
          // The slot's kit template pack, to draw the PNG on: a quiet link,
          // like the screen templates' on the Look step.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, textStyle: theme.textTheme.labelSmall),
              onPressed: widget.romPath == null || widget.slot == null || _downloading ? null : _downloadTemplate,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download kit template'),
            ),
          ),
          if (widget.info.gameId == 'pes2013-ps2')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'PES uses the picture for its colours and pattern only.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          _heading(theme, 'Colours'),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _colourRow(theme, 'Shirt', 'shirt'),
                const Divider(height: 1),
                _colourRow(theme, 'Secondary', 'secondary'),
                const Divider(height: 1),
                _colourRow(theme, 'Shorts', 'shorts'),
                const Divider(height: 1),
                _colourRow(theme, 'Socks', 'socks'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: current == null ? null : () => _choose(null),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Back to default'),
            ),
          ),
        ],
      ),
    );
  }
}
