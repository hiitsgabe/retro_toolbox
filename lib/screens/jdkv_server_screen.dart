import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/jdkv_server_provider.dart';
import 'package:roms_downloader/services/webdav_server_service.dart';
import 'package:roms_downloader/utils/formatters.dart';

/// Controls the embedded WebDAV server that syncs emulator saves with JKSV on
/// a Switch. Android→Switch (JKSV restores) and Switch→Android (confirm-to-pull).
class JdkvServerScreen extends ConsumerWidget {
  const JdkvServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(jdkvServerProvider);
    final notifier = ref.read(jdkvServerProvider.notifier);
    final theme = Theme.of(context);
    final host = state.addresses.isNotEmpty ? state.addresses.first : null;

    return Scaffold(
      appBar: AppBar(title: const Text('JDKV Server')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _folderCard(context, state, notifier),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable server'),
                subtitle: Text(state.running ? 'Sharing saves with JKSV' : 'Off'),
                value: state.running,
                onChanged: state.folder == null ? null : (v) => v ? notifier.enable() : notifier.disable(),
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
            const SizedBox(height: 20),
            _connectionCard(context, host, state.port),
            const SizedBox(height: 16),
            _instructions(theme),
          ],
          if (state.incoming.isNotEmpty) ...[
            const SizedBox(height: 20),
            _incomingSection(context, state, notifier),
          ],
          if (state.running) ...[
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

  Widget _folderCard(BuildContext context, JdkvServerState state, JdkvServerNotifier notifier) {
    final theme = Theme.of(context);
    final has = state.folder != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(has ? Icons.folder : Icons.folder_off_outlined,
                color: has ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Save exports folder', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(
                    has ? state.folder! : 'Not selected — export saves here from your emulator',
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: state.running
                  ? null
                  : () async {
                      final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Select save exports folder');
                      if (dir != null) notifier.setFolder(dir);
                    },
              child: Text(has ? 'Change' : 'Choose'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard(BuildContext context, String host, int port) {
    final theme = Theme.of(context);
    final json = '{\n  "origin": "http://$host:$port"\n}';
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('On the Switch: sdmc:/config/JKSV/webdav.json',
                style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(json,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: json));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('webdav.json copied'), duration: Duration(seconds: 1)),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _instructions(ThemeData theme) {
    const steps = [
      'Put the webdav.json above in sdmc:/config/JKSV/ on the Switch',
      'Open JKSV — it lists your Android saves as backups',
      'Select a game and press Y to restore it to the Switch',
      'To send back: back up a Switch save to WebDAV, then confirm the pull here',
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

  Widget _incomingSection(BuildContext context, JdkvServerState state, JdkvServerNotifier notifier) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.download_for_offline_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Incoming from Switch', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text('Confirm which saves to pull. The current export is backed up first.',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        for (final s in state.incoming)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.videogame_asset_outlined),
              title: Text(s.displayName),
              subtitle: Text('${s.titleId} · ${formatBytes(s.bytes)}'),
              trailing: FilledButton(
                onPressed: () => _confirmPull(context, notifier, s),
                child: const Text('Pull'),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmPull(BuildContext context, JdkvServerNotifier notifier, IncomingSave s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Pull ${s.displayName}?'),
        content: const Text('Your current export for this game will be copied to a timestamped backup, then replaced with the Switch save.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Pull')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final now = DateTime.now();
    final ts = '${now.year}${_pad2(now.month)}${_pad2(now.day)}-${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}';
    await notifier.pull(s.titleId, timestamp: ts);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.displayName} pulled — import it in your emulator')),
      );
    }
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}
