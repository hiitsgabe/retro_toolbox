import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/vault_provider.dart';

/// Warns, where the secret is typed, that this device has no keyring.
class VaultWarning extends ConsumerWidget {
  const VaultWarning({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(vaultProvider).when(
          loading: () => null,
          error: (e, _) => 'Could not open any vault, neither the system one nor the fallback: $e',
          data: (choice) => choice.encryptedAtRest ? null : 'Credentials are stored in plain text on this device.',
        );
    if (text == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_open, size: 20, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: colors.onErrorContainer)),
                const SizedBox(height: 4),
                Text(
                  'Without gnome-keyring or KWallet, the app stores the secret as before. The catalog you share stays free of tokens.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onErrorContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
