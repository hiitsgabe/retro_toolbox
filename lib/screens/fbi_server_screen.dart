import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:roms_downloader/providers/fbi_server_provider.dart';
import 'package:roms_downloader/services/fbi_server_service.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Serves 3DS .cia titles and installs them on a console running FBI, either by
/// pushing the URL to FBI's "Receive URLs over the network" or via a QR code.
class FbiServerScreen extends ConsumerStatefulWidget {
  const FbiServerScreen({super.key});

  @override
  ConsumerState<FbiServerScreen> createState() => _FbiServerScreenState();
}

class _FbiServerScreenState extends ConsumerState<FbiServerScreen> {
  late final _ip = TextEditingController(text: ref.read(fbiServerProvider).threeDsIp);

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _send(FbiGame g) async {
    final ip = _ip.text.trim();
    if (ip.isEmpty) return _snack('Enter your 3DS IP first.');
    await ref.read(fbiServerProvider.notifier).setThreeDsIp(ip);
    try {
      await ref.read(fbiServerProvider.notifier).sendToThreeDs(g.url);
      _snack('Sent “${g.game.title}” to your 3DS.');
    } catch (e) {
      _snack('Failed to reach FBI at $ip:5000 — $e');
    }
  }

  void _showQr(FbiGame g) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(g.game.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(data: g.url, size: 240, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 12),
            const Text('In FBI: Remote Install → Scan QR Code', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fbiServerProvider);
    final notifier = ref.read(fbiServerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('FBI Server')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ToolDescription(
            icon: Icons.install_mobile,
            text: 'Installs 3DS .cia titles onto a console running FBI over the local network. Turn the '
                'server on, then push a game to your 3DS or scan its QR in FBI.',
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable server'),
                subtitle: Text(state.running ? 'Serving 3DS titles' : 'Off'),
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
              decoration: const InputDecoration(labelText: 'Server port', border: OutlineInputBorder(), isDense: true),
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
          if (state.running) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _ip,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '3DS IP address',
                hintText: 'shown in FBI → Remote Install → Receive URLs',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.devices),
              ),
              onChanged: notifier.setThreeDsIp,
            ),
            const SizedBox(height: 16),
            _instructions(theme),
            const SizedBox(height: 16),
            Text('3DS titles', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            FutureBuilder<List<FbiGame>>(
              future: notifier.loadGameList(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                }
                final games = snap.data ?? [];
                if (games.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('No 3DS (.cia) titles in your catalog.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  );
                }
                return Column(children: [for (final g in games) _gameCard(theme, g)]);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _gameCard(ThemeData theme, FbiGame g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.videogame_asset_outlined),
        title: Text(g.game.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(g.console.name, style: theme.textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.qr_code_2), tooltip: 'QR', onPressed: () => _showQr(g)),
            IconButton(icon: const Icon(Icons.send), tooltip: 'Send to 3DS', onPressed: () => _send(g)),
          ],
        ),
      ),
    );
  }

  Widget _instructions(ThemeData theme) {
    const steps = [
      'On the 3DS: open FBI → Remote Install → Receive URLs over the network',
      'Type the IP it shows above, then Send — or scan a game’s QR',
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
}
