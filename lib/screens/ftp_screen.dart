import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ftpconnect/ftpconnect.dart';

import 'package:retro_toolbox/providers/ftp_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/file_browser.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:retro_toolbox/services/pick.dart';

/// FTP with two modes: a client that browses a remote server (same Finder-style
/// browser as SMB), and a server that shares a local folder over the LAN.
class FtpScreen extends ConsumerStatefulWidget {
  const FtpScreen({super.key});

  @override
  ConsumerState<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends ConsumerState<FtpScreen> with ServerToggle {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '21');
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _prefilled = false;

  static const _clientInfo = InfoButton(
    icon: Icons.cloud_download_rounded,
    title: 'FTP',
    text: 'Connect to an FTP server on your network to browse it, download files into the app, and upload files to it. '
        'Downloads and zips run in the background, so you can leave this screen.',
  );
  static const _serverInfo = InfoButton(
    icon: Icons.dns_rounded,
    title: 'FTP',
    text: 'Share a folder over FTP so other devices on your network can browse, download, and upload files to it. '
        'Any FTP app works. Read-only blocks uploads and deletes. Ports under 1024 need root.',
  );

  @override
  void initState() {
    super.initState();
    // A running server (restored at boot, or left on) is what the user came
    // back to, so do not hide it behind the client form.
    Future.microtask(() {
      if (mounted && ref.read(ftpProvider).serverRunning) ref.read(ftpProvider.notifier).setMode(FtpMode.server);
    });
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _connect(FtpNotifier notifier) => notifier.connect(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 21,
        username: _user.text.trim(),
        password: _pass.text,
      );

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
    final browsing = inClient && state.connected;
    final ActionBar bar;
    if (!inClient) {
      bar = _serverBar(state, notifier);
    } else if (browsing) {
      bar = ActionBar(
        primary: KitAction('Upload here', state.transfer == null && state.selected.isEmpty ? () => _upload(notifier) : null, icon: Icons.upload_file),
        secondary: KitAction('Disconnect', () => notifier.disconnect(), icon: Icons.logout),
        hints: const [KitHint(PadButton.a, 'Open'), KitHint(PadButton.x, 'Select'), KitHint(PadButton.y, 'Actions'), KitHint(PadButton.b, 'Up')],
      );
    } else {
      bar = ActionBar(
        primary: KitAction(state.busy ? 'Connecting…' : 'Connect', state.busy || _host.text.trim().isEmpty ? null : () => _connect(notifier), icon: Icons.login),
        hints: const [KitHint(PadButton.a, 'Type'), KitHint(PadButton.b, 'Back')],
        summary: _host.text.trim().isEmpty ? 'Type the server address first' : null,
      );
    }
    final stacked = kitStacked(context);
    final modes = _modes(state, notifier);
    final content = inClient ? (state.connected ? _browser(context, state, notifier) : _clientForm(context, state, notifier)) : _serverView(context, state, notifier);
    return PopScope(
        // Back goes up a folder; only the FTP root (or server mode) leaves.
        canPop: (!browsing || state.path == '/' || state.path.isEmpty) && state.selected.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || state.busy) return;
          // Back first clears a selection, then goes up.
          state.selected.isNotEmpty ? notifier.clearSelection() : notifier.goUp();
        },
        child: KitScaffold(
          title: 'FTP',
          subtitle: !inClient
              ? 'Share a folder with your PC over FTP'
              : (browsing ? 'Connected to ${state.host}' : 'Browse and copy files on an FTP server'),
          icon: inClient ? Icons.cloud_download_rounded : Icons.dns_rounded,
          glyph: PixelIcons.ftp,
          area: AppArea.servers,
          info: inClient ? _clientInfo : _serverInfo,
          // Both modes stay one tile; the switch sits in the header so the
          // body is all the mode's own, or over the body where the header is
          // too narrow for it and the subtitle.
          actions: [if (!stacked) ...[const SizedBox(width: 6), modes]],
          actionBar: bar,
          body: stacked
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(padding: const EdgeInsets.only(top: 4, bottom: kitGap), child: modes),
                  Expanded(child: content),
                ])
              : content,
        ));
  }

  Widget _modes(FtpState state, FtpNotifier notifier) => SegmentedButton<FtpMode>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        segments: const [
          ButtonSegment(value: FtpMode.client, label: Text('Client')),
          ButtonSegment(value: FtpMode.server, label: Text('Server')),
        ],
        selected: {state.mode},
        onSelectionChanged: (s) => notifier.setMode(s.first),
      );

  // ---- Client --------------------------------------------------------------

  Widget _clientForm(BuildContext context, FtpState state, FtpNotifier notifier) {
    return KitColumns(
      start: [
        const KitLabel('Server'),
        KitPanel(children: [
          FieldSlot(label: 'Host / IP', controller: _host, hint: '192.168.1.10', icon: Icons.dns_outlined, keyboardType: TextInputType.url, onChanged: (_) => setState(() {})),
          FieldSlot(
            label: 'Port',
            controller: _port,
            hint: '21',
            icon: Icons.settings_ethernet,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ]),
        if (state.error != null) StatusPanel.error(line: errorReason(state.error!), details: errorReason(state.error!) == state.error ? null : state.error),
      ],
      end: [
        const KitLabel('Login'),
        KitPanel(children: [
          FieldSlot(label: 'Username', controller: _user, hint: 'Leave empty for anonymous', icon: Icons.person_outline),
          FieldSlot(label: 'Password', controller: _pass, icon: Icons.key_outlined, obscureText: true, onSubmitted: (_) {
            if (!state.busy && _host.text.trim().isNotEmpty) _connect(notifier);
          }),
        ]),
      ],
    );
  }

  Widget _browser(BuildContext context, FtpState state, FtpNotifier notifier) {
    final t = state.transfer;
    return FileBrowserView(
      locationLabel: state.path,
      crumbs: remoteCrumbs('/', state.path, (p) => notifier.goTo(p.isEmpty ? '/' : p)),
      busy: state.busy,
      error: state.error,
      items: [
        for (final e in state.entries) BrowserItem(id: e.name, name: e.name, isDir: e.type == FTPEntryType.dir, size: e.size ?? 0),
      ],
      selectedIds: state.selected,
      transfer: t == null ? null : BrowserTransfer(name: t.name, done: t.done, total: t.total, upload: t.upload),
      queuedSource: 'ftp',
      onRefresh: () => notifier.refresh(),
      onOpen: (item) => notifier.open(_entry(state, item.id)),
      onToggleSelect: (item) => notifier.toggleSelect(_entry(state, item.id)),
      onClearSelection: () => notifier.clearSelection(),
      // Both run as background tasks (task manager + notification), so the
      // transfer survives leaving this screen or locking the device.
      onDownload: () => _pickDirThen((d) async {
        final label = notifier.selectionLabel();
        TaskQueueService.enqueueTransfer(ref, context, source: 'ftp', title: 'Download $label', verb: 'Downloading', label: label, run: notifier.downloadJob(d));
      }),
      onZip: () => _pickDirThen((d) async {
        final label = notifier.selectionLabel();
        TaskQueueService.enqueueTransfer(ref, context, source: 'ftp', title: 'Zip $label', verb: 'Downloading and zipping', label: label, run: notifier.zipJob(d));
      }),
      onDelete: () => _confirmDelete(context, state, notifier),
      extraActions: () => [
        BrowserAction(icon: Icons.upload_file, label: 'Upload', onPressed: state.transfer == null && state.selected.isEmpty ? () => _upload(notifier) : null),
      ],
    );
  }

  FTPEntry _entry(FtpState state, String id) => state.entries.firstWhere((e) => e.name == id);

  Future<void> _upload(FtpNotifier notifier) async {
    final local = await pickFile(context, title: 'Select a file to upload');
    if (local != null && mounted) await notifier.uploadFile(local);
  }

  Future<void> _pickDirThen(Future<void> Function(String dir) run) async {
    final dir = await pickDirectory(context, title: 'Choose output folder');
    if (dir != null && mounted) await run(dir);
  }

  Future<void> _confirmDelete(BuildContext context, FtpState state, FtpNotifier notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${state.selected.length} item(s) from the server? This cannot be undone.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await notifier.deleteSelected();
  }

  // ---- Server --------------------------------------------------------------

  ActionBar _serverBar(FtpState state, FtpNotifier notifier) {
    final running = state.serverRunning;
    final noDir = state.serverDir.isEmpty;
    return ActionBar(
      primary: serverAction(
        running: running,
        starting: starting,
        onToggle: noDir && !running ? null : () => toggleServer(running: running, start: notifier.startServer, stop: notifier.stopServer),
      ),
      hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
      summary: noDir && !running ? 'Choose a folder to share first' : (running ? 'Sharing on port ${state.serverPort}' : 'Port ${state.serverPort}'),
    );
  }

  Widget _serverView(BuildContext context, FtpState state, FtpNotifier notifier) {
    final addresses = orderAddresses(state.serverAddresses, ref.watch(settingsProvider).preferredLocalIp);
    final running = state.serverRunning;
    final host = running ? addresses.firstOrNull : null;
    final pill = serverStateOf(running: running, starting: starting, error: state.serverError);
    final locked = running ? lockedWhileRunning : null;
    String urlOf(String ip) => 'ftp://$ip:${state.serverPort}';

    return KitColumns(
      start: [
        if (host == null)
          AddressHero(state: pill, address: '')
        else
          AddressHero.url(
            urlOf(host),
            state: pill,
            otherAddresses: addresses.length - 1,
            onOtherAddresses: () => showOtherAddresses(context, area: AppArea.servers, addresses: [for (final ip in addresses.skip(1)) AddressChoice(urlOf(ip))]),
          ),
        if (state.serverError != null) StatusPanel.error(line: 'The server did not start: ${errorReason(state.serverError!)}', details: state.serverError),
        KitPanel(children: [
          Slot(
            label: 'Sharing',
            folder: true,
            path: state.serverDir.isEmpty ? null : state.serverDir,
            emptyText: 'Choose a folder to share',
            lockedReason: locked,
            onPick: () async {
              final dir = await pickDirectory(context, title: 'Choose folder to share');
              if (dir != null) await notifier.setServerDir(dir);
            },
          ),
        ]),
        OptionList(children: [
          PortOption(port: state.serverPort, onChanged: notifier.setServerPort, lockedReason: locked, message: 'Use a port above 1024 (21 needs root)'),
          OptionToggle(
            title: 'Read-only',
            subtitle: 'Block uploads and deletes from clients',
            value: state.serverReadOnly,
            onChanged: notifier.setServerReadOnly,
            lockedReason: locked,
          ),
        ]),
      ],
      end: [
        const KitLabel('On the other device'),
        Steps(steps: [
          'Open the address in an FTP app or a file manager',
          if (state.serverReadOnly) 'Read-only: it can browse and download, not upload or delete',
          'Both devices on the same Wi-Fi',
        ]),
      ],
    );
  }
}
