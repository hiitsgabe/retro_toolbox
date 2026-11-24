import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/screens/app_drawer_screen.dart';
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/services/launcher/launch_config.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// One of launcher mode's Android shelves on the console list: the apps the
/// user put in it, by their order there. Choosing one opens it; Choose apps
/// changes what is in it.
class AndroidCollectionScreen extends ConsumerStatefulWidget {
  const AndroidCollectionScreen({super.key, required this.kind});

  final AndroidCollection kind;

  @override
  ConsumerState<AndroidCollectionScreen> createState() => _AndroidCollectionScreenState();
}

class _AndroidCollectionScreenState extends ConsumerState<AndroidCollectionScreen> {
  Future<Map<String, AppInfo>>? _info;
  List<String>? _asked;

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(launchConfigProvider.select((c) => c.collection(widget.kind)));
    // Icons and labels for what is in it now; an uninstalled app has none
    // and is left out until it is back.
    if (_asked != packages) {
      _asked = packages;
      _info = ref.read(installedAppsProvider).info(packages);
    }
    final choose = KitAction('Choose apps', () => chooseCollectionApps(context, ref, widget.kind), icon: Icons.checklist);
    return KitScaffold(
      title: widget.kind.label,
      subtitle: widget.kind == AndroidCollection.games ? 'Android games' : 'Android apps',
      icon: widget.kind == AndroidCollection.games ? Icons.sports_esports : Icons.apps,
      glyph: widget.kind == AndroidCollection.games ? PixelIcons.games : PixelIcons.tools,
      area: AppArea.games,
      body: FutureBuilder<Map<String, AppInfo>>(
        future: _info,
        builder: (context, snap) {
          final info = snap.data;
          if (info == null) return const Center(child: CircularProgressIndicator());
          final shown = [for (final p in packages) if (info[p] != null) (package: p, info: info[p]!)];
          if (shown.isEmpty) {
            return EmptyState(icon: Icons.android, line: 'Nothing here yet. Choose the apps it shows.', action: choose);
          }
          return GridView.extent(
            maxCrossAxisExtent: 112,
            padding: const EdgeInsets.all(12),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final (i, app) in shown.indexed)
                AppTile(app: app, autofocus: i == 0, onOpen: () => ref.read(launcherChannelProvider).openApp(app.package)),
            ],
          );
        },
      ),
      actionBar: ActionBar(secondary: choose, hints: const [KitHint(PadButton.a, 'Open'), KitHint(PadButton.b, 'Back')]),
    );
  }
}

/// Picks what [kind] shows from the launchable apps, the ones in it ticked,
/// and saves the ticked ones in the order shown.
Future<void> chooseCollectionApps(BuildContext context, WidgetRef ref, AndroidCollection kind) async {
  final picked = await Navigator.of(context).push<List<String>>(
    MaterialPageRoute(builder: (_) => AndroidCollectionPickerScreen(kind: kind, initial: ref.read(launchConfigProvider).collection(kind))),
  );
  if (picked != null) await ref.read(launchConfigProvider.notifier).setCollection(kind, picked);
}

/// The launchable apps, by label, the ones already in [kind] first and
/// ticked. Save pops the ticked packages, the ones already in it in their
/// order, then the new ones by label; Back pops null.
class AndroidCollectionPickerScreen extends ConsumerStatefulWidget {
  const AndroidCollectionPickerScreen({super.key, required this.kind, required this.initial});

  final AndroidCollection kind;
  final List<String> initial;

  @override
  ConsumerState<AndroidCollectionPickerScreen> createState() => _AndroidCollectionPickerScreenState();
}

class _AndroidCollectionPickerScreenState extends ConsumerState<AndroidCollectionPickerScreen> {
  late final Future<List<({String package, AppInfo info})>> _apps = ref.read(installedAppsProvider).launchable();
  late Set<String> _ticked = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<({String package, AppInfo info})>>(
      future: _apps,
      builder: (context, snap) {
        final apps = snap.data ?? const [];
        final byPackage = {for (final a in apps) a.package: a};
        final inIt = [for (final p in widget.initial) if (byPackage[p] != null) byPackage[p]!];
        final rest = [for (final a in apps) if (!widget.initial.contains(a.package)) a];
        ResultRow row(({String package, AppInfo info}) a) => ResultRow(
              id: a.package,
              title: a.info.label,
              subtitle: a.package,
              leading: a.info.icon == null ? const Icon(Icons.android, size: 32) : Image.memory(a.info.icon!, width: 32, height: 32, gaplessPlayback: true),
            );
        final order = [...inIt, ...rest];
        return KitScaffold(
          title: 'Choose apps',
          subtitle: 'What ${widget.kind.label} shows',
          icon: Icons.checklist,
          glyph: PixelIcons.tools,
          area: AppArea.games,
          body: snap.data == null
              ? const Center(child: CircularProgressIndicator())
              : ResultsList(
                  groups: [
                    ResultGroup('In ${widget.kind.label}', [for (final a in inIt) row(a)]),
                    ResultGroup('Other apps', [for (final a in rest) row(a)]),
                  ],
                  selected: _ticked,
                  onSelectionChanged: (s) => setState(() => _ticked = s),
                  empty: const EmptyState(icon: Icons.apps, line: 'No other app to show'),
                ),
          actionBar: ActionBar(
            primary: KitAction('Save', () => Navigator.of(context).pop([for (final a in order) if (_ticked.contains(a.package)) a.package]), icon: Icons.check),
            hints: const [KitHint(PadButton.a, 'Tick'), KitHint(PadButton.b, 'Back')],
            summary: '${_ticked.length} ticked',
          ),
        );
      },
    );
  }
}
