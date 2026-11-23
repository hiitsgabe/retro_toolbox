import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// The app to add as an emulator: every app with a launcher entry but this
/// one and the ones already detected, by label, with a search as Save Sync's
/// picker has. A or a tap picks one and pops with it; Back pops null.
class LauncherAppPickerScreen extends ConsumerStatefulWidget {
  const LauncherAppPickerScreen({super.key, this.exclude = const {}});

  /// Packages already detected: added again, one emulator would show twice.
  final Set<String> exclude;

  @override
  ConsumerState<LauncherAppPickerScreen> createState() => _LauncherAppPickerScreenState();
}

class _LauncherAppPickerScreenState extends ConsumerState<LauncherAppPickerScreen> {
  List<({String package, AppInfo info})>? _apps;
  final _search = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final apps = await ref.read(installedAppsProvider).launchable();
      if (mounted) setState(() => _apps = [for (final a in apps) if (!widget.exclude.contains(a.package)) a]);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final apps = _apps;
    final shown = [
      for (final a in apps ?? const <({String package, AppInfo info})>[])
        if (_filter.isEmpty || a.info.label.toLowerCase().contains(_filter) || a.package.contains(_filter)) a,
    ];
    final Widget list;
    if (apps == null) {
      list = const Center(child: CircularProgressIndicator());
    } else if (shown.isEmpty) {
      list = EmptyState(icon: Icons.search_off, line: apps.isEmpty ? 'No other app on this device' : 'Nothing matches.');
    } else {
      list = ListView(children: [
        OptionList(children: [
          for (final (i, a) in shown.indexed)
            KitRow(
              key: ValueKey('launcher-app-${a.package}'),
              autofocus: i == 0,
              onTap: () => Navigator.of(context).pop(a),
              child: Row(children: [
                if (a.info.icon != null)
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(a.info.icon!, width: 32, height: 32, gaplessPlayback: true))
                else
                  Icon(Icons.android, size: 28, color: t.muted),
                const SizedBox(width: 12),
                Expanded(child: KitRowText(title: a.info.label, subtitle: a.package)),
              ]),
            ),
        ]),
      ]);
    }
    return KitScaffold(
      title: 'Add an emulator',
      subtitle: 'Pick the app that runs your games',
      icon: Icons.sports_esports,
      glyph: PixelIcons.games,
      area: AppArea.games,
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
        const SizedBox(height: kitGap),
        Expanded(child: list),
      ]),
      actionBar: const ActionBar(hints: [KitHint(PadButton.a, 'Pick'), KitHint(PadButton.b, 'Back')]),
    );
  }
}
