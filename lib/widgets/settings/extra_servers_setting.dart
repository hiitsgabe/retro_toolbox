import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';

/// Settings → Extra servers: one accordion with an on/off switch per console
/// install server. A server only shows its Servers-menu tile while enabled,
/// and turning one off stops it if it is running.
class ExtraServersSetting extends ConsumerWidget {
  const ExtraServersSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      shape: const Border(),
      title: const Text('Server consoles'),
      subtitle: const Text('Show and enable per-console install servers.'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        _switch(
          ref,
          id: 'tinfoil',
          title: 'Tinfoil Server (Switch)',
          subtitle: 'Browse and install the Switch library from the console.',
          enabled: ref.watch(settingsProvider.select((s) => s.isTinfoilEnabled)),
          stop: () async => ref.read(tinfoilServerProvider.notifier).disable(),
        ),
        _switch(
          ref,
          id: 'fbi',
          title: 'FBI Server (Nintendo 3DS)',
          subtitle: 'Push games straight into FBI on the 3DS.',
          enabled: ref.watch(settingsProvider.select((s) => s.isFbiEnabled)),
          stop: () async => ref.read(fbiServerProvider.notifier).disable(),
        ),
        _switch(
          ref,
          id: 'fpkgi',
          title: 'FPKGi Server (PlayStation 4)',
          subtitle: 'Host the PS4 library as an FPKGi shop with covers.',
          enabled: ref.watch(settingsProvider.select((s) => s.isFpkgiEnabled)),
          stop: () async => ref.read(fpkgiServerProvider.notifier).disable(),
        ),
      ],
    );
  }

  Widget _switch(
    WidgetRef ref, {
    required String id,
    required String title,
    required String subtitle,
    required bool enabled,
    required Future<void> Function() stop,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: enabled,
      onChanged: (v) async {
        // A running server must not outlive its menu tile.
        if (!v) await stop();
        await ref.read(settingsProvider.notifier).setExtraServerEnabled(id, v);
      },
    );
  }
}
