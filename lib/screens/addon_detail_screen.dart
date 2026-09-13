import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/widgets/settings/console_auth_setting.dart';
import 'package:roms_downloader/widgets/settings/vault_warning.dart';

/// The addon detail: identity, account, coverage, priority and remove.
///
/// Coverage shows which consoles the addon serves, not how many items in each:
/// a per-console count would cost one listing request per console, and the app
/// loads listings on demand precisely because they are expensive.
class AddonDetailScreen extends ConsumerWidget {
  final String addonId;

  const AddonDetailScreen({super.key, required this.addonId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final index = addons.indexWhere((a) => a.id == addonId);

    // Removal changes the list before the `pop` completes, so this frame really
    // exists. Without the guard, `addons[index]` below blows up with index -1
    // on the happy path of the Remove button.
    if (index < 0) return const Scaffold(body: SizedBox.shrink());

    final addon = addons[index];
    final catalog = ref.watch(mergedCatalogProvider);

    return Scaffold(
      appBar: AppBar(title: Text(addon.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Source',
            child: Text(addon.url ?? (addon.isBuiltin ? 'Installed with the app' : 'Installed from file')),
          ),
          catalog.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
            error: (e, _) => _Section(title: 'Coverage', child: Text('Unreadable catalog: $e')),
            data: (merged) {
              final coverage = merged.coverage()[addonId] ?? (consoles: const <String>[], authConsoles: const <String>[]);
              // A declaration, not `final name = (String id) => ...`:
              // `prefer_function_declarations_over_variables` is on and the
              // variable form would trip the lint.
              String name(String id) => merged.consoles[id]?.name ?? id;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (coverage.authConsoles.isNotEmpty) const VaultWarning(),
                  for (final consoleId in coverage.authConsoles)
                    if (merged.consoles[consoleId] != null)
                      _Section(
                        title: 'Account: ${name(consoleId)}',
                        child: ConsoleAuthSetting(console: merged.consoles[consoleId]!, addonId: addonId),
                      ),
                  _Section(
                    title: 'Coverage',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(coverage.consoles.isEmpty
                            ? 'No console'
                            : '${coverage.consoles.length} console${coverage.consoles.length == 1 ? '' : 's'}'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final id in coverage.consoles) Chip(label: Text(name(id)))],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          _Section(
            title: 'Priority',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${index + 1} of ${addons.length}'),
                const SizedBox(height: 4),
                Text(
                  'Drag in the addons list to change the order. The first source that has the file is the one that downloads.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _confirmRemoval(context, ref, addon),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoval(BuildContext context, WidgetRef ref, Addon addon) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${addon.name}?'),
        // The token stays in the vault on purpose (`AddonNotifier.remove`);
        // saying so here stops the user from thinking they must rediscover the
        // credential to reinstall.
        content: const Text('The catalog leaves the app. The credential stays saved, and reinstalling the same source finds it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove addon')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(addonProvider.notifier).remove(addon.id);
    navigator.pop();
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
