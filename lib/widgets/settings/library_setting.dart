import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/widgets/about/play_fair_card.dart';

/// Opt-in switch for the Games Library and downloads. Turning it on shows the
/// Play fair note for the user to accept; turning it off doesn't.
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
          content: const PlayFairCard(),
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
