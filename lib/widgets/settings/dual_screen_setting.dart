import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';

/// The card shows only on Android with a second display that is on.
bool showDualScreenCard({required bool isAndroid, required bool hasSecondDisplay}) => isAndroid && hasSecondDisplay;

/// Picks which screen the main app takes; the other one shows the companion.
class DualScreenSetting extends ConsumerWidget {
  const DualScreenSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(dualScreenProvider);
    final notifier = ref.read(dualScreenProvider.notifier);
    final theme = Theme.of(context);

    Widget choice(DualScreenMode mode, String title, [String? subtitle]) => RadioListTile<DualScreenMode>(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle, style: theme.textTheme.bodySmall),
          value: mode,
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RadioGroup<DualScreenMode>(
        groupValue: s.mode,
        onChanged: (v) {
          if (v != null) notifier.setMode(v);
        },
        child: Column(children: [
          choice(DualScreenMode.off, 'Off'),
          choice(DualScreenMode.mainOnTop, 'Main on top', 'Games list on top, details or tasks below'),
          choice(DualScreenMode.mainOnBottom, 'Main on bottom', 'The app moves to the bottom screen; details or tasks on top'),
        ]),
      ),
      const SizedBox(height: 4),
      Text('Changing which screen is the main one restarts the app on that screen.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      if (s.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(s.error!, style: TextStyle(color: theme.colorScheme.error)),
        ),
    ]);
  }
}
