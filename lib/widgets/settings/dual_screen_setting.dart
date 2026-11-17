import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/dual_screen_provider.dart';
import 'package:retro_toolbox/services/dual_screen/dual_screen_plan.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';

/// The card shows only on Android with a second display that is on.
bool showDualScreenCard({required bool isAndroid, required bool hasSecondDisplay}) => isAndroid && hasSecondDisplay;

/// Picks which screen the main app takes; the other one shows the companion.
class DualScreenSetting extends ConsumerWidget {
  const DualScreenSetting({super.key});

  static const _about = {
    DualScreenMode.off: 'One screen only',
    DualScreenMode.mainOnTop: 'Games list on top, details or tasks below',
    DualScreenMode.mainOnBottom: 'The app moves to the bottom screen; details or tasks on top',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(dualScreenProvider);
    final notifier = ref.read(dualScreenProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SettingsSegmentedRow<DualScreenMode>(
        title: 'Layout',
        subtitle: _about[s.mode],
        options: const [
          (DualScreenMode.off, 'Off'),
          (DualScreenMode.mainOnTop, 'Main on top'),
          (DualScreenMode.mainOnBottom, 'Main on bottom'),
        ],
        selected: s.mode,
        onChanged: notifier.setMode,
      ),
      const SettingsInfo('Changing which screen is the main one restarts the app on that screen.'),
      if (s.error != null) SettingsInfo(s.error!, error: true),
    ]);
  }
}
