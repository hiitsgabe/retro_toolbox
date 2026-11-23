import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// The consoles an emulator added with "Just open the file" opens: one row
/// per console art slug of the catalog, since presets are keyed by slug,
/// named after its first console, the ones with games on disk first. Add
/// pops with the ticked slugs in the order shown; Back pops null.
class LauncherConsolePickerScreen extends ConsumerStatefulWidget {
  const LauncherConsolePickerScreen({super.key, required this.label});

  /// The emulator's name, for the subtitle.
  final String label;

  @override
  ConsumerState<LauncherConsolePickerScreen> createState() => _LauncherConsolePickerScreenState();
}

class _LauncherConsolePickerScreenState extends ConsumerState<LauncherConsolePickerScreen> {
  var _ticked = <String>{};

  @override
  Widget build(BuildContext context) {
    final names = <String, String>{};
    final withGames = <String>{};
    for (final c in ref.watch(appStateProvider.select((s) => s.consolesList))) {
      final slug = ref.watch(gameSystemProvider(c.id)).slug;
      if (slug == null) continue;
      names.putIfAbsent(slug, () => c.name);
      if (ref.watch(gamesOnDiskProvider(c.id)).valueOrNull == true) withGames.add(slug);
    }
    final first = [for (final s in names.keys) if (withGames.contains(s)) s];
    final rest = [for (final s in names.keys) if (!withGames.contains(s)) s];
    final shown = [...first, ...rest];
    ResultRow row(String slug) => ResultRow(id: slug, title: names[slug]!);
    final n = _ticked.length;
    return KitScaffold(
      title: 'Consoles',
      subtitle: 'Tick the ones ${widget.label} opens',
      icon: Icons.sports_esports,
      glyph: PixelIcons.games,
      area: AppArea.games,
      body: ResultsList(
        groups: [
          ResultGroup('With games on disk', [for (final s in first) row(s)]),
          ResultGroup('Other consoles', [for (final s in rest) row(s)]),
        ],
        selected: _ticked,
        onSelectionChanged: (s) => setState(() => _ticked = s),
        empty: const EmptyState(icon: Icons.search_off, line: 'No console in the catalog yet'),
      ),
      actionBar: ActionBar(
        primary: KitAction('Add', n == 0 ? null : () => Navigator.of(context).pop([for (final s in shown) if (_ticked.contains(s)) s]), icon: Icons.add),
        hints: const [KitHint(PadButton.a, 'Tick'), KitHint(PadButton.b, 'Back')],
        summary: n == 0 ? 'Tick at least one' : '$n ticked',
      ),
    );
  }
}
