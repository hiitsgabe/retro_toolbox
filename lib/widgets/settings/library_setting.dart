import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';

/// Opt-in switch for the Games Library and downloads. Turning it on asks the
/// user to confirm they only download games they own; turning it off doesn't.
class LibrarySetting extends ConsumerWidget {
  const LibrarySetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Games Library & downloads'),
      subtitle: const Text('Browse a catalog and download games to this device.'),
      value: ref.watch(settingsProvider.select((s) => s.isLibraryEnabled)),
      onChanged: (v) async {
        if (v && await _confirm(context) != true) return;
        await ref.read(settingsProvider.notifier).setLibraryEnabled(v);
      },
    );
  }

  Future<bool?> _confirm(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable Games Library'),
          content: const Text('Only download games you legally own, from your own sources.'),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I understand, enable'),
            ),
          ],
        ),
      );
}
