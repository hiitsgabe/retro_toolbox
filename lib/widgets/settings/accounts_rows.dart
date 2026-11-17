import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_logins.dart';
import 'package:retro_toolbox/services/save_sync/catalog_source.dart';
import 'package:retro_toolbox/widgets/settings/console_auth_setting.dart';
import 'package:retro_toolbox/widgets/settings/ia_credentials_setting.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';
import 'package:retro_toolbox/widgets/settings/save_recipes_source_setting.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';
import 'package:retro_toolbox/widgets/settings/settings_sheet.dart';

String _consoles(int n) => '$n console${n == 1 ? '' : 's'}';

/// The Internet Archive login, for the [count] loaded consoles on it.
class InternetArchiveRow extends ConsumerWidget {
  const InternetArchiveRow({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(settingsProvider.select((s) => s.hasIaCredentials));
    return SettingsValueRow(
      key: const ValueKey('login ia'),
      title: 'Internet Archive',
      subtitle: 'Used by ${_consoles(count)}. ${connected ? 'Connected' : 'Not connected'}',
      value: connected ? 'Manage' : 'Sign in',
      onTap: () => showSettingsSheet<void>(
        context,
        title: 'Internet Archive',
        subtitle: 'For restricted downloads on archive.org.',
        closeLabel: 'Done',
        builder: (_) => const IaCredentialsSetting(),
      ),
    );
  }
}

/// A token or cookie login some loaded consoles share.
class CatalogLoginRow extends ConsumerWidget {
  const CatalogLoginRow({super.key, required this.login});

  final CatalogLogin login;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = login.signedInWith(ref.watch(settingsProvider));
    final names = login.consoles.map((c) => c.name).join(', ');
    return SettingsValueRow(
      key: ValueKey('login ${login.title}'),
      title: login.title,
      subtitle: '$names. ${signedIn ? 'Signed in' : 'Not signed in'}',
      value: signedIn ? 'Manage' : 'Sign in',
      onTap: () => showSettingsSheet<void>(
        context,
        title: login.title,
        subtitle: names,
        closeLabel: 'Done',
        builder: (_) => ConsoleAuthSetting(console: login.consoles.first, applyTo: login.consoleIds),
      ),
    );
  }
}

/// Save Sync's Google Drive account.
class GoogleDriveRow extends ConsumerStatefulWidget {
  const GoogleDriveRow({super.key});

  @override
  ConsumerState<GoogleDriveRow> createState() => _GoogleDriveRowState();
}

class _GoogleDriveRowState extends ConsumerState<GoogleDriveRow> {
  @override
  void initState() {
    super.initState();
    // Settings may open before Save Sync ever did: read who is signed in.
    if (ref.read(saveSyncProvider).hubKind == HubKind.unknown) {
      Future.microtask(() {
        if (mounted) ref.read(saveSyncProvider.notifier).loadHub();
      });
    }
  }

  Future<void> _manage() {
    return showSettingsSheet<void>(
      context,
      title: 'Google Drive',
      subtitle: 'Save Sync keeps your saves on this account\'s Drive.',
      builder: (sheet) => Consumer(builder: (sheet, ref, _) {
        final s = ref.watch(saveSyncProvider);
        final n = ref.read(saveSyncProvider.notifier);
        final signedIn = s.hubKind == HubKind.drive;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
          if (signedIn && s.googleEmail.isNotEmpty) SettingsInfo('Signed in as ${s.googleEmail}'),
          if (s.signInError != null) SettingsInfo(s.signInError!, error: true),
          if (signedIn)
            SheetOption(
              icon: SettingsIcons.trash,
              label: 'Sign out',
              danger: true,
              autofocus: true,
              onPressed: () async {
                Navigator.of(sheet).pop();
                await n.signOut();
              },
            )
          else if (!s.googleAvailable)
            const SettingsInfo('This build cannot sign in to Google.')
          else
            SheetOption(
              icon: SettingsIcons.accounts,
              label: s.signingIn ? 'Signing in' : 'Sign in with Google',
              autofocus: true,
              onPressed: s.signingIn
                  ? null
                  : () async {
                      await n.signInWithGoogle();
                      if (sheet.mounted && ref.read(saveSyncProvider).signInError == null) Navigator.of(sheet).pop();
                    },
            ),
        ]);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(saveSyncProvider);
    final signedIn = s.hubKind == HubKind.drive;
    final who = signedIn ? (s.googleEmail.isEmpty ? 'Signed in' : 'Signed in as ${s.googleEmail}') : 'Not signed in';
    return SettingsValueRow(
      key: const ValueKey('login google'),
      title: 'Google Drive',
      subtitle: 'Keeps saves in sync between devices. $who',
      value: signedIn ? 'Manage' : 'Sign in',
      onTap: _manage,
    );
  }
}

/// Where Save Sync reads its recipes from; the editor opens in a sheet.
class RecipesSourceRow extends ConsumerStatefulWidget {
  const RecipesSourceRow({super.key});

  @override
  ConsumerState<RecipesSourceRow> createState() => _RecipesSourceRowState();
}

class _RecipesSourceRowState extends ConsumerState<RecipesSourceRow> {
  String? _custom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mine = await ref.read(saveSyncProvider.notifier).catalogSetting();
      if (mounted) setState(() => _custom = mine);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final custom = _custom;
    final host = custom == null || custom.isEmpty ? null : (Uri.tryParse(custom)?.host ?? custom);
    return SettingsValueRow(
      title: 'Recipes source',
      subtitle: 'Where Save Sync reads game recipes from',
      value: host == null || host.isEmpty ? 'GitHub (default)' : host,
      onTap: () async {
        await showSettingsSheet<void>(
          context,
          title: 'Recipes source',
          subtitle: 'Leave it empty for $defaultCatalogBase',
          closeLabel: 'Done',
          builder: (_) => const SaveRecipesSourceSetting(),
        );
        await _load();
      },
    );
  }
}
