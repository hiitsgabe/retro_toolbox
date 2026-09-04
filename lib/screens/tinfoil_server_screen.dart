import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/providers/tinfoil_server_provider.dart';
import 'package:roms_downloader/services/tinfoil_server_service.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Controls the embedded Tinfoil shop server and shows the connection
/// details to enter on the Switch once it is running.
class TinfoilServerScreen extends ConsumerWidget {
  const TinfoilServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tinfoilServerProvider);
    final notifier = ref.read(tinfoilServerProvider.notifier);
    final theme = Theme.of(context);
    final host = state.addresses.isNotEmpty ? state.addresses.first : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Tinfoil Server')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ToolDescription(
            icon: Icons.cloud_upload_rounded,
            text: 'Hosts your game library over the local network so Tinfoil on your console can browse and install titles directly from this device. Both must be on the same network.',
          ),
          const SizedBox(height: 16),
          ..._authSections(context, ref),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable server'),
                subtitle: Text(state.running ? 'Serving Switch games' : 'Off'),
                value: state.running,
                onChanged: (v) => v ? notifier.enable() : notifier.disable(),
              ),
            ),
          ),
          if (!state.running) ...[
            const SizedBox(height: 16),
            TextFormField(
              initialValue: '${state.port}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) {
                final port = int.tryParse(v);
                if (port != null && port > 0 && port < 65536) notifier.setPort(port);
              },
            ),
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
            if (state.addresses.length > 1) ...[
              const SizedBox(height: 8),
              _otherAddresses(context, state),
            ],
            const SizedBox(height: 16),
            Center(
              child: Text('Active transfers: ${state.activeTransfers}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ],
      ),
    );
  }

  /// Switch sources need a login token to download. Show each such console's
  /// auth UI in an accordion — open when it still needs sign-in, collapsed once
  /// authenticated so it stays out of the way.
  List<Widget> _authSections(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final consoles = ref.watch(appStateProvider).consolesList.where(
          (c) => TinfoilServerService.isSwitchConsole(c) && c.hasTokenAuth,
        );
    if (consoles.isEmpty) return const [];

    bool authed(Console c) =>
        (settings.consoleSettings[c.id]?.authToken?.isNotEmpty ?? false) || ((c.auth?['token'] as String?)?.isNotEmpty ?? false);

    return [
      for (final c in consoles) ...[
        Card(
          margin: EdgeInsets.zero,
          child: ExpansionTile(
            // Rebuild the tile when auth flips so it collapses on sign-in.
            key: ValueKey('auth_${c.id}_${authed(c)}'),
            initiallyExpanded: !authed(c),
            shape: const Border(),
            leading: Icon(
              authed(c) ? Icons.check_circle : Icons.lock_outline,
              color: authed(c) ? Colors.green : theme.colorScheme.error,
            ),
            title: Text('${c.name} sign-in'),
            subtitle: Text(authed(c) ? 'Authenticated' : 'Required to download'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [ConsoleAuthSetting(console: c)],
          ),
        ),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _connectionCard(BuildContext context, String host, int port) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Enter this in Tinfoil', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 16),
            _field(context, 'Host', host),
            const Divider(height: 24),
            _field(context, 'Port', '$port'),
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(width: 52, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer))),
        Expanded(
          child: SelectableText(
            value,
            style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: theme.colorScheme.onPrimaryContainer),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 20),
          color: theme.colorScheme.onPrimaryContainer,
          tooltip: 'Copy $label',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)));
          },
        ),
      ],
    );
  }

  Widget _instructions(ThemeData theme) {
    const steps = [
      'Open Tinfoil → File Browser → New',
      'Set Protocol to http, then enter the host and port above',
      'Save — your games show up under New Games',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 11, backgroundColor: theme.colorScheme.secondaryContainer, child: Text('${i + 1}', style: theme.textTheme.labelSmall)),
                const SizedBox(width: 12),
                Expanded(child: Text(steps[i], style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _otherAddresses(BuildContext context, TinfoilServerState state) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('Other addresses', style: Theme.of(context).textTheme.bodySmall),
      children: [
        for (final ip in state.addresses.skip(1))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.wifi, size: 18),
            title: Text(ip, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 16),
              onPressed: () => Clipboard.setData(ClipboardData(text: ip)),
            ),
          ),
      ],
    );
  }
}
