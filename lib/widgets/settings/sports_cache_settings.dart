import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/services/formation_cache_service.dart';
import 'package:retro_toolbox/services/storage_usage.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';

/// One row that wipes every sports cache: the ESPN fetch cache (rrp_cache)
/// and the locally saved formations. Settings, Storage.
class SportsCacheSettings extends ConsumerStatefulWidget {
  const SportsCacheSettings({super.key, this.size});

  /// What they take on disk, when known.
  final int? size;

  @override
  ConsumerState<SportsCacheSettings> createState() => _SportsCacheSettingsState();
}

class _SportsCacheSettingsState extends ConsumerState<SportsCacheSettings> {
  bool _busy = false;

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear sports caches'),
        content: const Text('This removes all downloaded roster data (ESPN cache) and every locally saved formation. This cannot be undone.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await FormationCacheService.clearAll();
      ref.invalidate(storageUsageProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sports caches cleared'), duration: Duration(seconds: 2)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clear caches: $e'), backgroundColor: Theme.of(context).colorScheme.error),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SettingsActionRow(
      title: 'Sports caches',
      subtitle: size != null && size > 0 ? '${storageSize(size)} of rosters and formations' : 'Rosters and formations',
      action: 'Clear',
      busy: _busy,
      onPressed: _clear,
    );
  }
}
