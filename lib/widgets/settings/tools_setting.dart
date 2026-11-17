import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/services/storage_usage.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';

/// Clear the catalog cache: every console's ([console] null) or one's.
class ToolsSetting extends ConsumerWidget {
  final Console? console;

  /// What it takes on disk, when known.
  final int? size;

  const ToolsSetting({
    super.key,
    required this.console,
    this.size,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogNotifier = ref.read(catalogProvider.notifier);

    final known = size != null && size! > 0 ? storageSize(size!) : null;
    final String subtitle;
    if (console == null) {
      subtitle = known == null ? 'For all consoles, rebuilt on the next load' : '$known for all consoles, rebuilt on the next load';
    } else {
      subtitle = known == null ? 'Rebuilt on the next load' : '$known, rebuilt on the next load';
    }
    return SettingsActionRow(
      title: console != null ? 'Catalog cache for this console' : 'Catalog cache',
      subtitle: subtitle,
      action: 'Clear',
      onPressed: () => _showClearCacheDialog(context, ref, catalogNotifier),
    );
  }

  void _showClearCacheDialog(BuildContext context, WidgetRef ref, CatalogNotifier catalogNotifier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Catalog Cache'),
        content: Text(
          console != null
              ? 'Are you sure you want to clear the catalog cache for ${console!.name}?'
              : 'Are you sure you want to clear the catalog cache for all consoles?',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await catalogNotifier.clearCatalogCache(console?.id);
              await catalogNotifier.refreshCatalog();
              ref.invalidate(storageUsageProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Catalog cache cleared')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
