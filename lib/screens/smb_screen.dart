import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smb_connect/smb_connect.dart';

import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/smb_provider.dart';
import 'package:retro_toolbox/services/smb_service.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/file_browser.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:retro_toolbox/services/pick.dart';

/// Connects to an SMB/Samba share on the local network to browse it (Finder-
/// style), download or upload files, zip a selection, or delete files.
class SmbScreen extends ConsumerStatefulWidget {
  const SmbScreen({super.key});

  @override
  ConsumerState<SmbScreen> createState() => _SmbScreenState();
}

class _SmbScreenState extends ConsumerState<SmbScreen> {
  /// The address sheet is up: the error shows there, not twice.
  bool _sheetOpen = false;

  static const _info = InfoButton(
    icon: Icons.folder_shared_rounded,
    title: 'SMB Share',
    text: 'Connect to a Samba/SMB share on your network to browse it, download files into the app, and upload files to it. Both devices must be on the same network. '
        'Works with Windows shared folders, Samba and most NAS boxes. Downloads and zips keep running if you leave.',
  );

  /// The address sheet, filled with [host] (else the last one) and the saved
  /// user and domain.
  Future<void> _enterAddress({String? host}) async {
    final state = ref.read(smbProvider);
    setState(() => _sheetOpen = true);
    try {
      await showKitSheet<void>(
        context,
        area: AppArea.servers,
        title: 'Connect to a share',
        subtitle: 'A PC or NAS on this network',
        builder: (_) => _ConnectForm(host: host ?? state.host, user: state.username, domain: state.domain),
      );
    } finally {
      if (mounted) setState(() => _sheetOpen = false);
    }
  }

  // Tapping a found host connects right away; only a refused login falls back
  // to the address sheet, with the host filled in.
  Future<void> _connectTo(SmbHost h, SmbNotifier notifier) async {
    if (await notifier.connectToHost(h.ip) || !mounted) return;
    await _enterAddress(host: h.ip);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smbProvider);
    final notifier = ref.read(smbProvider.notifier);

    final ActionBar bar;
    if (state.connected) {
      bar = ActionBar(
        primary: KitAction('Upload here', state.transfer == null && !state.atRoot && state.selected.isEmpty ? () => _upload(notifier) : null, icon: Icons.upload_file),
        secondary: KitAction('Disconnect', () => notifier.disconnect(), icon: Icons.logout),
        hints: const [KitHint(PadButton.a, 'Open'), KitHint(PadButton.x, 'Select'), KitHint(PadButton.y, 'Actions'), KitHint(PadButton.b, 'Up')],
        summary: state.atRoot ? 'Open a share first' : null,
      );
    } else {
      bar = ActionBar(
        primary: KitAction(state.scanning ? 'Scanning…' : (state.discovered.isEmpty ? 'Scan network' : 'Scan again'), state.scanning ? null : () => notifier.scan(), icon: Icons.wifi_find),
        secondary: KitAction('Enter address', state.busy ? null : () => _enterAddress(), icon: Icons.edit_outlined, button: PadButton.y),
        hints: const [KitHint(PadButton.a, 'Connect'), KitHint(PadButton.b, 'Back')],
      );
    }

    return PopScope(
        // Back goes up a folder; only the shares root (or the connect form) leaves.
        canPop: (!state.connected || state.atRoot) && state.selected.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || state.busy) return;
          // Back first clears a selection, then goes up.
          state.selected.isNotEmpty ? notifier.clearSelection() : notifier.goUp();
        },
        child: KitScaffold(
          title: 'SMB Share',
          subtitle: state.connected ? 'Connected to ${state.host}' : 'Browse and copy files on a PC or NAS share',
          icon: Icons.folder_shared_rounded,
          glyph: PixelIcons.smb,
          area: AppArea.servers,
          info: _info,
          actionBar: bar,
          body: state.connected ? _browser(context, state, notifier) : _connectForm(context, state, notifier),
        ));
  }

  // ---- Connect / scan ------------------------------------------------------

  Widget _connectForm(BuildContext context, SmbState state, SmbNotifier notifier) {
    final t = KitType.of(context);
    final pad = ref.watch(inputModeProvider) == InputMode.gamepad;
    return KitColumns(
      start: [
        const KitLabel('On your network'),
        KitPanel(children: [
          if (state.scanning)
            Padding(
              key: const ValueKey('smb-scanning'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Scanning the network…', style: t.row),
                const SizedBox(height: 6),
                const LinearProgressIndicator(minHeight: 3),
              ]),
            ),
          for (final h in state.discovered) _hostRow(context, h, state.busy ? null : () => _connectTo(h, notifier)),
          if (state.discovered.isEmpty && !state.scanning)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Text('Scan to find SMB hosts, or enter an address.', style: t.body.copyWith(color: t.muted)),
            ),
          OptionAction(title: 'Enter address', subtitle: 'Type the host, user and password', onTap: state.busy ? null : () => _enterAddress()),
        ]),
        // The address sheet shows the error itself while it is up.
        if (state.error != null && !_sheetOpen) StatusPanel.error(line: errorReason(state.error!), details: errorReason(state.error!) == state.error ? null : state.error),
      ],
      end: [
        const KitLabel('How to connect'),
        Steps(steps: [
          '${pad ? 'Press A on' : 'Tap'} a PC or NAS to connect',
          'A user and password are asked only when the share needs them',
          'Both devices on the same Wi-Fi',
        ]),
      ],
    );
  }

  Widget _hostRow(BuildContext context, SmbHost h, VoidCallback? onTap) => Builder(builder: (context) => _hostRowIn(context, h, onTap));

  Widget _hostRowIn(BuildContext context, SmbHost h, VoidCallback? onTap) {
    final t = KitType.of(context);
    return KitRow(
      onTap: onTap,
      child: Row(children: [
        Icon(Icons.computer, size: 22, color: t.k.accent),
        const SizedBox(width: 12),
        Expanded(child: KitRowText(title: h.label, subtitle: h.name != null ? h.ip : null)),
        Text('Connect', style: t.verb),
      ]),
    );
  }

  // ---- Browser -------------------------------------------------------------

  Widget _browser(BuildContext context, SmbState state, SmbNotifier notifier) {
    final t = state.transfer;
    return FileBrowserView(
      locationLabel: state.atRoot ? 'Shares' : state.path,
      crumbs: remoteCrumbs('Shares', state.path, notifier.goTo),
      busy: state.busy,
      error: state.error,
      items: [
        for (final e in state.entries) BrowserItem(id: e.path, name: e.name, isDir: state.atRoot || e.isDirectory(), size: e.size),
      ],
      selectedIds: state.selected,
      transfer: t == null ? null : BrowserTransfer(name: t.name, done: t.done, total: t.total, upload: t.upload),
      queuedSource: 'smb',
      selectable: !state.atRoot,
      emptyLine: state.atRoot ? 'No shares on this host' : 'This folder is empty',
      onRefresh: () => notifier.refresh(),
      onOpen: (item) => notifier.open(_entry(state, item.id)),
      onToggleSelect: (item) => notifier.toggleSelect(_entry(state, item.id)),
      onClearSelection: () => notifier.clearSelection(),
      // Both run as background tasks (task manager + notification), so the
      // transfer survives leaving this screen or locking the device.
      onDownload: () => _pickDirThen((d) async {
        final label = notifier.selectionLabel();
        TaskQueueService.enqueueTransfer(ref, context, source: 'smb', title: 'Download $label', verb: 'Downloading', label: label, run: notifier.downloadJob(d));
      }),
      onZip: () => _pickDirThen((d) async {
        final label = notifier.selectionLabel();
        TaskQueueService.enqueueTransfer(ref, context, source: 'smb', title: 'Zip $label', verb: 'Downloading and zipping', label: label, run: notifier.zipJob(d));
      }),
      onDelete: () => _confirmDelete(context, state, notifier),
      extraActions: () => [
        BrowserAction(icon: Icons.upload_file, label: 'Upload', onPressed: state.transfer == null && !state.atRoot && state.selected.isEmpty ? () => _upload(notifier) : null),
      ],
    );
  }

  SmbFile _entry(SmbState state, String id) => state.entries.firstWhere((e) => e.path == id);

  Future<void> _upload(SmbNotifier notifier) async {
    final local = await pickFile(context, title: 'Select a file to upload');
    if (local != null && mounted) await notifier.uploadFile(local);
  }

  Future<void> _pickDirThen(Future<void> Function(String dir) run) async {
    final dir = await pickDirectory(context, title: 'Choose output folder');
    if (dir != null && mounted) await run(dir);
  }

  Future<void> _confirmDelete(BuildContext context, SmbState state, SmbNotifier notifier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete ${state.selected.length} item(s) from the share? This cannot be undone.'),
        actions: [
          TextButton(autofocus: true, onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await notifier.deleteSelected();
  }
}

/// Host, user, password and domain for a share; Connect closes the sheet once
/// it is in, and a refused login stays here with its error.
class _ConnectForm extends ConsumerStatefulWidget {
  const _ConnectForm({required this.host, required this.user, required this.domain});

  final String host;
  final String user;
  final String domain;

  @override
  ConsumerState<_ConnectForm> createState() => _ConnectFormState();
}

class _ConnectFormState extends ConsumerState<_ConnectForm> {
  late final _host = TextEditingController(text: widget.host);
  late final _user = TextEditingController(text: widget.user);
  final _pass = TextEditingController();
  late final _domain = TextEditingController(text: widget.domain);

  @override
  void dispose() {
    _host.dispose();
    _user.dispose();
    _pass.dispose();
    _domain.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await ref.read(smbProvider.notifier).connect(host: _host.text.trim(), username: _user.text.trim(), password: _pass.text, domain: _domain.text.trim());
    if (mounted && ref.read(smbProvider).connected) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(smbProvider);
    final ready = !state.busy && _host.text.trim().isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitPanel(children: [
        FieldSlot(label: 'Host / IP', controller: _host, hint: '192.168.1.10', icon: Icons.computer, keyboardType: TextInputType.url, autofocus: _host.text.isEmpty, onChanged: (_) => setState(() {})),
        FieldSlot(label: 'Username', controller: _user, icon: Icons.person_outline),
        FieldSlot(label: 'Password', controller: _pass, icon: Icons.key_outlined, obscureText: true, autofocus: _host.text.isNotEmpty, onSubmitted: (_) {
          if (ready) _connect();
        }),
        FieldSlot(label: 'Domain (optional)', controller: _domain, icon: Icons.domain),
      ]),
      if (state.error != null) ...[const SizedBox(height: kitGap), StatusPanel.error(line: errorReason(state.error!), details: errorReason(state.error!) == state.error ? null : state.error)],
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: ready ? _connect : null,
        icon: state.busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
        label: const Text('Connect'),
      ),
    ]);
  }
}
