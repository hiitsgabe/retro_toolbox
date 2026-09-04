import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:roms_downloader/providers/smb_provider.dart';
import 'package:roms_downloader/services/smb_service.dart';
import 'package:roms_downloader/widgets/file_browser.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Connects to an SMB/Samba share on the local network to browse it (Finder-
/// style), download or upload files, zip a selection, or delete files.
class SmbScreen extends ConsumerStatefulWidget {
  const SmbScreen({super.key});

  @override
  ConsumerState<SmbScreen> createState() => _SmbScreenState();
}

class _SmbScreenState extends ConsumerState<SmbScreen> {
  final _host = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _domain = TextEditingController();
  final _advanced = ExpansibleController();
  bool _prefilled = false;

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    _domain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smbProvider);
    final notifier = ref.read(smbProvider.notifier);

    if (!_prefilled && !state.connected && state.host.isNotEmpty) {
      _prefilled = true;
      _host.text = state.host;
      _user.text = state.username;
      _domain.text = state.domain;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMB Share'),
        actions: [
          if (state.connected)
            IconButton(icon: const Icon(Icons.logout), tooltip: 'Disconnect', onPressed: () => notifier.disconnect()),
        ],
      ),
      body: state.connected ? _browser(context, state, notifier) : _connectForm(context, state, notifier),
      floatingActionButton: state.connected && !state.atRoot && state.transfer == null && state.selected.isEmpty
          ? FloatingActionButton.extended(onPressed: () => notifier.uploadPick(), icon: const Icon(Icons.upload_file), label: const Text('Upload'))
          : null,
    );
  }

  // ---- Connect / scan ------------------------------------------------------

  Widget _connectForm(BuildContext context, SmbState state, SmbNotifier notifier) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ToolDescription(
          icon: Icons.folder_shared_rounded,
          text: 'Connect to a Samba/SMB share on your network to browse it, download files into the app, and upload files to it. Both devices must be on the same network.',
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: state.scanning ? null : () => notifier.scan(),
            icon: state.scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_find),
            label: Text(state.scanning ? 'Scanning the network…' : 'Scan network', style: const TextStyle(fontSize: 16)),
          ),
        ),
        if (state.discovered.isNotEmpty) ...[
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text('FOUND ON YOUR NETWORK',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, letterSpacing: 1.2)),
          ),
          for (final h in state.discovered) _hostTile(context, h),
        ] else if (!state.scanning) ...[
          const SizedBox(height: 16),
          Center(
            child: Text('Scan to find SMB hosts, or open Advanced to enter one.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: 16),
          Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 20),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ExpansionTile(
            controller: _advanced,
            shape: const Border(),
            leading: const Icon(Icons.tune),
            title: const Text('Advanced', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Enter host and credentials manually'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [_manualFields(context, state, notifier)],
          ),
        ),
      ],
    );
  }

  Widget _hostTile(BuildContext context, SmbHost h) {
    final theme = Theme.of(context);
    final hasName = h.name != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            _host.text = h.ip;
            setState(() {});
            _advanced.expand();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.computer, color: theme.colorScheme.onPrimaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(h.label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(hasName ? '${h.ip} · tap to connect' : 'tap to connect',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _manualFields(BuildContext context, SmbState state, SmbNotifier notifier) {
    final theme = Theme.of(context);
    return Column(
      children: [
        TextField(
          controller: _host,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Host / IP', hintText: '192.168.1.10', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: _domain, decoration: const InputDecoration(labelText: 'Domain (optional)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.busy || _host.text.trim().isEmpty
                ? null
                : () => notifier.connect(host: _host.text.trim(), username: _user.text.trim(), password: _pass.text, domain: _domain.text.trim()),
            icon: state.busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: const Text('Connect'),
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  // ---- Browser -------------------------------------------------------------

  Widget _browser(BuildContext context, SmbState state, SmbNotifier notifier) {
    final t = state.transfer;
    return FileBrowserView(
      locationLabel: state.atRoot ? 'Shares' : state.path,
      canGoUp: !state.atRoot,
      busy: state.busy,
      error: state.error,
      items: [
        for (final e in state.entries) BrowserItem(id: e.path, name: e.name, isDir: state.atRoot || e.isDirectory(), size: e.size),
      ],
      selectedIds: state.selected,
      transfer: t == null ? null : BrowserTransfer(name: t.name, done: t.done, total: t.total, upload: t.upload),
      selectable: !state.atRoot,
      onUp: () => notifier.goUp(),
      onRefresh: () => notifier.refresh(),
      onOpen: (item) => notifier.open(_entry(state, item.id)),
      onToggleSelect: (item) => notifier.toggleSelect(_entry(state, item.id)),
      onClearSelection: () => notifier.clearSelection(),
      onDownload: () => _pickDirThen((d) => notifier.downloadSelected(d)),
      onZip: () => _pickDirThen((d) => notifier.zipSelected(d)),
      onDelete: () => _confirmDelete(context, state, notifier),
      selectedFileCount: state.selectedFiles.length,
    );
  }

  SmbFile _entry(SmbState state, String id) => state.entries.firstWhere((e) => e.path == id);

  Future<void> _pickDirThen(Future<void> Function(String dir) run) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose output folder');
    if (dir != null) await run(dir);
  }

  Future<void> _confirmDelete(BuildContext context, SmbState state, SmbNotifier notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${state.selected.length} item(s) from the share? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await notifier.deleteSelected();
  }
}
