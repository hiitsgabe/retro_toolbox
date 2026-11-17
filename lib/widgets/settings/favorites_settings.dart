import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/favorites_provider.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/widgets/settings/rows/action_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/value_row.dart';
import 'package:retro_toolbox/widgets/settings/settings_icons.dart';
import 'package:retro_toolbox/widgets/settings/settings_sheet.dart';

String _games(int n) => '$n game${n == 1 ? '' : 's'}';

/// Settings > Library > Favorites: share them as a code, import a code, or
/// clear them, each a row opening its own sheet or question.
class FavoritesRows extends ConsumerStatefulWidget {
  const FavoritesRows({super.key});

  @override
  ConsumerState<FavoritesRows> createState() => _FavoritesRowsState();
}

class _FavoritesRowsState extends ConsumerState<FavoritesRows> {
  bool _exporting = false;

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: const Duration(seconds: 3),
    ));
  }

  /// Shares the favorites (once, or again on request) and shows the code.
  Future<void> _share() async {
    if (ref.read(favoritesProvider).exportSlug == null && !await _export()) return;
    if (!mounted) return;
    await showSettingsSheet<void>(
      context,
      title: 'Share favorites',
      subtitle: 'Type this code on another device, in Import favorites.',
      closeLabel: 'Done',
      builder: (sheet) => _ShareCode(onExportAgain: _export),
    );
  }

  Future<bool> _export() async {
    setState(() => _exporting = true);
    try {
      await ref.read(favoritesProvider.notifier).exportFavorites();
      return true;
    } catch (e) {
      _snack('Failed to export favorites', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() => showSettingsSheet<void>(
        context,
        title: 'Import favorites',
        subtitle: 'Adds the games of a shared code to yours.',
        builder: (_) => _ImportCode(onDone: _snack),
      );

  Future<void> _clear() async {
    final n = ref.read(favoritesProvider).count;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear favorites'),
        content: Text('Remove all ${_games(n)} from your favorites? This cannot be undone.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(favoritesProvider.notifier).clearFavorites();
    _snack('Favorites cleared');
  }

  @override
  Widget build(BuildContext context) {
    final n = ref.watch(favoritesProvider.select((f) => f.count));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      SettingsValueRow(
        title: 'Share favorites',
        subtitle: '${_games(n)}, as a code another device can import',
        value: _exporting ? 'Exporting' : 'Export',
        onTap: n == 0 || _exporting ? null : _share,
      ),
      SettingsValueRow(title: 'Import favorites', subtitle: 'From a code', value: 'Import', onTap: _import),
      SettingsActionRow(
        title: 'Clear favorites',
        subtitle: 'Removes all $n',
        action: 'Clear',
        danger: true,
        onPressed: n == 0 ? null : _clear,
      ),
    ]);
  }
}

/// The shared code, to read off or copy, with sharing again and deleting it.
class _ShareCode extends ConsumerStatefulWidget {
  const _ShareCode({required this.onExportAgain});

  final Future<bool> Function() onExportAgain;

  @override
  ConsumerState<_ShareCode> createState() => _ShareCodeState();
}

class _ShareCodeState extends ConsumerState<_ShareCode> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slug = ref.watch(favoritesProvider.select((f) => f.exportSlug));
    final code = slug?.split(':').first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
        child: SelectableText(
          code ?? 'No code yet',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1, color: scheme.onSurface, fontFamily: 'monospace'),
        ),
      ),
      if (code != null && !Handheld.current)
        SheetOption(
          icon: SettingsIcons.upload,
          label: 'Copy the code',
          autofocus: true,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 2)));
          },
        ),
      SheetOption(icon: SettingsIcons.downloads, label: 'Share again with today\'s list', onPressed: _busy ? null : () => _run(widget.onExportAgain)),
      if (code != null)
        SheetOption(
          icon: SettingsIcons.trash,
          label: 'Delete this code',
          danger: true,
          onPressed: _busy ? null : () => _run(() => ref.read(favoritesProvider.notifier).deleteExport()),
        ),
    ]);
  }
}

/// A code field and Import.
class _ImportCode extends ConsumerStatefulWidget {
  const _ImportCode({required this.onDone});

  final void Function(String message, {bool error}) onDone;

  @override
  ConsumerState<_ImportCode> createState() => _ImportCodeState();
}

class _ImportCodeState extends ConsumerState<_ImportCode> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final slug = _code.text.trim();
    if (slug.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(favoritesProvider.notifier).importFavorites(slug, merge: true);
      if (mounted) Navigator.of(context).pop();
      widget.onDone('Favorites imported');
    } catch (e) {
      widget.onDone('Failed to import favorites', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, spacing: 6, children: [
      TextField(
        controller: _code,
        autofocus: true,
        enabled: !_busy,
        decoration: const InputDecoration(hintText: 'Code, e.g. abcd.fav', border: OutlineInputBorder()),
        onSubmitted: (_) => _import(),
      ),
      const SizedBox(height: 6),
      SheetOption(icon: SettingsIcons.downloads, label: _busy ? 'Importing' : 'Import', onPressed: _busy ? null : _import),
    ]);
  }
}
