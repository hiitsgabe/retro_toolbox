import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retro_toolbox/providers/fbi_server_provider.dart';
import 'package:retro_toolbox/services/fbi_server_service.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/hammer_loader.dart';
import 'package:retro_toolbox/widgets/file_browser.dart' show errorReason;
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';

/// Serves 3DS titles as installable .cia and installs them on a console running
/// FBI: pick a file you downloaded elsewhere, or a catalog title (downloaded
/// and converted on demand); then push it to the 3DS or show a QR. Progress,
/// the QR and every send stay on the screen instead of in dialogs.
class FbiServerScreen extends ConsumerStatefulWidget {
  const FbiServerScreen({super.key});

  @override
  ConsumerState<FbiServerScreen> createState() => _FbiServerScreenState();
}

class _FbiServerScreenState extends ConsumerState<FbiServerScreen> with ServerToggle {
  static const _info = InfoButton(
    icon: Icons.install_mobile,
    title: 'FBI Server',
    text: 'Installs 3DS titles onto a console running FBI over the local network. Turn the server '
        'on, then install a file you picked or a catalog title: it’s converted to .cia if needed. '
        'Show QR needs nothing typed: in FBI open Remote Install, then Scan QR Code. Send to 3DS needs the address FBI shows under Receive URLs.',
  );

  final _search = TextEditingController();
  String _query = '';
  int _page = 0;
  static const _pageSize = 25;

  /// What is being prepared now, and how far (0 when unknown).
  ({String title, double progress})? _work;

  /// The last prepared title: its QR and Send stay up until closed.
  ({String title, String url})? _ready;

  /// This visit's sends and failures, newest first.
  final _log = <ActivityEntry>[];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _note(String title, String detail, KitTone tone) {
    if (!mounted) return;
    final now = DateTime.now();
    setState(() => _log.insert(0, ActivityEntry(title, detail: detail, tone: tone, time: '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}')));
  }

  /// Runs a prepare step in the status panel; returns the served URL, or null
  /// on error (logged) or when another one is running.
  Future<String?> _prepare(String title, Future<String> Function(void Function(double)) run) async {
    if (_work != null) return null;
    setState(() {
      _work = (title: title, progress: 0);
      _ready = null;
    });
    try {
      return await run((v) {
        if (mounted) setState(() => _work = (title: title, progress: v));
      });
    } catch (e) {
      _note(title, 'Could not prepare: $e', KitTone.error);
      return null;
    } finally {
      if (mounted) setState(() => _work = null);
    }
  }

  Future<void> _installFile() async {
    final path = await pickFile(context, title: 'Select a .cia / .3ds / .zip to install', extensions: ['cia', '3ds', 'cci', 'zip']);
    if (path == null || !mounted) return;
    final name = p.basename(path);
    final url = await _prepare(name, (op) => ref.read(fbiServerProvider.notifier).prepareLocalFile(path, op));
    if (url != null && mounted) setState(() => _ready = (title: name, url: url));
  }

  Future<void> _sendCatalog(FbiGame g) async {
    if (ref.read(fbiServerProvider).threeDsIp.trim().isEmpty && !await _editIp()) return;
    final url = await _prepare(g.game.title, (op) => ref.read(fbiServerProvider.notifier).prepareCatalog(g, op));
    if (url == null) return;
    await _sendUrl(g.game.title, url);
  }

  Future<void> _qrCatalog(FbiGame g) async {
    final url = await _prepare(g.game.title, (op) => ref.read(fbiServerProvider.notifier).prepareCatalog(g, op));
    if (url != null && mounted) setState(() => _ready = (title: g.game.title, url: url));
  }

  Future<void> _sendUrl(String title, String url) async {
    if (ref.read(fbiServerProvider).threeDsIp.trim().isEmpty && !await _editIp()) return;
    final ip = ref.read(fbiServerProvider).threeDsIp.trim();
    try {
      await ref.read(fbiServerProvider.notifier).sendUrlToThreeDs(url);
      _note(title, 'Sent to your 3DS', KitTone.success);
    } catch (e) {
      _note(title, 'Failed to reach FBI at $ip:5000: $e', KitTone.error);
    }
  }

  /// The 3DS address, typed in a sheet. True when one was saved.
  Future<bool> _editIp() async {
    final ip = await showKitSheet<String>(
      context,
      area: AppArea.servers,
      title: '3DS address',
      subtitle: 'Shown in FBI under Remote Install, Receive URLs',
      builder: (_) => _IpField(initial: ref.read(fbiServerProvider).threeDsIp),
    );
    if (ip == null || !mounted) return false;
    await ref.read(fbiServerProvider.notifier).setThreeDsIp(ip.trim());
    return ip.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fbiServerProvider);
    final notifier = ref.read(fbiServerProvider.notifier);
    final pill = serverStateOf(running: state.running, starting: starting, error: state.error);
    final work = _work;

    return KitScaffold(
      title: 'FBI Server',
      subtitle: 'Install 3DS games with FBI over Wi-Fi',
      icon: Icons.install_mobile,
      glyph: PixelIcons.fbi,
      area: AppArea.servers,
      info: _info,
      body: KitColumns(
        start: [
          // What was just asked for comes first: the progress, then the QR.
          if (work != null) StatusPanel.working(items: [WorkItem(work.title, progress: work.progress > 0 ? work.progress : null, note: work.progress > 0 ? null : 'Preparing')]),
          if (_ready != null) _readyPanel(context, _ready!, state.threeDsIp.trim().isNotEmpty),
          // This server pushes to the 3DS: its address is the one that matters.
          AddressHero.pushTarget(
            state: pill,
            stateDetail: transfersLabel(state.activeTransfers),
            label: '3DS address',
            address: state.threeDsIp,
            placeholder: 'Not set: only Send needs it',
            onChange: _editIp,
          ),
          if (state.error != null) StatusPanel.error(line: state.running ? errorReason(state.error!) : 'The server did not start: ${errorReason(state.error!)}', details: state.error),
          if (state.running || _log.isNotEmpty)
            ActivityPanel(
              count: state.activeTransfers,
              countLabel: state.activeTransfers > 0 ? '3DS downloading: ${state.activeTransfers}' : 'Idle',
              entries: _log.take(6).toList(),
            ),
          OptionList(children: [PortOption(port: state.port, onChanged: notifier.setPort, lockedReason: state.running ? lockedWhileRunning : null)]),
        ],
        end: [
          const KitLabel('In FBI'),
          const Steps(steps: [
            'Remote Install, Scan QR Code: show a QR here',
            'Or Receive URLs, then Send to 3DS',
          ]),
          Row(children: [
            const Expanded(child: KitLabel('Catalog 3DS titles')),
            if (state.running) TextButton(onPressed: state.gamesLoading ? null : notifier.refreshGames, child: const Text('Reload')),
          ]),
          ..._catalog(context, state),
        ],
      ),
      actionBar: ActionBar(
        primary: serverAction(running: state.running, starting: starting, onToggle: () => toggleServer(running: state.running, start: notifier.enable, stop: notifier.disable)),
        // Installing serves the file, so it needs the server on.
        secondary: KitAction('Install a file', state.running && work == null ? _installFile : null, icon: Icons.file_open, button: PadButton.x),
        hints: const [KitHint(PadButton.a, 'Show QR'), KitHint(PadButton.y, 'Send'), KitHint(PadButton.b, 'Back')],
        summary: state.running ? 'Serving on port ${state.port}' : 'Port ${state.port}',
      ),
    );
  }

  /// The prepared title: a QR for FBI's camera, and Send for Receive URLs.
  Widget _readyPanel(BuildContext context, ({String title, String url}) ready, bool hasIp) => Builder(builder: (context) => _readyPanelIn(context, ready, hasIp));

  Widget _readyPanelIn(BuildContext context, ({String title, String url}) ready, bool hasIp) {
    final t = KitType.of(context);
    final qr = QrValidator.validate(data: ready.url, version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.L);
    final side = kitStacked(context) ? 200.0 : 150.0;
    return KitPanel(key: const ValueKey('fbi-ready'), padding: const EdgeInsets.all(12), children: [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(ready.title, style: t.row, maxLines: 2, overflow: TextOverflow.ellipsis)),
          IconButton(tooltip: 'Close', icon: const Icon(Icons.close, size: 18), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _ready = null)),
        ]),
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: side,
            height: side,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(t.k.buttonRadius.clamp(4, 12).toDouble())),
            child: qr.isValid && qr.qrCode != null
                ? CustomPaint(key: const ValueKey('fbi-qr'), painter: QrPainter.withQr(qr: qr.qrCode!, gapless: true))
                : const Center(child: Text('Too long for a QR. Use Send to 3DS.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black87))),
          ),
        ),
        const SizedBox(height: 8),
        Text('On the 3DS: FBI, Remote Install, Scan QR Code', textAlign: TextAlign.center, style: t.subtitle),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton.icon(
            onPressed: () => _sendUrl(ready.title, ready.url),
            icon: const Icon(Icons.send, size: 18),
            label: Text(hasIp ? 'Send to 3DS' : 'Send to 3DS (set its address)'),
          ),
        ),
      ]),
    ]);
  }

  List<Widget> _catalog(BuildContext context, FbiServerState state) {
    final t = KitType.of(context);
    Widget line(String s) => KitPanel(padding: const EdgeInsets.all(14), children: [Text(s, style: t.body.copyWith(color: t.muted))]);
    if (!state.running) return [line('Start the server to install titles from your catalog.')];
    if (state.gamesLoading) return const [Padding(padding: EdgeInsets.all(24), child: Center(child: HammerLoader()))];
    if (state.games.isEmpty) return [line('No 3DS titles in your catalog. Use "Install a file" for a local ROM.')];

    final q = _query.toLowerCase();
    final filtered = q.isEmpty ? state.games : state.games.where((g) => g.game.title.toLowerCase().contains(q)).toList();
    final pageCount = (filtered.length / _pageSize).ceil();
    final page = _page.clamp(0, pageCount == 0 ? 0 : pageCount - 1);
    final start = page * _pageSize;
    final slice = filtered.skip(start).take(_pageSize).toList();
    return [
      KitPanel(children: [
        FieldSlot(
          label: 'Search titles',
          controller: _search,
          icon: Icons.search,
          onChanged: (v) => setState(() {
            _query = v.trim();
            _page = 0;
          }),
          trailing: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                    _page = 0;
                  }),
                ),
        ),
      ]),
      if (filtered.isEmpty)
        line('No matches.')
      else
        KitPanel(children: [
          for (final g in slice) _gameRow(context, g),
          if (pageCount > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(children: [
                TextButton(onPressed: page > 0 ? () => setState(() => _page = page - 1) : null, child: const Text('Previous')),
                Expanded(child: Text('${start + 1} to ${start + slice.length} of ${filtered.length}', textAlign: TextAlign.center, style: t.subtitle)),
                TextButton(onPressed: page < pageCount - 1 ? () => setState(() => _page = page + 1) : null, child: const Text('Next')),
              ]),
            ),
        ]),
    ];
  }

  /// One focus stop: A or a tap shows the QR, Y or a long press offers Send
  /// too. The send icon is for touch and mouse, out of the d-pad's way.
  Widget _gameRow(BuildContext context, FbiGame g) => Builder(builder: (context) => _gameRowIn(context, g));

  Widget _gameRowIn(BuildContext context, FbiGame g) {
    final t = KitType.of(context);
    void menu() => showRowMenu(context, title: g.game.title, subtitle: g.console.name, items: [
          RowMenuItem('Show QR', () => _qrCatalog(g), icon: Icons.qr_code_2, subtitle: 'In FBI: Remote Install, Scan QR Code'),
          RowMenuItem('Send to 3DS', () => _sendCatalog(g), icon: Icons.send, subtitle: 'In FBI: Remote Install, Receive URLs'),
        ]);
    return RowMenuTarget(
      onMenu: menu,
      child: KitRow(
        onTap: () => _qrCatalog(g),
        child: Row(children: [
          Icon(Icons.videogame_asset_outlined, size: 20, color: t.k.accent),
          const SizedBox(width: 10),
          Expanded(child: KitRowText(title: g.game.title, subtitle: g.console.name)),
          Text('QR', style: t.verb),
          ExcludeFocus(child: IconButton(icon: const Icon(Icons.send, size: 18), tooltip: 'Send to 3DS', visualDensity: VisualDensity.compact, onPressed: () => _sendCatalog(g))),
        ]),
      ),
    );
  }
}

/// The 3DS address field of the sheet; its controller lives and dies with it.
class _IpField extends StatefulWidget {
  const _IpField({required this.initial});

  final String initial;

  @override
  State<_IpField> createState() => _IpFieldState();
}

class _IpFieldState extends State<_IpField> {
  late final _ip = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void save() => Navigator.of(context).pop(_ip.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      KitPanel(children: [
        FieldSlot(label: '3DS IP address', controller: _ip, hint: '192.168.1.77', icon: Icons.devices, keyboardType: TextInputType.number, autofocus: true, onSubmitted: (_) => save()),
      ]),
      const SizedBox(height: 10),
      FilledButton(onPressed: save, child: const Text('Save')),
    ]);
  }
}
