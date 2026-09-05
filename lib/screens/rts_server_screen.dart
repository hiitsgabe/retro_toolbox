import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:roms_downloader/models/rts_folder_model.dart';
import 'package:roms_downloader/providers/rts_server_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/utils/network.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Turns local folders into a catalog other apps consume via New Catalog
/// Source: add folders, tweak how each appears, flip the server on, and share
/// the consoles.json link.
class RtsServerScreen extends ConsumerWidget {
  const RtsServerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rtsServerProvider);
    final notifier = ref.read(rtsServerProvider.notifier);
    final theme = Theme.of(context);
    final addresses = orderAddresses(state.addresses, ref.watch(settingsProvider).preferredLocalIp);
    final host = addresses.isNotEmpty ? addresses.first : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Retro Tools Server')),
      floatingActionButton: state.running
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addFolder(context, ref),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add folder'),
            ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ToolDescription(
            icon: Icons.dns_rounded,
            text: 'Shares folders on this device as a catalog. On another device, open New Catalog '
                'Source and paste the link below — it browses and downloads straight from here. Same network.',
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable server'),
                subtitle: Text(state.running
                    ? 'Sharing ${state.folders.length} folder(s)'
                    : state.folders.isEmpty
                        ? 'Add a folder first'
                        : 'Off'),
                value: state.running,
                onChanged: state.folders.isEmpty && !state.running ? null : (v) => v ? notifier.enable() : notifier.disable(),
              ),
            ),
          ),
          if (!state.running) ...[
            const SizedBox(height: 16),
            TextFormField(
              initialValue: '${state.port}',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true),
              onChanged: (v) {
                final port = int.tryParse(v);
                if (port != null && port > 0 && port < 65536) notifier.setPort(port);
              },
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (state.running && host != null) ...[
            const SizedBox(height: 20),
            _linkCard(context, 'http://$host:${state.port}/consoles.json'),
            const SizedBox(height: 12),
            Center(
              child: Text('Active transfers: ${state.activeTransfers}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Shared folders', style: theme.textTheme.titleSmall),
              const Spacer(),
              Text('${state.folders.length}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          if (state.folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No folders yet. Tap “Add folder”.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ),
          for (var i = 0; i < state.folders.length; i++) _folderCard(context, ref, i, state.folders[i], state.running),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _linkCard(BuildContext context, String url) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catalog link', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace', fontWeight: FontWeight.w600, color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  color: theme.colorScheme.onPrimaryContainer,
                  tooltip: 'Copy link',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 1)));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Paste in New Catalog Source on the other device.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }

  Widget _folderCard(BuildContext context, WidgetRef ref, int index, RtsFolder f, bool locked) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.folder_rounded),
        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                if (f.formats.isEmpty)
                  _chip(theme, 'all files')
                else
                  for (final ext in f.formats) _chip(theme, ext),
                if (f.boxartsUrl != null && f.boxartsUrl!.isNotEmpty) _chip(theme, 'boxart', Icons.image_outlined),
              ],
            ),
          ],
        ),
        trailing: locked
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editFolder(context, ref, index, f)),
                  IconButton(icon: const Icon(Icons.delete_outline, size: 20), onPressed: () => ref.read(rtsServerProvider.notifier).removeFolder(index)),
                ],
              ),
        isThreeLine: true,
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, [IconData? icon]) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: theme.colorScheme.onSecondaryContainer), const SizedBox(width: 3)],
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
          ],
        ),
      );

  Future<void> _addFolder(BuildContext context, WidgetRef ref) async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Pick a folder to share');
    if (path == null || !context.mounted) return;
    final name = p.basename(path);
    final draft = RtsFolder(
      path: path,
      name: name,
      formats: const [],
      boxartsUrl: RtsFolder.libretroBoxarts(name),
      romsSubfolder: name,
    );
    final result = await _showEditSheet(context, draft, isNew: true);
    if (result != null) ref.read(rtsServerProvider.notifier).addFolder(result);
  }

  Future<void> _editFolder(BuildContext context, WidgetRef ref, int index, RtsFolder f) async {
    final result = await _showEditSheet(context, f, isNew: false);
    if (result != null) ref.read(rtsServerProvider.notifier).updateFolder(index, result);
  }

  Future<RtsFolder?> _showEditSheet(BuildContext context, RtsFolder folder, {required bool isNew}) {
    return showModalBottomSheet<RtsFolder>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _FolderEditSheet(folder: folder, isNew: isNew),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.isNew ? 'Add folder' : 'Edit folder', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(widget.folder.path, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'System name', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.videogame_asset)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _formats,
            decoration: const InputDecoration(labelText: 'File formats (blank = all)', hintText: '.zip, .chd', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.filter_alt)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subfolder,
            decoration: const InputDecoration(labelText: 'ROM subfolder', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.folder)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _boxarts,
            decoration: const InputDecoration(labelText: 'Boxart URL (optional)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.image_outlined)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: Text(widget.isNew ? 'Add' : 'Save')),
          ),
        ],
      ),
    );
  }
}
