import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:roms_downloader/providers/fbi_server_provider.dart';
import 'package:roms_downloader/providers/settings_provider.dart';
import 'package:roms_downloader/services/fbi_server_service.dart';
import 'package:roms_downloader/widgets/tool_description.dart';

/// Serves 3DS .cia titles and installs them on a console running FBI, either by
/// pushing the URL to FBI's "Receive URLs over the network" or via a QR code.
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

  // FBI installs .cia only. A .3ds/.cci title must be converted first.
  bool _needsConversion(FbiGame g) {
    final t = g.game.title.toLowerCase();
    return !(t.endsWith('.cia'));
  }

  /// Explains that a 3DS cart image can't go straight to FBI and routes the
  /// user to convert it (which needs boot9.bin).
  void _showNeedsConversion(FbiGame g) {
    final hasBoot9 = ref.read(settingsProvider).boot9Path?.isNotEmpty ?? false;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Needs conversion to CIA'),
        content: Text(
          'FBI installs .cia files. “${g.game.title}” is a 3DS cart image (.3ds/.cci), so it has to be '
          'converted first — use Tools → 3DS → CIA${hasBoot9 ? '' : ', which needs your console\'s boot9.bin'}. '
          'Once converted, serve the .cia (e.g. via Retro Tools Server) and install it here.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _send(FbiGame g) async {
    if (_needsConversion(g)) return _showNeedsConversion(g);
    final ip = _ip.text.trim();
    if (ip.isEmpty) return _snack('Enter your 3DS IP first.');
    await ref.read(fbiServerProvider.notifier).setThreeDsIp(ip);
    try {
      await ref.read(fbiServerProvider.notifier).sendToThreeDs(g.url);
      _snack('Sent “${g.game.title}” to your 3DS.');
    } catch (e) {
      _snack('Failed to reach FBI at $ip:5000 — $e');
    }
  }

  // Render the QR to a PNG and show it as an image. QrImageView's CustomPaint
  // renders blank under Impeller (macOS/Android), so we rasterize instead.
  Future<Uint8List?> _qrPng(String url) async {
    try {
      final data = await QrPainter(data: url, version: QrVersions.auto, gapless: true).toImageData(600);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  void _showQr(FbiGame g) {
    if (_needsConversion(g)) return _showNeedsConversion(g);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(g.game.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FutureBuilder<Uint8List?>(
              future: _qrPng(g.url),
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const ToolDescription(
            icon: Icons.install_mobile,
            text: 'Installs 3DS .cia titles onto a console running FBI over the local network. Turn the '
                'server on, then push a game to your 3DS or scan its QR in FBI.',
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable server'),
                subtitle: Text(state.running ? 'Serving 3DS titles' : 'Off'),
                value: state.running,
                onChanged: (v) => v ? notifier.enable() : notifier.disable(),
              ),
            ),
          ),
          if (!state.running) ...[
            const SizedBox(height: 16),
            TextFormField(
              initialValue: '${state.port}',
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Server port', border: OutlineInputBorder(), isDense: true),
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
          if (state.running) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _ip,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '3DS IP address',
                hintText: 'shown in FBI → Remote Install → Receive URLs',
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
                Text('3DS titles', style: theme.textTheme.titleSmall),
                const Spacer(),
                IconButton(icon: const Icon(Icons.refresh, size: 20), tooltip: 'Reload', onPressed: () => notifier.refreshGames()),
              ],
            ),
            const SizedBox(height: 8),
            ..._gameList(theme, state, notifier),
          ],
        ],
      ),
    );
  }

  List<Widget> _gameList(ThemeData theme, FbiServerState state, FbiServerNotifier notifier) {
    if (state.gamesLoading) {
      return const [Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))];
    }
    if (state.games.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text('No 3DS (.cia) titles in your catalog.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() { _search.clear(); _query = ''; _page = 0; })),
        ),
        onChanged: (v) => setState(() { _query = v.trim(); _page = 0; }),
      ),
      const SizedBox(height: 8),
      if (filtered.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('No matches.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        )
      else ...[
        for (final g in slice) _gameCard(theme, g, state.threeDsIp.trim().isNotEmpty),
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

  Widget _gameCard(ThemeData theme, FbiGame g, bool canSend) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.videogame_asset_outlined),
        title: Text(g.game.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Flexible(child: Text(g.console.name, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
            if (_needsConversion(g)) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: theme.colorScheme.tertiaryContainer, borderRadius: BorderRadius.circular(6)),
                child: Text('needs CIA', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onTertiaryContainer)),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.qr_code_2), tooltip: 'QR', onPressed: () => _showQr(g)),
            IconButton(
              icon: const Icon(Icons.send),
              tooltip: canSend ? 'Send to 3DS' : 'Enter your 3DS IP to send',
              onPressed: canSend ? () => _send(g) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _instructions(ThemeData theme) {
    const steps = [
      'On the 3DS: open FBI → Remote Install → Receive URLs over the network',
      'Type the IP it shows above, then Send — or scan a game’s QR',
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
