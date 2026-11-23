import 'package:flutter/material.dart';
import 'package:retro_toolbox/services/launcher/detected_emulator.dart';
import 'package:retro_toolbox/services/launcher/launcher_session.dart';

/// "Open with…": one entry per detected emulator that covers the game's
/// system, each with "Just this once" and "Always for this game". Pops with
/// the emulator and whether the choice is to be kept, or null on Back.
Future<({DetectedEmulator emulator, bool always})?> showLaunchPicker(BuildContext context, LauncherSession session, List<DetectedEmulator> emulators) {
  return showDialog<({DetectedEmulator emulator, bool always})>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        title: const Text('Open with…'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (i, e) in emulators.indexed)
                Padding(
                  key: ValueKey('launch-picker-${e.presetId}'),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (e.icon != null) Image.memory(e.icon!, width: 32, height: 32) else const Icon(Icons.videogame_asset_outlined, size: 32),
                        const SizedBox(width: 12),
                        Flexible(child: Text(e.label, style: theme.textTheme.titleSmall, overflow: TextOverflow.ellipsis)),
                        if (!(session.preset(e.presetId)?.verified ?? false)) ...[
                          const SizedBox(width: 8),
                          Text('not tested', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.tertiary)),
                        ],
                      ]),
                      Wrap(spacing: 8, children: [
                        TextButton(
                          autofocus: i == 0,
                          onPressed: () => Navigator.pop(context, (emulator: e, always: false)),
                          child: const Text('Just this once'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, (emulator: e, always: true)),
                          child: const Text('Always for this game'),
                        ),
                      ]),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
