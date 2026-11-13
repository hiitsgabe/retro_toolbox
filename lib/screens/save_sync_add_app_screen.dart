import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/screens/save_sync_recipe_wizard_screen.dart';
import 'package:retro_toolbox/services/save_sync/recipe_index.dart';

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

  /// Package to the recipe this app already knows for it — what the build
  /// ships, what a hub published, what was written here. Consulted before the
  /// catalog, because a recipe already in hand beats one that has to be
  /// fetched.
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
  final _picked = <String>{};
  String _filter = '';
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final apps = await ref.read(saveSyncProvider.notifier).launchableApps();
      if (mounted) setState(() => _apps = apps);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apps = _apps;
    final catalog = widget.catalog;
    final shown = apps == null
        ? const <({String package, AppInfo info})>[]
        : [
            for (final a in apps)
              if (_filter.isEmpty || a.info.label.toLowerCase().contains(_filter) || a.package.contains(_filter)) a,
          ];

    return Scaffold(
      appBar: AppBar(title: const Text('Add an app')),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search installed apps'),
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          if (catalog != null && catalog.fetchedAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  catalog.fromCache
                      ? 'Catalog unreachable — showing what was cached'
                      : 'Catalog updated ${_ago(catalog.fetchedAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          if (apps == null) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (apps != null)
            Expanded(
              child: shown.isEmpty
                  ? Center(child: Text('Nothing matches.', style: theme.textTheme.bodyMedium))
                  : ListView.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final a = shown[i];
                        final added = widget.already.contains(a.package);
                        final mine = widget.known[a.package];
                        final hit = catalog?.byPackage[a.package];
                        return CheckboxListTile(
                          value: added || _picked.contains(a.package),
                          onChanged: added || _adding
                              ? null
                              : (on) => setState(() => on == true ? _picked.add(a.package) : _picked.remove(a.package)),
                          secondary: GestureDetector(
                            // An app with nothing published is a thing to
                            // describe, not a thing to hide: the way in is on
                            // its own row.
                            onLongPress: added ? null : () => _describe(a),
                            child: a.info.icon != null
                                ? Image.memory(a.info.icon!, width: 40, height: 40, gaplessPlayback: true)
                                : const Icon(Icons.videogame_asset, size: 40),
                          ),
                          title: Text(a.info.label),
                          // Not an error and not a dead end: an app with no
                          // recipe is one to write a recipe for.
                          subtitle: Text(
                            added
                                ? 'Already added'
                                : mine != null
                                    ? 'Recipe ready'
                                    : hit != null
                                        ? 'Recipe available${hit.status == 'verified' ? ' · verified' : ''}'
                                        : 'No recipe yet — hold its icon to describe it here',
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _picked.isEmpty || _adding ? null : _add,
                  child: Text(_picked.isEmpty ? 'Add' : 'Add ${_picked.length}'),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
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
    setState(() => _adding = true);
    final catalog = widget.catalog;
    // The recipe a catalog names is recorded with the choice; an app with
    // none is recorded all the same, so the intent reaches the other devices
    // and a recipe can land later.
    final chosen = {for (final p in _picked) p: widget.known[p] ?? catalog?.byPackage[p]?.id};
    await ref.read(saveSyncProvider.notifier).addApps(chosen);
    if (mounted) Navigator.of(context).pop(true);
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
