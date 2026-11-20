import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_recipe_wizard_screen.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// Picking which apps this set of handhelds keeps in step.
///
/// Every installed app with a launcher entry is listed, whether a recipe for
/// it exists or not: an app with nothing published is a thing to write a
/// recipe for, not a thing to hide.
class SaveSyncAddAppScreen extends ConsumerStatefulWidget {
  const SaveSyncAddAppScreen({super.key, required this.already, this.catalog, this.known = const {}});

  /// Packages the hub already covers, shown as added rather than offered
  /// again.
  final Set<String> already;

  /// Package to the recipe this app already knows for it: what a hub
  /// published, what was written here, what the catalog already brought.
  /// Consulted before the catalog, because a recipe already in hand beats one
  /// that has to be fetched.
  final Map<String, String> known;

  /// The published catalog, when one could be read. Null means it was never
  /// reachable and nothing is cached, which changes what the rows offer but
  /// never whether the screen works.
  final RecipeCatalog? catalog;

  @override
  ConsumerState<SaveSyncAddAppScreen> createState() => _SaveSyncAddAppScreenState();
}

class _SaveSyncAddAppScreenState extends ConsumerState<SaveSyncAddAppScreen> {
  List<({String package, AppInfo info})>? _apps;
  var _picked = <String>{};
  final _search = TextEditingController();
  String _filter = '';
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final apps = await ref.read(saveSyncProvider.notifier).launchableApps();
      if (mounted) setState(() => _apps = apps);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = ref.watch(inputModeProvider) == InputMode.gamepad;
    final apps = _apps;
    final catalog = widget.catalog;
    final shown = apps == null
        ? const <({String package, AppInfo info})>[]
        : [
            for (final a in apps)
              if (_filter.isEmpty || a.info.label.toLowerCase().contains(_filter) || a.package.contains(_filter)) a,
          ];
    final rows = [
      for (final a in shown)
        ResultRow(
          id: a.package,
          title: a.info.label,
          subtitle: _line(a.package, pad: pad),
          selectable: !widget.already.contains(a.package) && !_adding,
          leading: a.info.icon != null
              ? ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(a.info.icon!, width: 32, height: 32, gaplessPlayback: true))
              : Icon(Icons.videogame_asset_outlined, size: 28, color: KitType.of(context).muted),
          // An app with nothing published is a thing to describe, not a thing
          // to hide: the way in is on its own row, Y or a long press.
          onMenu: widget.already.contains(a.package) || _adding ? null : () => _describe(a),
        ),
    ];
    final n = _picked.length;
    return KitScaffold(
      title: 'Add an app',
      subtitle: catalog != null && catalog.fetchedAt != null
          ? (catalog.fromCache ? 'Catalog unreachable: showing what was cached' : 'Catalog updated ${_ago(catalog.fetchedAt!)}')
          : 'Pick the games whose saves should travel',
      icon: Icons.sync,
      glyph: PixelIcons.saves,
      area: AppArea.saves,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        KitPanel(children: [
          FieldSlot(
            label: 'Search',
            hint: 'Search installed apps',
            controller: _search,
            icon: Icons.search,
            onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
          ),
        ]),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: kitGap), child: StatusPanel.error(line: _error!)),
        const SizedBox(height: kitGap),
        Expanded(
          child: apps == null
              ? const Center(child: CircularProgressIndicator())
              : ResultsList(
                  groups: [ResultGroup('Installed apps', rows)],
                  selected: {..._picked, ...widget.already},
                  onSelectionChanged: _adding ? null : (s) => setState(() => _picked = s.difference(widget.already)),
                  empty: const EmptyState(icon: Icons.search_off, line: 'Nothing matches.'),
                ),
        ),
      ]),
      actionBar: ActionBar(
        primary: KitAction(n == 0 ? 'Add' : 'Add $n', n == 0 || _adding ? null : _add, icon: Icons.add),
        hints: const [KitHint(PadButton.a, 'Mark'), KitHint(PadButton.y, 'Describe'), KitHint(PadButton.b, 'Back')],
        summary: n == 0 ? null : '$n marked',
      ),
    );
  }

  /// What the row can count on. Not an error and not a dead end: an app with
  /// no recipe is one to write a recipe for.
  String _line(String package, {required bool pad}) {
    if (widget.already.contains(package)) return 'Already added';
    if (widget.known[package] != null) return 'Recipe ready';
    final hit = widget.catalog?.byPackage[package];
    if (hit != null) return 'Recipe available${hit.status == 'verified' ? ' · verified' : ''}';
    return pad ? 'No recipe yet: press Y to describe it here' : 'No recipe yet: hold it to describe it here';
  }

  /// Opens the authoring flow for one app and brings its recipe straight into
  /// the set, so describing an app and adding it are one errand.
  Future<void> _describe(({String package, AppInfo info}) a) async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => SaveSyncRecipeWizardScreen(package: a.package, label: a.info.label),
    ));
    if (added == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _add() async {
    setState(() {
      _adding = true;
      _error = null;
    });
    final catalog = widget.catalog;
    // The recipe a catalog names is recorded with the choice; an app with
    // none is recorded all the same, so the intent reaches the other devices
    // and a recipe can land later.
    final chosen = {for (final p in _picked) p: widget.known[p] ?? catalog?.byPackage[p]?.id};
    final error = await ref.read(saveSyncProvider.notifier).addApps(chosen);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _adding = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
