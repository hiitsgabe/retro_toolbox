import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';
import 'package:retro_toolbox/services/installed_apps.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// Retro Toolbox as the home app: every other app with an icon, by name, as
/// a launcher's app drawer has them. Choosing one opens it.
class AppDrawerScreen extends ConsumerStatefulWidget {
  const AppDrawerScreen({super.key});

  @override
  ConsumerState<AppDrawerScreen> createState() => _AppDrawerScreenState();
}

class _AppDrawerScreenState extends ConsumerState<AppDrawerScreen> {
  late final Future<List<({String package, AppInfo info})>> _apps = ref.read(installedAppsProvider).launchable();

  @override
  Widget build(BuildContext context) {
    return KitScaffold(
      title: 'Apps',
      icon: Icons.apps,
      glyph: PixelIcons.tools,
      area: AppArea.games,
      body: FutureBuilder<List<({String package, AppInfo info})>>(
        future: _apps,
        builder: (context, snap) {
          final apps = snap.data;
          if (apps == null) return const Center(child: CircularProgressIndicator());
          if (apps.isEmpty) return const EmptyState(icon: Icons.apps, line: 'No other app to open');
          return GridView.extent(
            maxCrossAxisExtent: 112,
            padding: const EdgeInsets.all(12),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final (i, app) in apps.indexed)
                _AppTile(app: app, autofocus: i == 0, onOpen: () => ref.read(launcherChannelProvider).openApp(app.package)),
            ],
          );
        },
      ),
    );
  }
}

class _AppTile extends StatelessWidget {
  const _AppTile({required this.app, required this.autofocus, required this.onOpen});

  final ({String package, AppInfo info}) app;
  final bool autofocus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final icon = app.info.icon;
    return InkWell(
      key: ValueKey('app ${app.package}'),
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(12),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) Image.memory(icon, width: 48, height: 48, gaplessPlayback: true) else Icon(Icons.android, size: 48, color: t.muted),
          const SizedBox(height: 6),
          Text(app.info.label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: t.subtitle),
        ]),
      ),
    );
  }
}
