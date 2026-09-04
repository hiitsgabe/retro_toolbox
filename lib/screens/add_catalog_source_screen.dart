import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:roms_downloader/models/console_model.dart';
import 'package:roms_downloader/providers/app_state_provider.dart';
import 'package:roms_downloader/services/catalog_service.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Adds a single console/system to the catalog from a URL. Toggle picks the
/// source: an Internet Archive item (id or archive.org URL) or a plain HTTP
/// directory-listing URL. The rest mirrors the console_utilities add flow —
/// name, ROM subfolder, file formats, and unzip/extract behaviour.
class AddCatalogSourceScreen extends ConsumerStatefulWidget {
  const AddCatalogSourceScreen({super.key});

  @override
  ConsumerState<AddCatalogSourceScreen> createState() => _AddCatalogSourceScreenState();
}

class _AddCatalogSourceScreenState extends ConsumerState<AddCatalogSourceScreen> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _folderController = TextEditingController();
  final _formatsController = TextEditingController(text: '.zip');
  bool _isIa = false;
  bool _shouldUnzip = true;
  bool _extractContents = true;
  bool _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _folderController.dispose();
    _formatsController.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _add() async {
    final name = _nameController.text.trim();
    final input = _urlController.text.trim();
    if (name.isEmpty) return _snack('Enter a name.');
    if (input.isEmpty) return _snack('Enter a URL or item ID.');

    final String url;
    if (_isIa) {
      final id = CatalogService.parseIaItemId(input);
      if (id == null) return _snack('Invalid archive.org item ID or URL.');
      url = 'https://archive.org/download/$id/';
    } else {
      if (!input.startsWith('http')) return _snack('Enter a full http(s) URL.');
      url = input;
    }

    final formats = _formatsController.text.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
    final folder = _folderController.text.trim();

    final console = Console(
      id: CatalogService.consoleId(name),
      name: name,
      urls: [url],
      fileFormat: formats.isEmpty ? null : formats,
      romsFolder: folder.isEmpty ? null : folder,
      shouldUnzip: _shouldUnzip,
      extractContents: _extractContents,
      added: true,
    );

    setState(() => _busy = true);
    try {
      await CatalogService().addConsole(console);
      await ref.read(appStateProvider.notifier).reloadConsoles();
      _snack('"$name" added to the catalog.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Catalog Source')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const ToolDescription(
              icon: Icons.playlist_add,
              text: 'Add a single console to your catalog from a URL. Turn on Internet Archive '
                  'for an archive.org item (ID or link); otherwise point at a directory-listing URL.',
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Internet Archive'),
              subtitle: const Text('Source is an archive.org item'),
              value: _isIa,
              onChanged: _busy ? null : (v) => setState(() => _isIa = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: _isIa ? 'archive.org item ID or URL' : 'Directory listing URL',
                hintText: _isIa ? 'my_item  or  https://archive.org/details/my_item' : 'https://…/roms/snes/',
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Name',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.videogame_asset),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _folderController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'ROM subfolder (optional)',
                hintText: 'defaults to the download folder',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _formatsController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'File formats',
                hintText: '.zip,.chd',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_alt),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Unzip after download'),
              value: _shouldUnzip,
              onChanged: _busy ? null : (v) => setState(() => _shouldUnzip = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Extract contents'),
              value: _extractContents,
              onChanged: _busy ? null : (v) => setState(() => _extractContents = v),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('Add to catalog'),
            ),
          ],
        ),
      ),
    );
  }
}
