import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/providers/launcher_provider.dart';

/// Launcher mode's part in the app's life. At start, with the mode on, the
/// background preset download, so the next session has the new presets
/// without a details page opening first. On each resume with the mode on, a
/// new detection: the user may have installed or removed an emulator while
/// away, and a resume is how they come back from one. On that resume, and
/// when the mode turns on, the library is read again: files may have come or
/// gone meanwhile, and the mode lists what is on disk.
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
      if (!mounted) return;
      if (ref.read(launchConfigProvider).enabled) ref.read(presetRefreshProvider);
      // Only after the load: the saved config coming in is not the mode
      // turning on.
      ref.listenManual(launchConfigProvider.select((c) => c.enabled), (was, on) {
        if (on && was == false) _rescan();
      });
    });
  }

  void _resumed() {
    if (!ref.read(launchConfigProvider).enabled) return;
    ref.read(detectEmulatorsProvider)();
    _rescan();
  }

  void _rescan() {
    ref.read(catalogProvider.notifier).rescanLibrary();
    ref.invalidate(gamesOnDiskProvider);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
