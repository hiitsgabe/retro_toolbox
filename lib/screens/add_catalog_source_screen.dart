import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Adds a single console/system to the catalog from a URL. Toggle picks the
/// source: an Internet Archive item (id or archive.org URL) or a plain HTTP
/// directory-listing URL. The rest mirrors the console_utilities add flow —
/// name, ROM subfolder, formats, platform, and decompress/extract behaviour.
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
  final _gameFormatsController = TextEditingController();
  final _platformController = TextEditingController();
  bool _isIa = false;
  Decompress _decompress = Decompress.unzip;
  bool _extractContents = true;
  bool _busy = false;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    _folderController.dispose();
    _formatsController.dispose();
    _gameFormatsController.dispose();
    _platformController.dispose();
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

    List<String> split(TextEditingController c) => c.text.split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
    final formats = split(_formatsController);
    final gameFormats = split(_gameFormatsController);
    final platform = _platformController.text.trim();
    final folder = _folderController.text.trim();

    final console = Console(
      id: CatalogService.consoleId(name),
      name: name,
      urls: [url],
      platform: platform.isEmpty ? null : platform,
      originalFormat: formats.isEmpty ? null : formats,
      gameFilesFormat: gameFormats.isEmpty ? null : gameFormats,
      romsFolder: folder.isEmpty ? null : folder,
      decompress: _decompress,
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
    return Actions(
      actions: {
        // Start == "Add to catalog".
        if (!_busy) PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(onInvoke: (_) => _add()),
      },
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
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
                labelText: 'Original formats',
                hintText: '.zip,.chd',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_alt),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Decompress>(
              initialValue: _decompress,
              decoration: const InputDecoration(
                labelText: 'Decompress',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.unarchive),
              ),
              items: [for (final d in Decompress.values) DropdownMenuItem(value: d, child: Text(d.name))],
              onChanged: _busy ? null : (v) => setState(() => _decompress = v ?? Decompress.none),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _gameFormatsController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Game files formats (optional)',
                hintText: '.bin,.cue — kept after decompressing',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.description),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _platformController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Platform (optional)',
                hintText: 'Batocera system id, e.g. psx',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.sports_esports),
              ),
            ),
            const SizedBox(height: 8),
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
