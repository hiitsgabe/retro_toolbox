import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/launchbox_provider.dart';
import 'package:retro_toolbox/services/storage_usage.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/switch_row.dart';

/// Asks, then deletes the downloaded metadata (turning it off). Shared by the
/// LaunchBox switch and Storage's Remove.
Future<void> confirmLaunchboxTurnOff(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: const Text('Delete the downloaded metadata?'),
      actions: [
        TextButton(autofocus: true, onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok == true) {
    await ref.read(launchboxProvider.notifier).turnOff();
    ref.invalidate(storageUsageProvider);
  }
}

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

  Future<void> _turnOff() => confirmLaunchboxTurnOff(context, ref);

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "Nov 16".
  static String _date(DateTime t) {
    final l = t.toLocal();
    return '${_months[l.month - 1]} ${l.day}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(launchboxProvider);
    if (s.loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    final manifest = s.manifest;
    final missing = s.missing.toList()..sort();
    // Off with nothing to import: turning it on would keep no platform.
    final nothingToImport = manifest == null && s.wanted.isEmpty;
    final size = manifest == null ? null : ref.watch(storageUsageProvider).valueOrNull?.launchbox;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SettingsSwitchRow(
        title: 'Use LaunchBox metadata',
        subtitle: manifest == null
            ? 'Ratings, genres and artwork. Downloads about 110 MB once'
            : 'Ratings, genres and artwork. ${size != null && size > 0 ? '${storageSize(size)}, updated' : 'Updated'} ${_date(manifest.importedAt)}',
        value: manifest != null,
        // Deleting under a running import would only have it write the files back.
        onChanged: s.importing || nothingToImport ? null : (on) => on ? _turnOn() : _turnOff(),
      ),
      if (nothingToImport && !s.importing && s.message != noLaunchboxConsolesMessage) const SettingsInfo(noLaunchboxConsolesMessage),
      if (missing.isNotEmpty) SettingsInfo('New consoles need an update: ${missing.join(', ')}', error: true),
      if (manifest != null)
        SettingsSwitchRow(
          title: 'LaunchBox covers as thumbnails',
          subtitle: 'Instead of the catalog box art, when LaunchBox has one',
          indent: true,
          value: s.useCovers,
          onChanged: (on) => ref.read(launchboxProvider.notifier).setUseCovers(on),
        ),
      if (s.importing)
        SettingsActionRow(
          title: 'Importing, see the Task Manager',
          subtitle: 'Downloads only when LaunchBox changed',
          action: 'Cancel',
          indent: true,
          onPressed: () => ref.read(launchboxProvider.notifier).cancelImport(),
        )
      else if (manifest != null)
        SettingsActionRow(
          title: 'Check for a newer database',
          subtitle: 'Downloads only when LaunchBox changed',
          action: 'Update',
          indent: true,
          onPressed: () => ref.read(launchboxProvider.notifier).startImport(ref, context),
        ),
      if (s.message != null) SettingsInfo(s.message!, indent: true),
    ]);
  }
}
