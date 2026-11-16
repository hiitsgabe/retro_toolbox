import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/save_sync_provider.dart';
import 'package:retro_toolbox/services/save_sync/catalog_source.dart';

/// Where Save Sync reads its recipes from. Empty means the repo's own folder
/// on GitHub; an address here points every refresh somewhere else.
class SaveRecipesSourceSetting extends ConsumerStatefulWidget {
  const SaveRecipesSourceSetting({super.key});

  @override
  ConsumerState<SaveRecipesSourceSetting> createState() => _SaveRecipesSourceSettingState();
}

class _SaveRecipesSourceSettingState extends ConsumerState<SaveRecipesSourceSetting> {
  final _controller = TextEditingController();
  String? _effective;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Shows what is stored and what is used. A store that cannot be read
  /// leaves the field as it is: this runs from initState, where a throw would
  /// escape into the framework.
  Future<void> _load() async {
    final String? mine;
    final String base;
    try {
      final n = ref.read(saveSyncProvider.notifier);
      mine = await n.catalogSetting();
      base = await n.catalogBase();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _controller.text = mine ?? '';
      _effective = base;
    });
  }

  Future<void> _save(String? url) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      final ok = await ref.read(saveSyncProvider.notifier).setCatalogSetting(url);
      if (!ok) {
        error = 'Use an https:// address';
      } else {
        await _load();
      }
    } catch (e) {
      error = 'Could not save: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _controller,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(labelText: 'Recipes URL', hintText: defaultCatalogBase, errorText: _error),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        FilledButton(
          onPressed: _busy ? null : () => _save(_controller.text.trim().isEmpty ? null : _controller.text),
          child: const Text('Save'),
        ),
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  _controller.clear();
                  _save(null);
                },
          child: const Text('Reset to default'),
        ),
      ]),
      if (_effective != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Reading from: $_effective', style: theme.textTheme.bodySmall),
        ),
    ]);
  }
}
