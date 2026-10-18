import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retro_toolbox/models/game_state_model.dart';
import 'package:retro_toolbox/providers/game_state_provider.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/services/file_ops.dart';
import 'package:retro_toolbox/services/link_download.dart';
import 'package:retro_toolbox/services/link_inbox_server.dart';
import 'package:retro_toolbox/services/task_queue_service.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/widgets/common/advanced_port.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/common/path_browser.dart';
import 'package:retro_toolbox/widgets/tool_description.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dirKey = 'link_download_dir';
const _portKey = 'link_inbox_port';
const _accent = Color(0xFF2E7D5B);

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
  final _downloadFocus = FocusNode();
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

  /// Downloads started here, by task id, so a finished archive can offer Extract.
  final _started = <String>{};

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
    _downloadFocus.dispose();
    super.dispose();
  }

  void _onLink(String link) {
    if (!mounted) return;
    _url.text = link;
    _urlChanged(link, showFull: true);
    _downloadFocus.requestFocus();
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
    final dir = await PathBrowser.show(context, title: 'Save downloads to', initialDir: _dir ?? '/', selectDirectory: true);
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
    // A free name now, so the task's path (for Extract) is where the file lands.
    final name = FileOps.uniqueName(dir, safeFileName(_name.text));
    final dest = p.join(dir, name);
    final id = TaskQueueService.enqueueTransfer(
      ref,
      context,
      title: name,
      source: 'link',
      verb: 'Downloading',
      label: name,
      outputPath: dest,
      run: (onProgress) => downloadToFile(url: url, destPath: dest, onProgress: onProgress),
    );
    _started.add(id);
  }

  void _onGames(Map<String, GameState>? prev, Map<String, GameState> next) {
    for (final id in _started.toList()) {
      final s = next[id];
      if (s == null || s.status != GameStatus.downloaded || prev?[id]?.status == GameStatus.downloaded) continue;
      _started.remove(id);
      final path = s.outputPath!;
      final archive = s.availableActions.contains(GameAction.extract);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${p.basename(path)} downloaded'),
        duration: Duration(seconds: archive ? 10 : 4),
        action: archive
            ? SnackBarAction(
                label: 'Extract here',
                onPressed: () {
                  if (mounted) TaskQueueService.enqueueArchiveExtraction(ref, context, path);
                })
            : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(gameStateManagerProvider, _onGames);
    final ip = orderAddresses(_addresses, ref.watch(settingsProvider.select((s) => s.preferredLocalIp))).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Download from link')),
      body: Actions(
        actions: {
          // Not isEnabled-gated: the nearest Start binding wins even when disabled, so defer explicitly.
          PrimaryActionIntent: CallbackAction<PrimaryActionIntent>(onInvoke: (intent) {
            if (!_canDownload) return Actions.maybeInvoke(context, intent);
            _download();
            return null;
          }),
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: LayoutBuilder(builder: (context, box) {
            final form = _form(context), phone = _phone(context, ip);
            if (box.maxWidth < 600) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [form, const SizedBox(height: 12), phone]);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: form), const SizedBox(width: 12), SizedBox(width: 220, child: phone)],
            );
          }),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final url = _url.text;
    final invalid = url.trim().isNotEmpty && !isValidDownloadUrl(url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ToolDescription(
          icon: Icons.link,
          text: 'Saves a file from an http or https link into a folder you choose, in the background. '
              'Type or paste the link, or send it from your phone.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          onChanged: (v) => _urlChanged(v),
          decoration: InputDecoration(
            labelText: 'Link',
            hintText: 'https://…',
            prefixIcon: const Icon(Icons.link),
            suffixIcon: IconButton(icon: const Icon(Icons.content_paste), tooltip: 'Paste', onPressed: _paste),
            errorText: invalid ? 'Enter an http or https link' : null,
            helperText: _showFull && !invalid ? url.trim() : null,
            helperMaxLines: 4,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _name,
          autocorrect: false,
          onChanged: (_) => _nameTouched = true,
          decoration: const InputDecoration(
            labelText: 'File name',
            prefixIcon: Icon(Icons.insert_drive_file_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Save to',
            prefixIcon: Icon(Icons.folder_outlined),
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding: EdgeInsets.fromLTRB(12, 4, 4, 4),
          ),
          child: Row(
            children: [
              Expanded(child: Text(_dir ?? '…', maxLines: 1, overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: _dir == null ? null : _changeDir, child: const Text('Change')),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          focusNode: _downloadFocus,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44), shape: const StadiumBorder()),
          onPressed: _canDownload ? _download : null,
          icon: const Icon(Icons.download),
          label: const Text('Download'),
        ),
      ],
    );
  }

  Widget _phone(BuildContext context, String? ip) {
    final t = Theme.of(context).textTheme;
    final hsl = HSLColor.fromColor(_accent);
    // Same darkened accent gradient as the menu tiles.
    final gradient = [hsl.withLightness(0.30).withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0)).toColor(), hsl.withLightness(0.15).toColor()];
    final error = _serverError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                children: [
                  Row(children: [
                    const Icon(Icons.smartphone, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('FROM YOUR PHONE',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelMedium?.copyWith(color: Colors.white70, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Container(
                    width: 148,
                    height: 148,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: ip == null || error != null
                        ? Icon(error != null ? Icons.error_outline : Icons.wifi_off, size: 40, color: Colors.black38)
                        : CustomPaint(painter: QrPainter(data: 'http://$ip:$_port/', version: QrVersions.auto, gapless: true)),
                  ),
                  const SizedBox(height: 10),
                  Text(ip == null ? 'No network · port $_port' : '$ip:$_port',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    error ?? (ip == null ? 'Connect to Wi-Fi to send links from your phone' : 'Scan, paste a link and tap Send'),
                    textAlign: TextAlign.center,
                    style: t.bodySmall?.copyWith(color: error != null ? Colors.amberAccent : Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Re-keyed once the saved port loads: the field only reads its initial value.
        AdvancedPort(key: ValueKey(_dir != null), port: _port, onChanged: _setPort),
      ],
    );
  }
}
