import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:roms_downloader/providers/fbi_server_provider.dart';
import 'package:roms_downloader/services/fbi_server_service.dart';
import 'package:roms_downloader/widgets/common/advanced_port.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Serves 3DS titles as installable .cia and installs them on a console running
/// FBI — pick a file you downloaded elsewhere, or a catalog title (downloaded
/// and converted on demand); then push it to the 3DS or show a QR.
class FbiServerScreen extends ConsumerStatefulWidget {
  const FbiServerScreen({super.key});

  @override
  ConsumerState<FbiServerScreen> createState() => _FbiServerScreenState();
}

class _FbiServerScreenState extends ConsumerState<FbiServerScreen> {
  late final _ip = TextEditingController(text: ref.read(fbiServerProvider).threeDsIp);
  final _search = TextEditingController();
  String _query = '';
  int _page = 0;
  static const _pageSize = 25;

  @override
  void dispose() {
    _ip.dispose();
    _search.dispose();
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  /// Runs a prepare step behind a progress dialog; returns the served URL or
  /// null on error/cancel.
  Future<String?> _prepare(String title, Future<String> Function(void Function(double)) run) async {
    final progress = ValueNotifier<double>(0);
    String? result;
    Object? err;
    final future = run((p) => progress.value = p).then((url) => result = url).catchError((e) => err = e);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        future.whenComplete(() {
          if (Navigator.canPop(context)) Navigator.pop(context);
        });
        return AlertDialog(
          title: const Text('Preparing…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, v, __) => Column(
                  children: [
                    LinearProgressIndicator(value: v > 0 ? v : null),
                    const SizedBox(height: 6),
                    Text(v > 0 ? '${(v * 100).round()}%' : 'Working…', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    progress.dispose();
    if (err != null) {
      _snack('$err');
      return null;
    }
    return result;
  }

  Future<void> _installFile() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select a .cia / .3ds / .zip to install',
      type: FileType.custom,
      allowedExtensions: ['cia', '3ds', 'cci', 'zip'],
    );
    final path = picked?.files.firstOrNull?.path;
    if (path == null || !mounted) return;
    final url = await _prepare(picked!.files.first.name, (op) => ref.read(fbiServerProvider.notifier).prepareLocalFile(path, op));
    if (url != null && mounted) _afterPrepared(picked.files.first.name, url);
  }

  Future<void> _sendCatalog(FbiGame g) async {
    if (_ip.text.trim().isEmpty) return _snack('Enter your 3DS IP first.');
    await ref.read(fbiServerProvider.notifier).setThreeDsIp(_ip.text.trim());
    final url = await _prepare(g.game.title, (op) => ref.read(fbiServerProvider.notifier).prepareCatalog(g, op));
    if (url == null) return;
    await _sendUrl(g.game.title, url);
  }

  Future<void> _qrCatalog(FbiGame g) async {
    final url = await _prepare(g.game.title, (op) => ref.read(fbiServerProvider.notifier).prepareCatalog(g, op));
    if (url != null && mounted) _showQr(g.game.title, url);
  }

  Future<void> _sendUrl(String title, String url) async {
    try {
      await ref.read(fbiServerProvider.notifier).sendUrlToThreeDs(url);
      _snack('Sent “$title” to your 3DS.');
    } catch (e) {
      _snack('Failed to reach FBI at ${_ip.text.trim()}:5000 — $e');
    }
  }

  /// After a file is prepared and served, offer to push it or show its QR.
  void _afterPrepared(String title, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ready to install'),
        content: Text('“$title” is served. Push it to your 3DS, or show a QR for FBI to scan.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showQr(title, url);
            },
            child: const Text('QR'),
          ),
          FilledButton(
            onPressed: _ip.text.trim().isEmpty
                ? null
                : () {
                    Navigator.pop(context);
                    _sendUrl(title, url);
                  },
            child: const Text('Send to 3DS'),
          ),
        ],
      ),
    );
  }

  Future<Uint8List?> _qrPng(String url) async {
    try {
      final data = await QrPainter(data: url, version: QrVersions.auto, gapless: true).toImageData(600);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _showQr(String title, String url) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FutureBuilder<Uint8List?>(
              future: _qrPng(url),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const SizedBox(width: 240, height: 240, child: Center(child: CircularProgressIndicator()));
                }
                final bytes = snap.data;
                if (bytes == null) {
                  return const SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(child: Text('URL too long for a QR code — use Send instead.', textAlign: TextAlign.center)),
                  );
                }
                return Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Image.memory(bytes, width: 240, height: 240, filterQuality: FilterQuality.none),
                );
              },
            ),
            const SizedBox(height: 12),
            const Text('In FBI: Remote Install → Scan QR Code', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fbiServerProvider);
    final notifier = ref.read(fbiServerProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('FBI Server')),
      floatingActionButton: state.running
          ? FloatingActionButton.extended(onPressed: _installFile, icon: const Icon(Icons.file_open), label: const Text('Install a file'))
          : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ToolDescription(
            icon: Icons.install_mobile,
            text: 'Installs 3DS titles onto a console running FBI over the local network. Turn the server '
                'on, then install a file you picked or a catalog title — it’s converted to .cia if needed.',
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable server'),
                subtitle: Text(state.running ? 'Serving on port ${state.port}' : 'Off'),
                value: state.running,
                onChanged: (v) => v ? notifier.enable() : notifier.disable(),
              ),
            ),
          ),
          if (!state.running) ...[
            const SizedBox(height: 8),
            AdvancedPort(port: state.port, onChanged: notifier.setPort),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (state.running) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _ip,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '3DS IP address',
                hintText: 'FBI → Remote Install → Receive URLs',
                border: OutlineInputBorder(),
                isDense: true,
                prefixIcon: Icon(Icons.devices),
              ),
              onChanged: notifier.setThreeDsIp,
            ),
            const SizedBox(height: 16),
            _instructions(theme),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Catalog 3DS titles', style: theme.textTheme.titleSmall),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Reload', onPressed: () => notifier.refreshGames()),
              ],
            ),
            const SizedBox(height: 8),
            ..._gameList(theme, state),
          ],
        ],
      ),
    );
  }

  List<Widget> _gameList(ThemeData theme, FbiServerState state) {
    if (state.gamesLoading) {
      return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    }
    if (state.games.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('No 3DS titles in your catalog. Use “Install a file” for a local ROM.',
                textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ),
      ];
    }

    final q = _query.toLowerCase();
    final filtered = q.isEmpty ? state.games : state.games.where((g) => g.game.title.toLowerCase().contains(q)).toList();
    final pageCount = (filtered.length / _pageSize).ceil();
    final page = _page.clamp(0, pageCount == 0 ? 0 : pageCount - 1);
    final start = page * _pageSize;
    final slice = filtered.skip(start).take(_pageSize).toList();

    return [
      TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search titles',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _search.clear(); _query = ''; _page = 0; })),
        ),
        onChanged: (v) => setState(() { _query = v.trim(); _page = 0; }),
      ),
      const SizedBox(height: 8),
      if (filtered.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('No matches.', style: theme.textTheme.bodyMedium)))
      else ...[
        for (final g in slice) _gameCard(theme, g),
        if (pageCount > 1) _pager(theme, page, pageCount, filtered.length, start, slice.length),
      ],
    ];
  }

  Widget _pager(ThemeData theme, int page, int pageCount, int total, int start, int shown) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: page > 0 ? () => setState(() => _page = page - 1) : null),
          Text('${start + 1}–${start + shown} of $total', style: theme.textTheme.bodySmall),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: page < pageCount - 1 ? () => setState(() => _page = page + 1) : null),
        ],
      ),
    );
  }

  Widget _gameCard(ThemeData theme, FbiGame g) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.videogame_asset_outlined),
        title: Text(g.game.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(g.console.name, style: theme.textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.qr_code_2), tooltip: 'Prepare + QR', onPressed: () => _qrCatalog(g)),
            IconButton(icon: const Icon(Icons.send), tooltip: 'Prepare + send to 3DS', onPressed: () => _sendCatalog(g)),
          ],
        ),
      ),
    );
  }

  Widget _instructions(ThemeData theme) {
    const steps = [
      'On the 3DS: open FBI → Remote Install → Receive URLs over the network',
      'Type the IP it shows above, then Send — or scan a QR',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(radius: 11, backgroundColor: theme.colorScheme.secondaryContainer, child: Text('${i + 1}', style: theme.textTheme.labelSmall)),
                const SizedBox(width: 12),
                Expanded(child: Text(steps[i], style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
