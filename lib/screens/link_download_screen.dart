import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retro_toolbox/services/pick.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/models/task_queue_model.dart';
import 'package:retro_toolbox/providers/extraction_provider.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/providers/task_queue_provider.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/services/link_download.dart';
import 'package:retro_toolbox/services/link_inbox_server.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';

const _dirKey = 'link_download_dir';
const _portKey = 'link_inbox_port';

/// Downloads a file from an http(s) link into a chosen folder, as a background
/// task. While open it serves a small LAN page (QR) where a phone can send the
/// link; a received link only fills the field, the user still presses Download.
class LinkDownloadScreen extends ConsumerStatefulWidget {
  const LinkDownloadScreen({super.key, this.server, this.addresses});

  final LinkInboxServer? server;

  /// Test seam for the device's LAN addresses.
  final Future<List<String>> Function()? addresses;

  @override
  ConsumerState<LinkDownloadScreen> createState() => _LinkDownloadScreenState();
}

class _LinkDownloadScreenState extends ConsumerState<LinkDownloadScreen> {
  late final _server = widget.server ?? LinkInboxServer();
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _portField = TextEditingController(text: '$linkInboxDefaultPort');
  StreamSubscription<String>? _sub;
  Timer? _probe;
  Future<void> _serverOp = Future.value();

  /// Set once the user types in the name field; a later probe result won't overwrite it.
  bool _nameTouched = false;

  /// The link came from the phone or the clipboard: show it in full under the
  /// single-line field, so the user sees exactly what they confirm.
  bool _showFull = false;
  int _port = linkInboxDefaultPort;
  String? _dir, _serverError;
  List<String> _addresses = const [];

  /// Finished archives already sent to extraction, so Extract here is offered once.
  final _extracted = <String>{};

  @override
  void initState() {
    super.initState();
    _sub = _server.links.listen(_onLink);
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final port = prefs.getInt(_portKey) ?? linkInboxDefaultPort;
    final dir = prefs.getString(_dirKey) ?? await DirectoryService().getDownloadDir();
    if (!mounted) return;
    setState(() {
      _port = port;
      _dir = dir;
      _portField.text = '$port';
    });
    _restart();
    final addrs = await (widget.addresses ?? TinfoilServerService.localAddresses)().catchError((_) => const <String>[]);
    if (mounted) setState(() => _addresses = addrs);
  }

  /// (Re)starts the server on [_port]; queued so fast port edits don't race.
  void _restart() {
    final port = _port;
    _serverOp = _serverOp.then((_) async {
      String? error;
      try {
        await _server.stop();
        if (!mounted) return;
        await _server.start(port);
      } catch (_) {
        error = 'Port $port is busy. Pick another one under Advanced.';
      }
      if (mounted) setState(() => _serverError = error);
    });
  }

  @override
  void dispose() {
    _probe?.cancel();
    _sub?.cancel();
    _serverOp.then((_) => _server.stop());
    _url.dispose();
    _name.dispose();
    _portField.dispose();
    super.dispose();
  }

  void _onLink(String link) {
    if (!mounted) return;
    _url.text = link;
    _urlChanged(link, showFull: true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link received from your phone. Press Download to start.')));
  }

  void _urlChanged(String raw, {bool showFull = false}) {
    final url = raw.trim();
    _probe?.cancel();
    setState(() {
      _nameTouched = false;
      _showFull = showFull;
      _name.text = url.isEmpty ? '' : fileNameFromUrl(url);
    });
    if (!isValidDownloadUrl(url)) return;
    _probe = Timer(const Duration(milliseconds: 500), () async {
      final name = await probeFileName(url);
      if (name != null && mounted && !_nameTouched && _url.text.trim() == url) setState(() => _name.text = name);
    });
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _url.text = text;
    _urlChanged(text, showFull: true);
  }

  Future<void> _changeDir() async {
    final dir = await pickDirectory(context, title: 'Save downloads to', initialDir: _dir);
    if (dir == null || !mounted) return;
    setState(() => _dir = dir);
    (await SharedPreferences.getInstance()).setString(_dirKey, dir);
  }

  Future<void> _setPort(int port) async {
    if (port == _port) return;
    setState(() => _port = port);
    _restart();
    (await SharedPreferences.getInstance()).setInt(_portKey, port);
  }

  bool get _canDownload => _dir != null && isValidDownloadUrl(_url.text);

  void _download() {
    final url = _url.text.trim(), dir = _dir;
    if (dir == null || !isValidDownloadUrl(url)) return;
    // Reserved now, so the task's path (for Extract) is where the file lands.
    final dest = reserveDownloadPath(dir, safeFileName(_name.text));
    final name = p.basename(dest);
    // The status panel shows it from here on.
    TaskQueueService.enqueueTransfer(
      ref,
      context,
      title: name,
      source: 'link',
      verb: 'Downloading',
      label: name,
      outputPath: dest,
      run: downloadJob(url, dest),
    );
  }

  /// The downloads started from this screen, in the task list.
  StatusPanel _status() {
    final games = ref.watch(gameStateManagerProvider);
    String? path(QueuedTask t) => games[t.id]?.outputPath;
    return toolTaskStatus(
      ref.watch(taskQueueProvider),
      ref.watch(extractionProvider),
      TaskType.remoteTransfer,
      where: (t) => t.params['source'] == 'link',
      name: (t) => '${t.params['label']}',
      saved: (t) => path(t) == null ? 'Saved ${t.params['label']}' : savedIn(p.basename(path(t)!), p.dirname(path(t)!)),
      failed: 'Could not download',
      action: (t) {
        final s = games[t.id], file = path(t);
        if (s == null || file == null || _extracted.contains(t.id)) return null;
        if (s.status != GameStatus.downloaded || !s.availableActions.contains(GameAction.extract)) return null;
        return (
          'Extract here',
          () {
            setState(() => _extracted.add(t.id));
            TaskQueueService.enqueueArchiveExtraction(ref, context, file);
          }
        );
      },
    );
  }

  static const _info = InfoButton(
    icon: Icons.link,
    title: 'Download from link',
    text: 'Saves a file from an http or https link into a folder you choose, in the background. '
        'Type or paste the link, or send it from your phone.\n\n'
        'While this screen is open, a phone on the same network can open the address under the QR code and send a link; '
        'it only fills the Link field, you still press Download. Downloads also show in Tasks.',
  );

  @override
  Widget build(BuildContext context) {
    final ip = orderAddresses(_addresses, ref.watch(settingsProvider.select((s) => s.preferredLocalIp))).firstOrNull;
    final url = _url.text, dir = _dir;
    final invalid = url.trim().isNotEmpty && !isValidDownloadUrl(url);
    final String summary;
    if (url.trim().isEmpty) {
      summary = 'Paste or type a link';
    } else if (invalid) {
      summary = 'Not an http or https link';
    } else {
      final name = safeFileName(_name.text);
      summary = dir == null ? name : '$name to ${pathParts(dir).join(pathSeparator)}';
    }
    return KitScaffold(
      title: 'Download from link',
      subtitle: 'Save a file from a link, or send it from a phone',
      icon: Icons.link,
      glyph: PixelIcons.link,
      area: AppArea.tools,
      info: _info,
      body: KitColumns(
        start: [
          const KitLabel('Download'),
          KitPanel(children: [
            FieldSlot(
              label: 'Link',
              controller: _url,
              hint: 'https://…',
              icon: Icons.link,
              glyph: PixelIcons.link,
              keyboardType: TextInputType.url,
              onChanged: (v) => _urlChanged(v),
              error: invalid ? 'Enter an http or https link' : null,
              // The whole link, never cut: the user must see exactly what they confirm.
              message: _showFull && !invalid ? url.trim() : null,
              trailing: IconButton(icon: const Icon(Icons.content_paste), tooltip: 'Paste', onPressed: _paste),
            ),
            FieldSlot(label: 'File name', controller: _name, icon: Icons.insert_drive_file_outlined, glyph: PixelIcons.file, onChanged: (_) => _nameTouched = true),
            Slot(label: 'Save to', folder: true, path: dir, emptyText: 'Looking for the downloads folder', onPick: dir == null ? null : _changeDir),
          ]),
          _status(),
        ],
        end: [
          const KitLabel('From your phone'),
          _phone(context, ip),
          OptionList(children: [
            OptionExpander(subtitle: 'Port $_port', children: [
              FieldSlot(
                label: 'Port',
                controller: _portField,
                icon: Icons.settings_ethernet,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) {
                  final port = int.tryParse(v);
                  if (port != null && port > 0 && port < 65536) _setPort(port);
                },
              ),
            ]),
          ]),
        ],
      ),
      actionBar: ActionBar(
        primary: KitAction('Download', _canDownload ? _download : null, icon: Icons.download),
        hints: const [KitHint(PadButton.a, 'Choose'), KitHint(PadButton.b, 'Back')],
        summary: summary,
      ),
    );
  }

  /// The QR a phone on the same network opens to send a link here.
  Widget _phone(BuildContext context, String? ip) {
    final t = KitType.of(context);
    final error = _serverError;
    final side = kitStacked(context) ? 148.0 : 124.0;
    return KitPanel(padding: const EdgeInsets.all(12), children: [
      Center(
        child: Container(
          width: side,
          height: side,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(t.k.buttonRadius.clamp(4, 12).toDouble())),
          child: ip == null || error != null
              ? Icon(error != null ? Icons.error_outline : Icons.wifi_off, size: 40, color: Colors.black38)
              : CustomPaint(painter: QrPainter(data: 'http://$ip:$_port/', version: QrVersions.auto, gapless: true)),
        ),
      ),
      const SizedBox(height: 10),
      Text(ip == null ? 'No network · port $_port' : '$ip:$_port', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.mono(16).copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(
        error ?? (ip == null ? 'Connect to Wi-Fi to send links from your phone' : 'Scan, paste a link and tap Send'),
        textAlign: TextAlign.center,
        style: t.subtitle.copyWith(color: error != null ? t.k.warning : null),
      ),
    ]);
  }
}
