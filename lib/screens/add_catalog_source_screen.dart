import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/models/game_handler.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/providers/app_state_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Adds a single console/system to the catalog from a URL. Toggle picks the
/// source: an Internet Archive item (id or archive.org URL) or a plain HTTP
/// directory-listing URL. The rest mirrors the console_utilities add flow:
/// name, ROM subfolder, formats, platform, and decompress/extract behaviour.
/// The screen stays after adding, with the result in its status.
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

  /// What is wrong with the link or the name, under that field.
  String? _urlError, _nameError;
  StatusPanel _status = const StatusPanel.hidden();

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

  Future<void> _add() async {
    if (_busy) return;
    final name = _nameController.text.trim();
    final input = _urlController.text.trim();
    String? urlError, nameError;
    if (name.isEmpty) nameError = 'Enter a name.';
    String? url;
    if (input.isEmpty) {
      urlError = 'Enter a URL or item ID.';
    } else if (_isIa) {
      final id = CatalogService.parseIaItemId(input);
      if (id == null) {
        urlError = 'Invalid archive.org item ID or URL.';
      } else {
        url = 'https://archive.org/download/$id/';
      }
    } else if (!input.startsWith('http')) {
      urlError = 'Enter a full http(s) URL.';
    } else {
      url = input;
    }
    setState(() {
      _nameError = nameError;
      _urlError = urlError;
      if (nameError != null || urlError != null) _status = const StatusPanel.hidden();
    });
    if (url == null || nameError != null) return;

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

    setState(() {
      _busy = true;
      _status = StatusPanel.working(items: [WorkItem('Adding $name')]);
    });
    try {
      await CatalogService().addConsole(console);
      await ref.read(appStateProvider.notifier).reloadConsoles();
      if (!mounted) return;
      // The form clears for the next console; the options stay as they were.
      setState(() {
        _status = StatusPanel.done(summary: '"$name" added to the catalog.');
        _urlController.clear();
        _nameController.clear();
        _folderController.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _status = StatusPanel.error(line: 'Could not add "$name"', details: '$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _info = InfoButton(
    icon: Icons.playlist_add,
    title: 'New Catalog Source',
    text: 'Add a single console to your catalog from a URL. Turn on Internet Archive '
        'for an archive.org item (ID or link); otherwise point at a directory-listing URL.\n\n'
        'Original formats are the files the server lists (.zip). Game files formats are what is kept after '
        'decompressing (.bin,.cue). Platform is the Batocera system id (psx), used for metadata.',
  );

  static const _unpack = {
    Decompress.none: ('Keep as downloaded', 'The files are used as they are'),
    Decompress.unzip: ('Unzip', 'Each download is a .zip to extract'),
    Decompress.unrar: ('Unrar', 'Each download is a .rar to extract'),
  };

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();
    return KitScaffold(
      title: 'New Catalog Source',
      subtitle: 'Add a console from a web folder or archive.org',
      icon: Icons.playlist_add,
      glyph: PixelIcons.catalogSource,
      area: AppArea.tools,
      info: _info,
      body: KitColumns(
        start: [
          const KitLabel('Source'),
          KitPanel(children: [
            OptionToggle(title: 'Internet Archive', subtitle: 'Source is an archive.org item', value: _isIa, onChanged: _busy ? null : (v) => setState(() => _isIa = v)),
            FieldSlot(
              label: _isIa ? 'archive.org item ID or URL' : 'Directory listing URL',
              controller: _urlController,
              hint: _isIa ? 'my_item  or  https://archive.org/details/my_item' : 'https://…/roms/snes/',
              icon: Icons.link,
              glyph: PixelIcons.link,
              keyboardType: TextInputType.url,
              enabled: !_busy,
              error: _urlError,
              onChanged: (_) => setState(() => _urlError = null),
            ),
            FieldSlot(
              label: 'Name',
              controller: _nameController,
              hint: 'Super Nintendo',
              icon: Icons.videogame_asset,
              glyph: PixelIcons.consoles,
              enabled: !_busy,
              error: _nameError,
              onChanged: (_) => setState(() => _nameError = null),
            ),
            FieldSlot(
              label: 'ROM subfolder (optional)',
              controller: _folderController,
              hint: 'defaults to the download folder',
              icon: Icons.folder_outlined,
              glyph: PixelIcons.folder,
              enabled: !_busy,
            ),
          ]),
        ],
        end: [
          const KitLabel('Decompress'),
          OptionList(children: [
            for (final MapEntry(key: d, value: (title, subtitle)) in _unpack.entries)
              OptionChoice<Decompress>(
                title: title,
                subtitle: subtitle,
                value: d,
                groupValue: _decompress,
                onSelected: _busy ? null : (v) => setState(() => _decompress = v),
              ),
            OptionExpander(subtitle: 'Formats, platform, extract contents', children: [
              FieldSlot(label: 'Original formats', controller: _formatsController, hint: '.zip,.chd', icon: Icons.filter_alt_outlined, enabled: !_busy),
              FieldSlot(
                label: 'Game files formats (optional)',
                controller: _gameFormatsController,
                hint: '.bin,.cue, kept after decompressing',
                icon: Icons.description_outlined,
                enabled: !_busy,
              ),
              FieldSlot(label: 'Platform (optional)', controller: _platformController, hint: 'Batocera system id, e.g. psx', icon: Icons.sports_esports_outlined, enabled: !_busy),
              OptionToggle(
                title: 'Extract contents',
                subtitle: 'Into the console folder, not a folder per game',
                value: _extractContents,
                onChanged: _busy ? null : (v) => setState(() => _extractContents = v),
              ),
            ]),
          ]),
          _status,
        ],
      ),
      actionBar: ActionBar(
        primary: KitAction('Add to catalog', _busy ? null : _add, icon: Icons.add),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: name.isEmpty ? 'Name the console' : 'Add $name',
      ),
    );
  }
}
