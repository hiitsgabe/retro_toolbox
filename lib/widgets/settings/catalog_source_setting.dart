import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';

class CatalogSourceSetting extends ConsumerStatefulWidget {
  const CatalogSourceSetting({super.key});

  @override
  ConsumerState<CatalogSourceSetting> createState() => _CatalogSourceSettingState();
}

class _CatalogSourceSettingState extends ConsumerState<CatalogSourceSetting> {
  final _catalogService = CatalogService();
  final _urlController = TextEditingController();
  bool _busy = false;
  bool _hasUserCatalog = false;
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(settingsProvider).catalogSourceUrl;
    if (saved != null) _urlController.text = saved;
    _refreshState();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _refreshState() async {
    final has = await _catalogService.hasUserCatalog();
    if (mounted) setState(() => _hasUserCatalog = has);
  }

  Future<void> _run(Future<void> Function() action, String successMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      await ref.read(appStateProvider.notifier).reloadConsoles();
      await _refreshState();
      if (mounted) setState(() => _showOptions = false);
      _snack(successMsg);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a catalog JSON file',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(null);
    await _run(() => _catalogService.setCatalogFromJson(File(path).readAsStringSync()),
        'Catalog imported.');
  }

  Future<void> _loadUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(url);
    await _run(() => _catalogService.setCatalogFromUrl(url), 'Catalog loaded from URL.');
  }

  Future<void> _reset() async {
    await ref.read(settingsProvider.notifier).setCatalogSourceUrl(null);
    _urlController.clear();
    await _run(() => _catalogService.resetCatalog(), 'Catalog reset to bundled default.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _hasUserCatalog ? Icons.check_circle : Icons.info_outline,
              size: 16,
              color: _hasUserCatalog ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _hasUserCatalog ? 'Using your imported catalog.' : 'Using the bundled catalog (if any).',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Collapse the inputs once a catalog is set; reveal on request.
        if (_hasUserCatalog && !_showOptions)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => setState(() => _showOptions = true),
              icon: const Icon(Icons.sync, size: 16),
              label: const Text('Load new source'),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Catalog URL',
                    hintText: 'https://…/consoles.json',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link),
                  ),
                  onSubmitted: (_) => _loadUrl(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _loadUrl,
                child: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Load'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _importFile,
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Import file'),
              ),
              const Spacer(),
              if (_hasUserCatalog)
                TextButton.icon(
                  onPressed: _busy ? null : _reset,
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('Reset'),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
