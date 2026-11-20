import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/models/console_model.dart';
import 'package:retro_toolbox/models/rts_folder_model.dart';
import 'package:retro_toolbox/providers/rts_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/catalog_service.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/file_browser.dart' show errorReason;
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:retro_toolbox/services/pick.dart';

/// Turns local folders into a catalog other apps load as their catalog source
/// (Settings > Library > Catalog source): add folders, tweak how each appears,
/// flip the server on, and share the consoles.json link.
class RtsServerScreen extends ConsumerStatefulWidget {
  const RtsServerScreen({super.key});

  @override
  ConsumerState<RtsServerScreen> createState() => _RtsServerScreenState();
}

class _RtsServerScreenState extends ConsumerState<RtsServerScreen> with ServerToggle {
  static const _info = InfoButton(
    icon: Icons.dns_rounded,
    title: 'Retro Tools Server',
    text: 'Shares folders on this device as a catalog. On another device, open Settings > Library > Catalog source '
        '(with Games Library & downloads on) and paste the link below. It browses and downloads straight from here. Same network. '
        'Forward my library serves every console in your library, using this device\'s sign-ins; games downloaded through here are kept on this device. '
        'Formats left empty share every file in the folder.',
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rtsServerProvider);
    final notifier = ref.read(rtsServerProvider.notifier);
    final addresses = orderAddresses(state.addresses, ref.watch(settingsProvider).preferredLocalIp);
    final host = state.running ? addresses.firstOrNull : null;
    final pill = serverStateOf(running: state.running, starting: starting, error: state.error);
    final detail = transfersLabel(state.activeTransfers);
    final nothing = state.folders.isEmpty && !state.forwardLibrary;
    final locked = state.running ? lockedWhileRunning : null;
    String urlOf(String ip) => 'http://$ip:${state.port}/consoles.json';

    final hero = host == null
        ? AddressHero(state: pill, address: '', stateDetail: detail, label: 'Catalog link')
        : AddressHero.url(
            urlOf(host),
            state: pill,
            stateDetail: detail,
            otherAddresses: addresses.length - 1,
            onOtherAddresses: () => showOtherAddresses(context, area: AppArea.servers, addresses: [for (final ip in addresses.skip(1)) AddressChoice(urlOf(ip))]),
          );

    return KitScaffold(
      title: 'Retro Tools Server',
      subtitle: 'Share your ROM folders as a catalog',
      icon: Icons.dns_rounded,
      glyph: PixelIcons.rts,
      area: AppArea.servers,
      info: _info,
      body: KitColumns(
        start: [
          hero,
          if (state.error != null && !state.running) StatusPanel.error(line: 'The server did not start: ${errorReason(state.error!)}', details: state.error),
          const KitLabel('On the other device'),
          Steps(steps: [
            'Open Settings > Library > Catalog source',
            Handheld.current ? 'Type the link shown above' : 'Paste or type the link shown above',
          ]),
          if (state.running) ActivityPanel(count: state.activeTransfers, countLabel: detail ?? 'Idle', emptyText: state.activeTransfers > 0 ? 'Downloading from here' : 'No transfers right now'),
          OptionList(children: [PortOption(port: state.port, onChanged: notifier.setPort, lockedReason: locked)]),
        ],
        end: [
          KitLabel(state.folders.isEmpty ? 'Sharing' : 'Sharing ${_plural(state.folders.length, 'folder')}'),
          OptionList(children: [
            OptionToggle(
              title: 'Forward my library',
              subtitle: "Every console, with this device's sign-ins",
              value: state.forwardLibrary,
              onChanged: notifier.setForwardLibrary,
              lockedReason: locked,
            ),
            for (var i = 0; i < state.folders.length; i++) _folderRow(context, i, state.folders[i], locked),
            if (state.folders.isEmpty)
              OptionAction(
                title: 'No folders yet',
                subtitle: 'Add a ROM folder to share it',
                value: 'Add folder',
                onTap: () => _addFolder(context),
                lockedReason: locked,
              ),
          ]),
        ],
      ),
      actionBar: ActionBar(
        primary: serverAction(
          running: state.running,
          starting: starting,
          onToggle: nothing && !state.running ? null : () => toggleServer(running: state.running, start: notifier.enable, stop: notifier.disable),
        ),
        secondary: KitAction('Add folder', state.running ? null : () => _addFolder(context), icon: Icons.create_new_folder_outlined, button: PadButton.x),
        hints: const [KitHint(PadButton.a, 'Edit'), KitHint(PadButton.y, 'Folder menu'), KitHint(PadButton.b, 'Back')],
        summary: nothing && !state.running
            ? 'Add a folder or forward your library first'
            : (state.running ? 'Stop the server to change what is shared' : 'Port ${state.port}'),
      ),
    );
  }

  static String _plural(int n, String word) => n == 1 ? '1 $word' : '$n ${word}s';

  /// A shared folder: A or a tap edits it, Y or a long press offers Edit and
  /// Remove. While the server runs it is shown with the lock.
  Widget _folderRow(BuildContext context, int index, RtsFolder f, String? locked) => Builder(builder: (context) => _folderRowIn(context, index, f, locked));

  Widget _folderRowIn(BuildContext context, int index, RtsFolder f, String? locked) {
    final t = KitType.of(context);
    final chips = [
      if (f.formats.isEmpty) 'all files' else ...f.formats,
      if (f.boxartsUrl != null && f.boxartsUrl!.isNotEmpty) 'boxart',
    ];
    void edit() => _editFolder(context, index, f);
    void menu() => showRowMenu(context, title: f.name, subtitle: f.path, items: [
          RowMenuItem('Edit', locked == null ? edit : null, icon: Icons.edit_outlined, subtitle: locked),
          RowMenuItem('Remove', locked == null ? () => ref.read(rtsServerProvider.notifier).removeFolder(index) : null, icon: Icons.delete_outline, destructive: true),
        ]);
    return RowMenuTarget(
      onMenu: menu,
      child: KitRow(
        onTap: locked == null ? edit : null,
        child: Row(children: [
          Icon(Icons.folder_rounded, size: 20, color: t.k.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              KitRowText(title: f.name, lockedReason: locked),
              PathText(f.path, style: t.subtitle),
              const SizedBox(height: 4),
              Wrap(spacing: 4, runSpacing: 4, children: [for (final c in chips) KitBadge(c)]),
            ]),
          ),
          if (locked == null) ...[const SizedBox(width: 8), Text('Edit', style: t.verb)],
        ]),
      ),
    );
  }

  Future<void> _addFolder(BuildContext context) async {
    final path = await pickDirectory(context, title: 'Pick a folder to share');
    if (path == null || !context.mounted) return;
    final name = p.basename(path);

    // Reuse a matching catalog console's formats/boxart if the folder name lines
    // up (e.g. "psp" → the PSP console), so the user rarely types formats.
    final consoles = await CatalogService().getConsoles();
    final id = CatalogService.consoleId(name);
    Console? match;
    for (final c in consoles.values) {
      if (c.id == id || c.name.toLowerCase() == name.toLowerCase()) {
        match = c;
        break;
      }
    }
    final boxarts = (match?.boxarts is Map && (match!.boxarts as Map)['url'] is String)
        ? (match.boxarts as Map)['url'] as String
        : RtsFolder.libretroBoxarts(name);

    if (!context.mounted) return;
    final draft = RtsFolder(
      path: path,
      name: name,
      formats: match?.gameFilesFormat ?? match?.originalFormat ?? const [],
      boxartsUrl: boxarts,
      romsSubfolder: name,
    );
    final result = await _showEditSheet(context, draft, isNew: true);
    if (result != null) ref.read(rtsServerProvider.notifier).addFolder(result);
  }

  Future<void> _editFolder(BuildContext context, int index, RtsFolder f) async {
    final result = await _showEditSheet(context, f, isNew: false);
    if (result != null) ref.read(rtsServerProvider.notifier).updateFolder(index, result);
  }

  Future<RtsFolder?> _showEditSheet(BuildContext context, RtsFolder folder, {required bool isNew}) {
    return showModalBottomSheet<RtsFolder>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // The sheet is a route of its own: it takes the servers' accent again.
      builder: (context) => KitArea(
        area: AppArea.servers,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: _FolderEditSheet(folder: folder, isNew: isNew),
        ),
      ),
    );
  }
}

class _FolderEditSheet extends StatefulWidget {
  final RtsFolder folder;
  final bool isNew;
  const _FolderEditSheet({required this.folder, required this.isNew});

  @override
  State<_FolderEditSheet> createState() => _FolderEditSheetState();
}

class _FolderEditSheetState extends State<_FolderEditSheet> {
  late final _name = TextEditingController(text: widget.folder.name);
  late final _formats = TextEditingController(text: widget.folder.formats.join(', '));
  late final _subfolder = TextEditingController(text: widget.folder.romsSubfolder);
  late final _boxarts = TextEditingController(text: widget.folder.boxartsUrl ?? '');

  @override
  void dispose() {
    _name.dispose();
    _formats.dispose();
    _subfolder.dispose();
    _boxarts.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final formats = _formats.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).map((e) => e.startsWith('.') ? e : '.$e').toList();
    Navigator.of(context).pop(widget.folder.copyWith(
      name: name,
      formats: formats,
      romsSubfolder: _subfolder.text.trim().isEmpty ? name : _subfolder.text.trim(),
      boxartsUrl: _boxarts.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.isNew ? 'Add folder' : 'Edit folder', style: t.row.copyWith(fontSize: t.size(16))),
          PathText(widget.folder.path, style: t.subtitle),
          const SizedBox(height: 10),
          KitPanel(children: [
            FieldSlot(label: 'System name', controller: _name, icon: Icons.videogame_asset, autofocus: true),
            FieldSlot(label: 'File formats (blank = all)', controller: _formats, hint: '.zip, .chd', icon: Icons.filter_alt),
            FieldSlot(label: 'ROM subfolder', controller: _subfolder, icon: Icons.folder),
            FieldSlot(label: 'Boxart URL (optional)', controller: _boxarts, icon: Icons.image_outlined, keyboardType: TextInputType.url),
          ]),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(widget.isNew ? 'Add' : 'Save')),
        ],
      ),
    );
  }
}
