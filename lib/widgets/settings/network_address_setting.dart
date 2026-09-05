import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';

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
    final theme = Theme.of(context);
    final selected = ref.watch(settingsProvider).preferredLocalIp;
    final notifier = ref.read(settingsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('The address servers share with your consoles and other devices.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        FutureBuilder<List<String>>(
          future: _addresses,
          builder: (context, snap) {
            final ips = snap.data ?? const [];
            return Column(
              children: [
                RadioListTile<String?>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Automatic'),
                  subtitle: Text(ips.isNotEmpty ? 'Uses ${ips.first}' : 'Best guess', style: theme.textTheme.bodySmall),
                  value: null,
                  groupValue: selected,
                  onChanged: (v) => notifier.setPreferredLocalIp(v),
                ),
                for (final ip in ips)
                  RadioListTile<String?>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(ip, style: const TextStyle(fontFamily: 'monospace')),
                    value: ip,
                    groupValue: selected,
                    onChanged: (v) => notifier.setPreferredLocalIp(v),
                  ),
                // A previously-picked IP that's not currently up (different Wi-Fi).
                if (selected != null && !ips.contains(selected))
                  RadioListTile<String?>(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(selected, style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text('Not on this network right now', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                    value: selected,
                    groupValue: selected,
                    onChanged: (v) => notifier.setPreferredLocalIp(v),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _addresses = TinfoilServerService.localAddresses()),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
