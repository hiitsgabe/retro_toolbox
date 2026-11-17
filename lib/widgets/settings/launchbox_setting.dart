import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';

/// Turns LaunchBox metadata on (an import in the Task Manager), updates it
/// and turns it off (deletes it). Never updates by itself: each one is a
/// 110 MB download.
class LaunchboxSetting extends ConsumerStatefulWidget {
  const LaunchboxSetting({super.key});

  @override
  ConsumerState<LaunchboxSetting> createState() => _LaunchboxSettingState();
}

class _LaunchboxSettingState extends ConsumerState<LaunchboxSetting> {
  @override
  void initState() {
    super.initState();
    // Consoles can change between visits, and with them what is missing.
    ref.read(launchboxProvider.notifier).refresh();
  }

  Future<bool> _confirm(String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _turnOn() async {
    if (!await _confirm("Download about 110 MB from LaunchBox's games database and index it on this device?", 'Download')) return;
    if (mounted) ref.read(launchboxProvider.notifier).startImport(ref, context);
  }

  Future<void> _turnOff() async {
    if (!await _confirm('Delete the downloaded metadata?', 'Delete')) return;
    await ref.read(launchboxProvider.notifier).turnOff();
  }

  static String _date(DateTime t) {
    final l = t.toLocal();
    String two(int n) => '$n'.padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(launchboxProvider);
    if (s.loading) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final theme = Theme.of(context);
    final manifest = s.manifest;
    final count = manifest?.platforms.length ?? 0;
    final missing = s.missing.toList()..sort();
    // Off with nothing to import: turning it on would keep no platform.
    final nothingToImport = manifest == null && s.wanted.isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Use LaunchBox metadata'),
        subtitle: Text(manifest == null
            ? "Adds ratings, genres, descriptions and artwork from LaunchBox's games database. Downloads about 110 MB once and indexes it on this device."
            : 'Updated ${_date(manifest.importedAt)} · $count platform${count == 1 ? '' : 's'}'),
        value: manifest != null,
        // Deleting under a running import would only have it write the files back.
        onChanged: s.importing || nothingToImport ? null : (on) => on ? _turnOn() : _turnOff(),
      ),
      if (nothingToImport && !s.importing && s.message != noLaunchboxConsolesMessage) const Text(noLaunchboxConsolesMessage),
      if (missing.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('New consoles need an update: ${missing.join(', ')}', style: TextStyle(color: theme.colorScheme.error)),
        ),
      if (s.importing)
        Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Importing, see the Task Manager'),
          TextButton(
            onPressed: () => ref.read(launchboxProvider.notifier).cancelImport(),
            child: const Text('Cancel'),
          ),
        ])
      else if (manifest != null)
        FilledButton(
          onPressed: () => ref.read(launchboxProvider.notifier).startImport(ref, context),
          child: const Text('Update'),
        ),
      if (s.message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(s.message!, style: theme.textTheme.bodySmall),
        ),
      if (manifest != null)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Use LaunchBox covers for thumbnails'),
          subtitle: const Text("Instead of the catalog's box art, when LaunchBox has one"),
          value: s.useCovers,
          onChanged: (on) => ref.read(launchboxProvider.notifier).setUseCovers(on),
        ),
    ]);
  }
}
