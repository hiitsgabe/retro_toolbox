import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ftpconnect/ftpconnect.dart';

import 'package:roms_downloader/providers/ftp_provider.dart';
import 'package:roms_downloader/widgets/file_browser.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// FTP with two modes: a client that browses a remote server (same Finder-style
/// browser as SMB), and a server that shares a local folder over the LAN.
class FtpScreen extends ConsumerStatefulWidget {
  const FtpScreen({super.key});

  @override
  ConsumerState<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends ConsumerState<FtpScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _srvPort = TextEditingController();
  final _srvAdvanced = ExpansibleController();
  bool _prefilled = false;
  bool _srvPrefilled = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    _srvPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ftpProvider);
    final notifier = ref.read(ftpProvider.notifier);

    if (!_prefilled && !state.connected && (state.host.isNotEmpty || state.port != 21)) {
      _prefilled = true;
      _host.text = state.host;
      _port.text = '${state.port}';
      _user.text = state.username;
    }

    final inClient = state.mode == FtpMode.client;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FTP'),
        actions: [
          if (inClient && state.connected)
            IconButton(icon: const Icon(Icons.logout), tooltip: 'Disconnect', onPressed: () => notifier.disconnect()),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<FtpMode>(
              segments: const [
                ButtonSegment(value: FtpMode.client, label: Text('Client'), icon: Icon(Icons.download)),
                ButtonSegment(value: FtpMode.server, label: Text('Server'), icon: Icon(Icons.dns)),
              ],
              selected: {state.mode},
              onSelectionChanged: (s) => notifier.setMode(s.first),
            ),
          ),
          Expanded(
            child: inClient
                ? (state.connected ? _browser(context, state, notifier) : _clientForm(context, state, notifier))
                : _serverView(context, state, notifier),
          ),
        ],
      ),
      floatingActionButton: inClient && state.connected && state.transfer == null && state.selected.isEmpty
          ? FloatingActionButton.extended(onPressed: () => notifier.uploadPick(), icon: const Icon(Icons.upload_file), label: const Text('Upload'))
          : null,
    );
  }

  // ---- Client --------------------------------------------------------------

  Widget _clientForm(BuildContext context, FtpState state, FtpNotifier notifier) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ToolDescription(
          icon: Icons.cloud_download_rounded,
          text: 'Connect to an FTP server on your network to browse it, download files into the app, and upload files to it.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _host,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Host / IP', hintText: '192.168.1.10', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _port,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Port', hintText: '21', border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(controller: _user, decoration: const InputDecoration(labelText: 'Username (blank = anonymous)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 12),
        TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), isDense: true)),
        if (state.error != null) ...[
          const SizedBox(height: 16),
          Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.busy || _host.text.trim().isEmpty
                ? null
                : () => notifier.connect(
                      host: _host.text.trim(),
                      port: int.tryParse(_port.text.trim()) ?? 21,
                      username: _user.text.trim(),
                      password: _pass.text,
                    ),
            icon: state.busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login),
            label: const Text('Connect'),
          ),
        ),
      ],
    );
  }

  Widget _browser(BuildContext context, FtpState state, FtpNotifier notifier) {
    final t = state.transfer;
    return FileBrowserView(
      locationLabel: state.path,
      canGoUp: state.path != '/' && state.path.isNotEmpty,
      busy: state.busy,
      error: state.error,
      items: [
        for (final e in state.entries) BrowserItem(id: e.name, name: e.name, isDir: e.type == FTPEntryType.dir, size: e.size ?? 0),
      ],
      selectedIds: state.selected,
      transfer: t == null ? null : BrowserTransfer(name: t.name, done: t.done, total: t.total, upload: t.upload),
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

  FTPEntry _entry(FtpState state, String id) => state.entries.firstWhere((e) => e.name == id);

  Future<void> _pickDirThen(Future<void> Function(String dir) run) async {
    final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose output folder');
    if (dir != null) await run(dir);
  }

  Future<void> _confirmDelete(BuildContext context, FtpState state, FtpNotifier notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${state.selected.length} item(s) from the server? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await notifier.deleteSelected();
  }

  // ---- Server --------------------------------------------------------------

  Widget _serverView(BuildContext context, FtpState state, FtpNotifier notifier) {
    final theme = Theme.of(context);
    final host = state.serverAddresses.isNotEmpty ? state.serverAddresses.first : null;
    final running = state.serverRunning;

    if (!_srvPrefilled) {
      _srvPrefilled = true;
      _srvPort.text = '${state.serverPort}';
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const ToolDescription(
          icon: Icons.dns_rounded,
          text: 'Share a folder over FTP so other devices on your network can browse, download, and upload files to it.',
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.folder),
            title: Text(state.serverDir.isEmpty ? 'No folder selected' : state.serverDir, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Folder to share'),
            trailing: TextButton(onPressed: running ? null : () => notifier.pickServerDir(), child: const Text('Choose')),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ExpansionTile(
            controller: _srvAdvanced,
            shape: const Border(),
            leading: const Icon(Icons.tune),
            title: const Text('Advanced', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Port ${state.serverPort}${state.serverReadOnly ? ' · read-only' : ''}'),
            childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            children: [
              TextField(
                controller: _srvPort,
                enabled: !running,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder(), isDense: true, helperText: 'Use a port > 1024 (21 needs root)'),
                onChanged: (v) {
                  final port = int.tryParse(v);
                  if (port != null && port > 0 && port < 65536) notifier.setServerPort(port);
                },
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Read-only'),
                subtitle: const Text('Block uploads and deletes from clients'),
                value: state.serverReadOnly,
                onChanged: running ? null : (v) => notifier.setServerReadOnly(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              backgroundColor: running ? theme.colorScheme.errorContainer : null,
              foregroundColor: running ? theme.colorScheme.onErrorContainer : null,
            ),
            onPressed: () => running ? notifier.stopServer() : notifier.startServer(),
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
            label: Text(running ? 'Stop server' : 'Start server', style: const TextStyle(fontSize: 16)),
          ),
        ),
        if (state.serverError != null) ...[
          const SizedBox(height: 16),
          Text(state.serverError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        if (running && host != null) ...[
          const SizedBox(height: 24),
          _connectionCard(context, host, state.serverPort),
        ],
      ],
    );
  }

  Widget _connectionCard(BuildContext context, String host, int port) {
    final theme = Theme.of(context);
    final url = 'ftp://$host:$port';
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Connect from another device', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onPrimaryContainer)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SelectableText(url,
                      style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace', fontWeight: FontWeight.w600, color: theme.colorScheme.onPrimaryContainer)),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  color: theme.colorScheme.onPrimaryContainer,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: url));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
