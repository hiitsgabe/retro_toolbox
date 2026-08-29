import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/tinfoil_server_provider.dart';

/// Controls the embedded Tinfoil shop server and shows the connection
/// details to enter on the Switch once it is running.
class TinfoilServerScreen extends ConsumerWidget {
  const TinfoilServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tinfoilServerProvider);
    final notifier = ref.read(tinfoilServerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tinfoil Server')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('Enable server'),
            subtitle: Text(state.running ? 'Serving Switch games from the catalog' : 'Off'),
            value: state.running,
            onChanged: (v) => v ? notifier.enable() : notifier.disable(),
          ),
          if (!state.running)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextFormField(
                initialValue: '${state.port}',
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true),
                onChanged: (v) {
                  final port = int.tryParse(v);
                  if (port != null && port > 0 && port < 65536) notifier.setPort(port);
                },
              ),
            ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (state.running) ...[
            const SizedBox(height: 8),
            Text('Server addresses', style: theme.textTheme.titleSmall),
            for (final addr in state.addresses)
              ListTile(
                dense: true,
                leading: const Icon(Icons.wifi),
                title: Text(addr, style: const TextStyle(fontFamily: 'monospace')),
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => Clipboard.setData(ClipboardData(text: addr)),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('In Tinfoil on your Switch', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    const Text('1. Open Tinfoil → File Browser\n'
                        '2. Press [-] / New to add a source\n'
                        '3. Protocol: http\n'
                        '4. Host: the IP above (without http:// and port)\n'
                        '5. Port: the port above\n'
                        '6. Path: /\n'
                        '7. Save — games appear under New Games'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Active transfers: ${state.activeTransfers}', style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
