import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';

/// Lets the user pin which local IP every server (Tinfoil, FBI, Retro Tools,
/// FTP, JDKV) advertises, instead of each one guessing. "Automatic" keeps the
/// old best-guess behaviour.
class NetworkAddressSetting extends ConsumerStatefulWidget {
  const NetworkAddressSetting({super.key});

  @override
  ConsumerState<NetworkAddressSetting> createState() => _NetworkAddressSettingState();
}

class _NetworkAddressSettingState extends ConsumerState<NetworkAddressSetting> {
  late Future<List<String>> _addresses;

  @override
  void initState() {
    super.initState();
    _addresses = TinfoilServerService.localAddresses();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(settingsProvider).preferredLocalIp;
    final notifier = ref.read(settingsProvider.notifier);

    return FutureBuilder<List<String>>(
      future: _addresses,
      builder: (context, snap) {
        final ips = snap.data ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          SettingsSegmentedRow<String?>(
            title: 'Address the servers use',
            subtitle: 'What Tinfoil, FBI, FTP and the others share with your consoles. '
                '${ips.isNotEmpty ? 'Automatic uses ${ips.first}' : 'Automatic makes a best guess'}.',
            stacked: true,
            options: [
              (null, 'Automatic'),
              for (final ip in ips) (ip, ip),
              // A previously-picked IP that's not currently up (different Wi-Fi).
              if (selected != null && !ips.contains(selected)) (selected, '$selected (not on this network)'),
            ],
            selected: selected,
            onChanged: notifier.setPreferredLocalIp,
          ),
          SettingsActionRow(
            title: 'Look for addresses again',
            subtitle: 'After joining another network',
            action: 'Refresh',
            indent: true,
            onPressed: () => setState(() => _addresses = TinfoilServerService.localAddresses()),
          ),
        ]);
      },
    );
  }
}
