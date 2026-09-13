import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/settings/ia_credentials_setting.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

/// Connected accounts, one accordion per provider. Collapsed once connected so
/// it stays out of the way; opens when the user still needs to log in.
///
/// The consolidated view: non-addon accounts (today, the Internet Archive) and
/// one per (addon, console) pair that needs a credential. The same credential
/// is editable here and in the addon detail, and that is an accepted cost.
class AccountsSetting extends ConsumerWidget {
  const AccountsSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loggedIn = ref.watch(settingsProvider).hasIaCredentials;
    final accounts = ref.watch(addonAccountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const VaultWarning(),
        ExpansionTile(
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
        ),
        // Loading and error draw nothing: this is a section inside the settings
        // screen, and a progress bar flashing here on every open costs more
        // than the one-frame wait.
        ...accounts.maybeWhen(
          data: (list) => [for (final account in list) _AddonAccount(account: account)],
          orElse: () => const <Widget>[],
        ),
      ],
    );
  }
}

/// An addon account, with the connection state in the subtitle.
class _AddonAccount extends ConsumerStatefulWidget {
  final AddonAccount account;

  const _AddonAccount({required this.account});

  @override
  ConsumerState<_AddonAccount> createState() => _AddonAccountState();
}

class _AddonAccountState extends ConsumerState<_AddonAccount> {
  String? _token;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    final token = await ref.read(settingsProvider.notifier).readAddonToken(
          widget.account.addon.id,
          widget.account.console.id,
        );
    if (!mounted) return;
    setState(() => _token = token);
  }

  @override
  Widget build(BuildContext context) {
    final console = widget.account.console;
    // Until the vault responds the subtitle is just the console name, never
    // "Not connected": telling a connected user they are not, for one frame, is
    // the only one of the three answers that is a lie.
    final state = _token == null ? console.name : '${console.name}: ${_token!.isEmpty ? 'Not connected' : 'Connected'}';

    return ExpansionTile(
      initiallyExpanded: false,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.extension_outlined),
      title: Text(widget.account.addon.name),
      subtitle: Text(state),
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        ConsoleAuthSetting(
          console: console,
          addonId: widget.account.addon.id,
          onSaved: (token) {
            if (mounted) setState(() => _token = token);
          },
        ),
      ],
    );
  }
}
