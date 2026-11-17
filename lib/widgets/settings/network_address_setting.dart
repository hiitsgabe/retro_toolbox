import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/widgets/settings/rows/segmented_row.dart';

/// Lets the user pin which local IP every server (Tinfoil, FBI, Retro Tools,
/// FTP, JDKV) advertises, instead of each one guessing. "Automatic" keeps the
/// old best-guess behaviour. The addresses are looked up each time the row
/// is shown, so a new network shows on the next visit.
class NetworkAddressSetting extends ConsumerStatefulWidget {
  const NetworkAddressSetting({super.key});

  /// Test seam: this device's addresses.
  @visibleForTesting
  static List<String>? debugAddresses;

  @override
  ConsumerState<NetworkAddressSetting> createState() => _NetworkAddressSettingState();
}

class _NetworkAddressSettingState extends ConsumerState<NetworkAddressSetting> {
  late Future<List<String>> _addresses;

  @override
  void initState() {
    super.initState();
    final fixed = NetworkAddressSetting.debugAddresses;
    _addresses = fixed != null ? Future.value(fixed) : TinfoilServerService.localAddresses();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(settingsProvider).preferredLocalIp;
    final notifier = ref.read(settingsProvider.notifier);

    return FutureBuilder<List<String>>(
      future: _addresses,
      builder: (context, snap) {
        final ips = snap.data ?? const [];
        return SettingsSegmentedRow<String?>(
          title: 'Address the servers use',
          subtitle: 'What Tinfoil, FBI, FTP and the others advertise',
          options: [
            (null, 'Automatic'),
            for (final ip in ips) (ip, ip),
            // A previously-picked IP that's not currently up (different Wi-Fi).
            if (selected != null && !ips.contains(selected)) (selected, '$selected (not here)'),
          ],
          selected: selected,
          onChanged: notifier.setPreferredLocalIp,
        );
      },
    );
  }
}
