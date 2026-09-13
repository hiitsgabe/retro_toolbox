import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/addon_model.dart';
import 'package:roms_downloader/providers/addon_provider.dart';
import 'package:roms_downloader/providers/vault_provider.dart';
import 'package:roms_downloader/screens/addon_detail_screen.dart';
import 'package:roms_downloader/services/addon_install.dart';
import 'package:roms_downloader/services/console_merge.dart';

/// The ordered list of sources. The order is the priority: it feeds
/// `sourcePriorityProvider`, so dragging a row here changes which source
/// downloads the file.
class AddonsScreen extends ConsumerWidget {
  const AddonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(addonProvider);
    final coverage = ref.watch(addonCoverageProvider).valueOrNull ?? const <String, AddonCoverage>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Addons')),
      body: Column(
        children: [
          Expanded(
            child: addons.isEmpty
                ? const Center(child: Text('No addons installed.'))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: addons.length,
                    onReorder: (from, to) => ref.read(addonProvider.notifier).reorder(from, to),
                    itemBuilder: (context, i) {
                      final addon = addons[i];
                      return _Row(
                        key: ValueKey(addon.id),
                        index: i,
                        addon: addon,
                        // Absent means zero coverage, not error: the state of a
                        // freshly installed addon whose catalog is not read yet.
                        coverage: coverage[addon.id] ?? (consoles: const <String>[], authConsoles: const <String>[]),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _installDialog(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Install from URL'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _installDialog(BuildContext context, WidgetRef ref) async {
    final url = await showDialog<String>(context: context, builder: (_) => const _UrlDialog());
    if (url == null || url.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final vault = (await ref.read(vaultProvider.future)).vault;
      await installAddonFromUrl(
        url,
        notifier: ref.read(addonProvider.notifier),
        vault: vault,
        fetch: ref.read(catalogFetcherProvider),
      );
    } catch (e) {
      // A message instead of a stack trace: the two likely errors are a wrong
      // URL and a server that returns a login page, neither of which is a bug.
      messenger.showSnackBar(SnackBar(content: Text('Could not install: $e')));
    }
  }
}

/// The "Install from URL" dialog. Stateful only for the sake of `dispose`: the
/// controller must outlive the `TextField`, and disposing it inline would kill
/// it mid-transition. With it in `State`, the framework disposes it after the
/// route is actually gone.
class _UrlDialog extends StatefulWidget {
  const _UrlDialog();

  @override
  State<_UrlDialog> createState() => _UrlDialogState();
}

class _UrlDialogState extends State<_UrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install from URL'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Catalog address', hintText: 'https://example.org/catalog.json'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text.trim()), child: const Text('Install')),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final int index;
  final Addon addon;
  final AddonCoverage coverage;

  const _Row({super.key, required this.index, required this.addon, required this.coverage});

  @override
  Widget build(BuildContext context) {
    final n = coverage.consoles.length;
    return ListTile(
      leading: const Icon(Icons.extension_outlined),
      title: Text(addon.name),
      subtitle: Row(
        children: [
          Text(n == 0 ? 'No console' : '$n console${n == 1 ? '' : 's'}'),
          if (coverage.authConsoles.isNotEmpty) ...[
            const SizedBox(width: 8),
            const Chip(
              label: Text('account'),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The handle is the only drag point, which is why
          // `buildDefaultDragHandles` is false above: with it on, the whole row
          // drags and the tap that opens the detail becomes a one-pixel drag.
          ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_handle)),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AddonDetailScreen(addonId: addon.id)),
      ),
    );
  }
}
