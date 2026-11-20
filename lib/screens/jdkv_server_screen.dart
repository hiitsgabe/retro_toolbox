import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/providers/jdkv_server_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/services/webdav_server_service.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/widgets/file_browser.dart' show errorReason;
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Controls the embedded WebDAV server that syncs emulator saves with JKSV on
/// a Switch. Android to Switch (JKSV restores) and Switch to Android (confirm
/// to pull).
class JdkvServerScreen extends ConsumerStatefulWidget {
  const JdkvServerScreen({super.key});

  @override
  ConsumerState<JdkvServerScreen> createState() => _JdkvServerScreenState();
}

class _JdkvServerScreenState extends ConsumerState<JdkvServerScreen> with ServerToggle {
  static const _info = InfoButton(
    icon: Icons.folder_shared_rounded,
    title: 'JDKV Server',
    text: 'Runs a WebDAV server so JKSV on your console can back up and restore game saves to this device over the local network. '
        'Point JKSV at the address shown here with webdav.json. Your current export is always backed up before a pull replaces it.',
  );

  /// What happened this visit (pulls, saved files), newest first.
  final _log = <ActivityEntry>[];

  @override
  void initState() {
    super.initState();
    ref.read(jdkvServerProvider.notifier).loadHubRecipes();
  }

  void _note(ActivityEntry e) {
    if (mounted) setState(() => _log.insert(0, e));
  }

  static String _json(String origin) => '{\n  "origin": "$origin"\n}';

  Future<void> _saveJson(String origin) async {
    final json = _json(origin);
    final path = await pickSavePath(context, title: 'Save webdav.json', fileName: 'webdav.json', bytes: Uint8List.fromList(utf8.encode(json)));
    if (path == null || !mounted) return;
    // Only iOS' save dialog writes the bytes itself; everywhere else
    // (desktop dialog, folder browser) we just got a path.
    String? error;
    if (!Platform.isIOS) {
      try {
        File(path).writeAsStringSync(json);
      } catch (e) {
        error = 'Could not save webdav.json: $e';
      }
    }
    _note(ActivityEntry(error ?? 'Saved webdav.json', detail: error == null ? path : null, tone: error == null ? KitTone.success : KitTone.error));
  }

  Future<void> _copyJson(String origin) async {
    await Clipboard.setData(ClipboardData(text: _json(origin)));
    _note(ActivityEntry('Copied webdav.json', detail: origin));
  }

  Future<void> _confirmPull(IncomingSave s) async {
    final notifier = ref.read(jdkvServerProvider.notifier);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Pull ${s.displayName}?'),
        content: const Text('Your current export for this game will be copied to a timestamped backup, then replaced with the Switch save.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(autofocus: true, onPressed: () => Navigator.pop(c, true), child: const Text('Pull')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final now = DateTime.now();
    final ts = '${now.year}${_pad2(now.month)}${_pad2(now.day)}-${_pad2(now.hour)}${_pad2(now.minute)}${_pad2(now.second)}';
    final before = ref.read(jdkvServerProvider).error;
    await notifier.pull(s.titleId, timestamp: ts);
    if (!mounted) return;
    final after = ref.read(jdkvServerProvider).error;
    final error = after != before ? after : null;
    _note(ActivityEntry(
      s.displayName,
      detail: error == null ? 'Pulled, old save backed up. Import it in your emulator.' : 'Pull failed: $error',
      time: '${_pad2(now.hour)}:${_pad2(now.minute)}',
      tone: error == null ? KitTone.success : KitTone.error,
    ));
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(jdkvServerProvider);
    final notifier = ref.read(jdkvServerProvider.notifier);
    final pad = ref.watch(inputModeProvider) == InputMode.gamepad;
    final addresses = orderAddresses(state.addresses, ref.watch(settingsProvider).preferredLocalIp);
    final host = state.running ? addresses.firstOrNull : null;
    final pill = serverStateOf(running: state.running, starting: starting, error: state.error);
    final detail = transfersLabel(state.activeTransfers);
    final locked = state.running ? lockedWhileRunning : null;
    final folderSource = state.source.recipe == null;
    final ready = !folderSource || state.folder != null;
    String origin(String ip) => 'http://$ip:${state.port}';

    final hero = host == null
        ? AddressHero(state: pill, address: '', stateDetail: detail, label: 'In webdav.json')
        // The scheme small, so the address keeps one line on a small screen.
        : AddressHero(state: pill, stateDetail: detail, prefix: 'http://', address: '$host:${state.port}', label: 'In webdav.json', copyable: false);

    // Saves waiting to be pulled are why the user came back: on a phone they
    // go right under the address, not after the options.
    final incoming = state.incoming.isEmpty
        ? const <Widget>[]
        : [const KitLabel('From the Switch'), KitPanel(children: [for (final s in state.incoming) _incomingRow(s)])];
    final stacked = kitStacked(context);

    return KitScaffold(
      title: 'JDKV Server',
      subtitle: 'Sync Switch saves with JKSV over Wi-Fi',
      icon: Icons.folder_shared_rounded,
      glyph: PixelIcons.jdkv,
      area: AppArea.servers,
      info: _info,
      body: KitColumns(
        start: [
          hero,
          if (stacked) ...incoming,
          if (state.error != null && !state.running) StatusPanel.error(line: 'The server did not start: ${errorReason(state.error!)}', details: state.error),
          ConfigFileSlot(
            fileName: 'webdav.json',
            destination: 'sdmc:/config/JKSV/ on the Switch',
            onSave: host == null ? null : () => _saveJson(origin(host)),
            onCopy: host == null ? null : () => _copyJson(origin(host)),
          ),
          if (addresses.length > 1 && state.running)
            OptionList(children: [
              OptionAction(
                title: 'Other addresses (${addresses.length - 1})',
                subtitle: 'When the Switch is on another network',
                onTap: () => showOtherAddresses(context, area: AppArea.servers, addresses: [
                  for (final ip in addresses.skip(1))
                    AddressChoice(origin(ip), copyText: _json(origin(ip)), actions: [KitAction('Save file', () => _saveJson(origin(ip)))]),
                ]),
              ),
            ]),
          const KitLabel('Saves from'),
          _source(state, notifier, locked),
          OptionList(children: [PortOption(port: state.port, onChanged: notifier.setPort, lockedReason: locked)]),
        ],
        end: [
          if (!stacked) ...incoming,
          const KitLabel('In JKSV'),
          Steps(
            steps: [
              'Open JKSV: your saves here show as backups',
              'Select a game and press Y to restore it to the Switch',
              // The Pull is on this device, so its verb follows the last input here.
              'To send one back, back up to WebDAV in JKSV, then ${pad ? 'press A on it' : 'tap it'} under From the Switch',
            ],
            firstTime: const ['Put webdav.json in sdmc:/config/JKSV/ on the Switch'],
          ),
          if (state.running || _log.isNotEmpty)
            ActivityPanel(count: state.activeTransfers, countLabel: detail ?? 'Idle', entries: _log, emptyText: 'No pulls or transfers yet'),
        ],
      ),
      actionBar: ActionBar(
        primary: serverAction(
          running: state.running,
          starting: starting,
          onToggle: ready || state.running ? () => toggleServer(running: state.running, start: notifier.enable, stop: notifier.disable) : null,
        ),
        hints: [if (state.incoming.isNotEmpty) const KitHint(PadButton.a, 'Pull') else const KitHint(PadButton.a, 'Choose'), const KitHint(PadButton.b, 'Back')],
        summary: !ready && !state.running ? 'Choose the save exports folder first' : (state.running ? 'Serving on port ${state.port}' : 'Port ${state.port}'),
      ),
    );
  }

  /// Where the saves come from: the exported saves folder, or a Save Sync
  /// recipe. Locked while the server runs.
  Widget _source(JdkvServerState state, JdkvServerNotifier notifier, String? locked) {
    // The chosen recipe stays listed while the hub is read, or when it cannot be.
    final ids = {...state.hubRecipes.keys, if (state.source.recipe case final id?) id};
    Widget option(String title, JdkvSourceChoice? choice, {bool enabled = true, String? hint}) => OptionChoice<JdkvSourceChoice?>(
          title: title,
          subtitle: hint,
          value: choice,
          groupValue: state.source,
          onSelected: enabled && choice != null ? (c) => notifier.setSource(c!) : null,
          lockedReason: choice == null || !enabled ? null : locked,
        );
    final folder = state.folder;
    return OptionList(children: [
      option('Exported saves folder', const JdkvSourceChoice.folder()),
      if (state.source.recipe == null)
        Slot(
          label: 'Save exports folder',
          folder: true,
          path: folder,
          emptyText: 'Choose where your emulator exports saves',
          lockedReason: locked,
          onPick: () async {
            final dir = await pickDirectory(context, title: 'Select save exports folder');
            if (dir != null) notifier.setFolder(dir);
          },
        ),
      if (!state.hubConfigured && ids.isEmpty) option('Save Sync', null, hint: 'Set up Save Sync first'),
      for (final id in ids)
        option('Save Sync: ${state.hubRecipes[id] ?? id}', JdkvSourceChoice.hub(id), enabled: state.hubConfigured, hint: state.hubConfigured ? null : 'Set up Save Sync first'),
    ]);
  }

  /// A save JKSV sent: A or a tap asks to pull it.
  Widget _incomingRow(IncomingSave s) => Builder(builder: (context) => _incomingRowIn(context, s));

  Widget _incomingRowIn(BuildContext context, IncomingSave s) {
    final t = KitType.of(context);
    return KitRow(
      onTap: () => _confirmPull(s),
      child: Row(children: [
        Icon(Icons.download_for_offline_outlined, size: 20, color: t.k.accent),
        const SizedBox(width: 10),
        Expanded(child: KitRowText(title: s.displayName, subtitle: '${s.titleId} · ${formatBytes(s.bytes)}')),
        const SizedBox(width: 8),
        Text('Pull', style: t.verb),
      ]),
    );
  }
}
