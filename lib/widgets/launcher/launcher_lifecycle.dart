import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';

/// Launcher mode's part in the app's life. At start, with the mode on, the
/// background preset download, so the next session has the new presets
/// without a details page opening first. On each resume with the mode on, a
/// new detection: the user may have installed or removed an emulator while
/// away, and a resume is how they come back from one.
class LauncherLifecycle extends ConsumerStatefulWidget {
  const LauncherLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LauncherLifecycle> createState() => _LauncherLifecycleState();
}

class _LauncherLifecycleState extends ConsumerState<LauncherLifecycle> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _resumed);
    ref.read(launchConfigProvider.notifier).loaded.then((_) {
      if (mounted && ref.read(launchConfigProvider).enabled) ref.read(presetRefreshProvider);
    });
  }

  void _resumed() {
    if (ref.read(launchConfigProvider).enabled) ref.read(detectEmulatorsProvider)();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
