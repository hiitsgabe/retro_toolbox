import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A collapsed "Advanced" accordion holding the server port field. Ports are
/// constrained to 9091–9099 (the range shared by the app's LAN servers).
class AdvancedPort extends StatelessWidget {
  final int port;
  final ValueChanged<int> onChanged;
  const AdvancedPort({super.key, required this.port, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        leading: const Icon(Icons.tune, size: 20),
        title: const Text('Advanced'),
        subtitle: Text('Port $port', style: Theme.of(context).textTheme.bodySmall),
        children: [
          TextFormField(
            initialValue: '$port',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Port (9091–9099)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              final p = int.tryParse(v);
              if (p != null && p >= 9091 && p <= 9099) onChanged(p);
            },
          ),
        ],
      ),
    );
  }
}
