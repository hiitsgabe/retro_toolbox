import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';

/// The card shows only on Android with a second display that is on.
bool showDualScreenCard({required bool isAndroid, required bool hasSecondDisplay}) => isAndroid && hasSecondDisplay;

/// [showDualScreenCard] for this device, as a provider tests can set.
final dualScreenCardProvider = Provider<bool>(
  (ref) => showDualScreenCard(isAndroid: Platform.isAndroid, hasSecondDisplay: ref.watch(dualScreenProvider.select((s) => s.hasSecondDisplay))),
);

/// Picks which screen the main app takes; the other one shows the companion.
class DualScreenSetting extends ConsumerWidget {
  const DualScreenSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(dualScreenProvider);
    final notifier = ref.read(dualScreenProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SettingsSegmentedRow<DualScreenMode>(
        title: 'Layout',
        subtitle: 'Only shown when a second display is found',
        options: const [
          (DualScreenMode.off, 'Off'),
          (DualScreenMode.mainOnTop, 'Main on top'),
          (DualScreenMode.mainOnBottom, 'Main on bottom'),
        ],
        selected: s.mode,
        onChanged: notifier.setMode,
      ),
      const SettingsInfo(
        'The other screen shows the focused game on a game list, and the Task Manager everywhere else. '
        'Changing which screen is the main one restarts the app there.',
      ),
      if (s.error != null) SettingsInfo(s.error!, error: true),
    ]);
  }
}
