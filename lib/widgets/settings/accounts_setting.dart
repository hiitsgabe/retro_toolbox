import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/widgets/settings/ia_credentials_setting.dart';

/// Connected accounts, one accordion per provider. Collapsed once connected so
/// it stays out of the way; opens when the user still needs to log in. More
/// providers will be added here over time.
class AccountsSetting extends ConsumerWidget {
  const AccountsSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(settingsProvider).hasIaCredentials;

    return ExpansionTile(
      // Rebuild so the status subtitle updates after login/logout.
      key: ValueKey('ia_$loggedIn'),
      initiallyExpanded: false,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      // account_balance is the columned-building glyph — matches the IA logo.
      leading: const Icon(Icons.account_balance),
      title: const Text('Internet Archive'),
      subtitle: Text(loggedIn ? 'Connected' : 'Not connected'),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: const [IaCredentialsSetting()],
    );
  }
}
