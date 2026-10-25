import 'package:flutter/material.dart';
import 'package:retro_toolbox/services/formation_cache_service.dart';

/// One button that wipes every sports cache: the ESPN fetch cache (rrp_cache)
/// and the locally saved formations. Used in the general settings.
class SportsCacheSettings extends StatefulWidget {
  const SportsCacheSettings({super.key});

  @override
  State<SportsCacheSettings> createState() => _SportsCacheSettingsState();
}

class _SportsCacheSettingsState extends State<SportsCacheSettings> {
  bool _busy = false;

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear sports caches'),
        content: const Text(
            'This removes all downloaded roster data (ESPN cache) and every locally saved formation. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await FormationCacheService.clearAll();
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
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        onPressed: _busy ? null : _clear,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.delete_sweep_outlined),
        label: const Text('Clear all sports caches'),
      ),
    );
  }
}