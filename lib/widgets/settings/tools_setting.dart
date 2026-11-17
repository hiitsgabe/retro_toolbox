import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/catalog_provider.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';

class ToolsSetting extends ConsumerWidget {
  final Console? console;

  const ToolsSetting({
    super.key,
    required this.console,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogNotifier = ref.read(catalogProvider.notifier);

    return SettingsActionRow(
      title: console != null ? 'Catalog cache for this console' : 'Catalog cache',
      subtitle: console != null ? 'Rebuilt on the next load' : 'For every console, rebuilt on the next load',
      action: 'Clear',
      onPressed: () => _showClearCacheDialog(context, catalogNotifier),
    );
  }

  void _showClearCacheDialog(BuildContext context, CatalogNotifier catalogNotifier) {
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
