import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/tinfoil_server_provider.dart';
import 'package:retro_toolbox/widgets/settings/rows/switch_row.dart';

/// Settings, Network & servers: an on/off switch per console install server.
/// A server only shows its Servers-menu tile while enabled, and turning one
/// off stops it if it is running.
class ExtraServersSetting extends ConsumerWidget {
  const ExtraServersSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _switch(
          ref,
          id: 'tinfoil',
          title: 'Tinfoil (Switch)',
          subtitle: 'Browse and install the library from the console',
          enabled: ref.watch(settingsProvider.select((s) => s.isTinfoilEnabled)),
          stop: () async => ref.read(tinfoilServerProvider.notifier).disable(),
        ),
        _switch(
          ref,
          id: 'fbi',
          title: 'FBI (3DS)',
          subtitle: 'Push games straight into FBI',
          enabled: ref.watch(settingsProvider.select((s) => s.isFbiEnabled)),
          stop: () async => ref.read(fbiServerProvider.notifier).disable(),
        ),
        _switch(
          ref,
          id: 'fpkgi',
          title: 'FPKGi (PS4)',
          subtitle: 'Host the library as a shop with covers',
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
    return SettingsSwitchRow(
      title: title,
      subtitle: subtitle,
      value: enabled,
      onChanged: (v) async {
        // A running server must not outlive its menu tile.
        if (!v) await stop();
        await ref.read(settingsProvider.notifier).setExtraServerEnabled(id, v);
      },
    );
  }
}
