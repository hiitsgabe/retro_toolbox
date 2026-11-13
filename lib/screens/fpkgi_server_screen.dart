import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/providers/fpkgi_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/fpkgi_server_service.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/widgets/common/advanced_port.dart';
import 'package:retro_toolbox/widgets/settings/ia_credentials_setting.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:retro_toolbox/services/pick.dart';

/// Controls the embedded FPKGi server and shows the connection details to
/// enter on the PS4 once it is running.
class FpkgiServerScreen extends ConsumerWidget {
  const FpkgiServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fpkgiServerProvider);
    final notifier = ref.read(fpkgiServerProvider.notifier);
    final theme = Theme.of(context);
    final addresses = orderAddresses(state.addresses, ref.watch(settingsProvider).preferredLocalIp);
    final host = addresses.isNotEmpty ? addresses.first : null;
    final iaReady = ref.watch(settingsProvider).iaAccessKey?.isNotEmpty ?? false;
    // Only an Internet Archive source needs IA credentials; a PS4 catalog
    // served from anywhere else downloads without them.
    final needsIa = ref
        .watch(appStateProvider)
        .consolesList
        .where(FpkgiServerService.isPs4Console)
        .any((c) => c.usesInternetArchive);
    final hasPs4 = ref.watch(appStateProvider).consolesList.any(FpkgiServerService.isPs4Console);

    return Scaffold(
      appBar: AppBar(title: const Text('FPKGi Server')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ToolDescription(
            icon: Icons.cloud_upload_rounded,
            text: 'Hosts your PS4 library over the local network as an FPKGi shop. Packages and covers stream through this device with your Internet Archive sign-in, so the PS4 needs no credentials. Both must be on the same network.',
          ),
          const SizedBox(height: 16),
          if (needsIa && !iaReady) ...[
            Card(
              margin: EdgeInsets.zero,
              child: ExpansionTile(
                initiallyExpanded: true,
                shape: const Border(),
                leading: Icon(Icons.lock_outline, color: theme.colorScheme.error),
                title: const Text('Internet Archive sign-in required'),
                subtitle: const Text('The PS4 FPKG items are access-restricted; enter your IA keys.'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: const [IaCredentialsSetting()],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!hasPs4) ...[
            Card(
              margin: EdgeInsets.zero,
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('No PS4 system in the catalog'),
                subtitle: Text('Add the PlayStation 4 system to your catalog first.'),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable server'),
                subtitle: Text(state.running ? 'Serving PS4 games' : 'Off'),
                value: state.running,
                onChanged: (v) => v ? notifier.enable() : notifier.disable(),
              ),
            ),
          ),
          if (!state.running) ...[
            const SizedBox(height: 8),
            AdvancedPort(port: state.port, onChanged: notifier.setPort),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (state.running && host != null) ...[
            const SizedBox(height: 24),
            _connectionCard(context, host, state.port),
            const SizedBox(height: 16),
            _instructions(theme),
            const SizedBox(height: 16),
            Center(
              child: Text('Active transfers: ${state.activeTransfers}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _connectionCard(BuildContext context, String host, int port) {
    final theme = Theme.of(context);
    final url = 'http://$host:$port/games.json';
    final configJson = const JsonEncoder.withIndent('  ').convert({
      'FILTERING': {
        'CONTENT': 'all',
        'SORT': {'type': 'name', 'ascending': true},
        'REGIONS': ['Asia', 'Europe', 'Japan', 'USA'],
      },
      'PREFERENCES': {
        'DOWNLOADS': {
          'directDownload': false,
          'downloadPath': '/user/data/FPKGi/Downloads/',
          'installAfter': true,
          'deleteAfter': true,
          'deleteOnCancel': true,
        },
        'APPLICATION': {
          'background_uri': 'false',
          'backgroundMusic': false,
          'populateViaWeb': true,
          'enableUpdates': false,
        },
        'CONTENT_URLS': {
          'PS1': null,
          'PS2': null,
          'PSP': null,
          'PS5': null,
          'games': url,
          'apps': null,
          'updates': null,
          'DLC': null,
          'demos': null,
          'homebrew': null,
          'emulators': null,
          'themes': null,
        },
      },
    });
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Content URL', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(url, style: theme.textTheme.bodyLarge?.copyWith(fontFamily: 'monospace')),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded),
                  tooltip: 'Copy URL',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied $url')));
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save config.json'),
              onPressed: () async {
                final path = await pickSavePath(
                  context,
                  title: 'Save FPKGi config.json',
                  fileName: 'config.json',
                  bytes: Uint8List.fromList(utf8.encode(configJson)),
                );
                if (path == null || !context.mounted) return;
                String? error;
                if (!Platform.isIOS) {
                  try {
                    File(path).writeAsStringSync(configJson);
                  } catch (e) {
                    error = 'Could not save config.json: $e';
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error ?? 'Saved config.json')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _instructions(ThemeData theme) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('On the PS4', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            const Text(
              '1. Install FPKGi and FPKGi Data on the PS4 (from /data/pkg).\n'
              '2. Open FPKGi once so it creates /user/data/FPKGi/.\n'
              '3. Copy the saved config.json to /user/data/FPKGi/ on the PS4 via FTP.\n'
              '4. In FPKGi, press triangle (settings) and make sure "Populate via web" is ON, then press triangle again to save.\n'
              '5. Reopen FPKGi — it fetches the catalog from this device.\n'
              '6. Browse and install like a store (L2/R2 troca categoria).',
            ),
          ],
        ),
      ),
    );
  }
}
