import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retro_toolbox/providers/settings_provider.dart';
import 'package:retro_toolbox/services/directory_service.dart';
import 'package:retro_toolbox/services/process_list.dart';
import 'package:retro_toolbox/services/system_info.dart';
import 'package:retro_toolbox/services/tinfoil_server_service.dart';
import 'package:retro_toolbox/utils/formatters.dart';
import 'package:retro_toolbox/utils/handheld.dart';
import 'package:retro_toolbox/utils/network.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

typedef Mount = ({String label, String mount, int total, int free});

/// `df -Pk` for each path; paths on a mount already listed are dropped (the
/// first label wins), and paths `df` can't read are skipped.
Future<List<Mount>> readMounts(List<({String label, String path})> paths) async {
  final out = <Mount>[];
  for (final p in paths) {
    try {
      // A dead network mount can hang df; skip it rather than freeze the refresh.
      final r = await Process.run('df', ['-Pk', p.path]).timeout(const Duration(seconds: 5));
      if (r.exitCode != 0) continue;
      final lines = r.stdout.toString().trim().split('\n');
      if (lines.length < 2) continue;
      final f = lines[1].trim().split(RegExp(r'\s+'));
      final total = int.tryParse(f.length > 5 ? f[1] : ''), free = int.tryParse(f.length > 5 ? f[3] : '');
      final mount = f.length > 5 ? f.sublist(5).join(' ') : '';
      if (total == null || free == null || out.any((m) => m.mount == mount)) continue;
      out.add((label: p.label, mount: mount, total: total * 1024, free: free * 1024));
    } catch (_) {}
  }
  return out;
}

Future<List<Mount>> _defaultMounts() async {
  String? downloads;
  try {
    downloads = await DirectoryService().getDownloadDir();
  } catch (_) {}
  return readMounts([
    (label: 'System', path: '/'),
    (label: 'ROMs', path: '/roms'),
    (label: 'ROMs 2', path: '/roms2'),
    if (downloads != null) (label: 'Downloads', path: downloads),
  ]);
}

Future<String?> _defaultSsid() async {
  final r = await Process.run('iwgetid', ['-r']).timeout(const Duration(seconds: 5));
  final s = r.stdout.toString().trim();
  return r.exitCode == 0 && s.isNotEmpty ? s : null;
}

/// Handheld dashboard: device, storage, memory, battery, network and system
/// facts, plus an Advanced process list where non-critical processes can be
/// ended. Panels only, no action bar: nothing here runs on Start.
class ConsoleInfoScreen extends ConsumerStatefulWidget {
  const ConsoleInfoScreen({
    super.key,
    this.reader,
    this.processes,
    this.refresh = const Duration(seconds: 3),
    this.mounts,
    this.addresses,
    this.ssid,
  });

  final SystemInfoReader? reader;
  final ProcessList? processes;
  final Duration refresh;
  final Future<List<Mount>> Function()? mounts;
  final Future<List<String>> Function()? addresses;
  final Future<String?> Function()? ssid;

  @override
  ConsumerState<ConsoleInfoScreen> createState() => _ConsoleInfoScreenState();
}

class _ConsoleInfoScreenState extends ConsumerState<ConsoleInfoScreen> {
  late final _reader = widget.reader ?? SystemInfoReader();
  late final _processes = widget.processes ?? ProcessList();
  Timer? _timer;
  bool _busy = false, _expanded = false;

  SystemSnapshot? _snap;
  List<Mount> _mounts = const [];
  List<String> _addresses = const [];
  String? _ssid, _version;
  List<ProcessEntry>? _procs;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(widget.refresh, (_) => _load());
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static Future<T> _safe<T>(Future<T> Function() f, T fallback) async {
    try {
      return await f();
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _load() async {
    if (_busy) return; // ponytail: a slow df skips ticks instead of piling up reads
    _busy = true;
    final snap = _safe(_reader.read, const SystemSnapshot());
    final mounts = _safe(widget.mounts ?? _defaultMounts, const <Mount>[]);
    final addrs = _safe(widget.addresses ?? TinfoilServerService.localAddresses, const <String>[]);
    final ssid = _safe(widget.ssid ?? _defaultSsid, null);
    final procs = _expanded ? _safe(_processes.list, const <ProcessEntry>[]) : null;
    final (s, m, a, w, p) = (await snap, await mounts, await addrs, await ssid, await procs);
    _busy = false;
    if (!mounted) return;
    setState(() {
      _snap = s;
      _mounts = m;
      _addresses = a;
      _ssid = w;
      if (p != null) _procs = p;
    });
  }

  Future<void> _loadProcs() async {
    final p = await _safe(_processes.list, const <ProcessEntry>[]);
    if (mounted) setState(() => _procs = p);
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(autofocus: true, onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _end(ProcessEntry e) async {
    if (!await _confirm('End ${e.name}?', 'Anything unsaved in it is lost.', 'End') || !mounted) return;
    var r = await _processes.end(e.pid, name: e.name);
    if (r == EndResult.stillRunning && mounted && await _confirm('${e.name} is still running', 'Force end stops it at once.', 'Force end')) {
      r = await _processes.end(e.pid, force: true, name: e.name);
    }
    if (!mounted) return;
    final msg = switch (r) {
      EndResult.ended => null,
      EndResult.alreadyGone => '${e.name} already exited',
      EndResult.stillRunning => '${e.name} is still running',
      EndResult.refused => '${e.name} is protected',
    };
    if (msg != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    await _loadProcs();
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap ?? const SystemSnapshot();
    final ip = orderAddresses(_addresses, ref.watch(settingsProvider.select((x) => x.preferredLocalIp))).firstOrNull;
    return KitScaffold(
      title: 'Console Info',
      subtitle: 'Storage, battery, network and processes',
      icon: Icons.memory,
      glyph: PixelIcons.consoleInfo,
      area: AppArea.tools,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 520;
          // Two columns of equal-height panels when wide, stacked otherwise.
          Widget pair(Widget a, Widget b) => wide
              ? IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: kitGap), Expanded(child: b)]),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: kitGap), b]);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(s),
              const SizedBox(height: kitGap),
              pair(_storage(), _power(s)),
              const SizedBox(height: kitGap),
              pair(_memory(s.mem), _network(ip, s.hostname)),
              const SizedBox(height: kitGap),
              _system(context, s, wide ? (box.maxWidth - 24 - kitGap) / 2 : null),
              const SizedBox(height: kitGap),
              _advanced(),
            ],
          );
        }),
      ),
    );
  }

  Widget _header(SystemSnapshot s) {
    final t = KitType.of(context);
    final sub = [s.firmware, s.osVersion].nonNulls.join(' · ');
    return _InfoPanel(
      autofocus: true,
      child: Row(
        children: [
          const KitIconTile(icon: Icons.videogame_asset, glyph: PixelIcons.consoleInfo, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.deviceName ?? 'This device', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.title),
                if (sub.isNotEmpty) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memory(MemInfo m) {
    final t = KitType.of(context);
    final used = m.usedBytes, total = m.totalBytes;
    final swapTotal = m.swapTotalBytes ?? 0;
    final line = [
      if (m.availableBytes != null) '${formatBytes(m.availableBytes!)} free',
      if (swapTotal > 0) 'swap ${formatBytes(swapTotal - (m.swapFreeBytes ?? 0))} / ${formatBytes(swapTotal)}',
    ].join(' · ');
    return _InfoPanel(
      title: 'Memory',
      icon: Icons.memory,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _big(used == null ? _unknown : formatBytes(used), total == null ? null : ' / ${formatBytes(total)}'),
          const SizedBox(height: 8),
          _Bar(used == null || total == null || total == 0 ? null : used / total),
          if (line.isNotEmpty) ...[const SizedBox(height: 6), Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle)],
        ],
      ),
    );
  }

  Widget _power(SystemSnapshot s) {
    final pct = s.battery?.percent, charging = s.battery?.charging, temp = s.cpuTempC;
    final t = KitType.of(context);
    final k = t.k;
    Widget half(IconData icon, String value, String? label, double? level, Color? color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: color ?? k.accent, size: 20),
                const SizedBox(width: 4),
                Flexible(child: _big(value, null)),
              ]),
              const SizedBox(height: 8),
              _Bar(level, color: color),
              if (label != null) ...[const SizedBox(height: 6), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle)],
            ],
          ),
        );
    return _InfoPanel(
      title: 'Battery & temperature',
      icon: Icons.bolt,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          half(
            charging == true ? Icons.battery_charging_full : (pct != null && pct < 20 ? Icons.battery_alert : Icons.battery_full),
            pct == null ? _unknown : '$pct%',
            charging == null ? null : (charging ? 'Charging' : 'On battery'),
            pct == null ? null : pct / 100,
            pct != null && pct < 20 && charging != true ? k.error : null,
          ),
          const SizedBox(width: 16),
          half(
            Icons.thermostat,
            temp == null ? _unknown : '${temp.toStringAsFixed(1)} °C',
            'CPU',
            temp == null ? null : (temp / 100).clamp(0, 1).toDouble(),
            temp == null ? null : (temp >= 75 ? k.error : (temp >= 60 ? k.warning : null)),
          ),
        ],
      ),
    );
  }

  Widget _storage() {
    final t = KitType.of(context);
    return _InfoPanel(
      title: 'Storage',
      icon: Icons.sd_storage,
      child: _mounts.isEmpty
          ? _big(_unknown, null)
          : Column(
              children: [
                for (final (i, m) in _mounts.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: m.label, style: t.row),
                            TextSpan(text: '  ${m.mount}', style: t.subtitle),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${formatBytes(m.free)} free of ${formatBytes(m.total)}', style: t.subtitle),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _Bar(m.total == 0 ? null : (m.total - m.free) / m.total, color: m.total > 0 && m.free / m.total < 0.1 ? t.k.warning : null),
                ],
              ],
            ),
    );
  }

  Widget _network(String? ip, String? hostname) {
    final t = KitType.of(context);
    return _InfoPanel(
      title: 'Network',
      icon: Icons.wifi,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ip ?? 'Not connected', style: ip == null ? t.row.copyWith(color: t.muted) : t.mono(18).copyWith(fontWeight: FontWeight.w700)),
          if (ip != null) Text('Use this address in FTP, SMB and Retro Tools Server', style: t.subtitle),
          const SizedBox(height: 8),
          _Field('Hostname', hostname),
          _Field('Wi-Fi', _ssid),
        ],
      ),
    );
  }

  /// [col]: width of each of the panel's two field columns; null for one column.
  Widget _system(BuildContext context, SystemSnapshot s, double? col) {
    final size = View.of(context).physicalSize;
    final os = [s.osName, s.osVersion].nonNulls.join(' ');
    final fields = [
      _Field('OS', os.isEmpty ? null : os),
      _Field('Kernel', s.kernel),
      _Field('CPU', s.cpuModel == null ? null : '${s.cpuModel} × ${s.cores}'),
      _Field('glibc', s.glibc),
      _Field('Display', '${Handheld.framebuffer ? 'Framebuffer' : 'DRM/KMS'} · ${size.width.round()}×${size.height.round()}'),
      _Field('App', _version == null ? null : 'Retro Toolbox $_version'),
    ].where((f) => f.value != null);
    return _InfoPanel(
      title: 'System',
      icon: Icons.info_outline,
      child: Wrap(
        spacing: 12,
        children: [for (final f in fields) SizedBox(width: col?.floorToDouble(), child: f)],
      ),
    );
  }

  Widget _advanced() {
    final procs = _procs;
    final maxRss = procs == null || procs.isEmpty ? 1 : procs.map((p) => p.rssBytes).reduce((a, b) => a > b ? a : b);
    return OptionList(children: [
      OptionExpander(
        subtitle: procs == null || !_expanded ? 'Running processes' : '${procs.length} running processes',
        onChanged: (v) {
          _expanded = v;
          if (v) _loadProcs();
        },
        children: [
          if (procs == null)
            const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
          else if (procs.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No processes'))
          else
            for (final p in procs) _ProcessRow(p, maxRss: maxRss, onEnd: () => _end(p)),
        ],
      ),
    ]);
  }

  Widget _big(String value, String? suffix) {
    final t = KitType.of(context);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: value, style: t.row.copyWith(fontSize: t.size(20), fontWeight: FontWeight.w700)),
        if (suffix != null) TextSpan(text: suffix, style: t.subtitle.copyWith(fontSize: t.size(13))),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A value the device does not report.
const _unknown = 'Unknown';

/// A focusable panel (so the d-pad can step through and scroll the page).
class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.child, this.title, this.icon, this.autofocus = false});
  final Widget child;
  final String? title;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return Focus(
      autofocus: autofocus,
      child: KitPanel(
        padding: const EdgeInsets.all(12),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Row(children: [
                  Icon(icon, size: 16, color: t.k.accent),
                  const SizedBox(width: 6),
                  Flexible(child: Text(title!.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.label)),
                ]),
                const SizedBox(height: 10),
              ],
              child,
            ],
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.value, {this.color, this.height = 8});
  final double? value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) => LinearProgressIndicator(
        // A null value would animate forever: unknown is an empty track.
        value: (value ?? 0).clamp(0.0, 1.0),
        minHeight: height,
        borderRadius: BorderRadius.circular(height / 2),
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        color: color ?? StyleTokens.of(context).accent,
      );
}

/// A label and its value; nothing when the device does not report it.
class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null) return const SizedBox.shrink();
    final t = KitType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: t.subtitle)),
          Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body)),
        ],
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow(this.p, {required this.maxRss, required this.onEnd});
  final ProcessEntry p;
  final int maxRss;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final tint = p.protected ? t.muted : t.k.accent;
    return Padding(
      key: ValueKey('process-${p.pid}'),
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: tint.withValues(alpha: 0.2),
          child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: t.row.copyWith(color: tint)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.row)),
              Text(formatBytes(p.rssBytes), style: t.subtitle),
            ]),
            Text(p.cmdline, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.subtitle),
            const SizedBox(height: 4),
            _Bar(maxRss == 0 ? 0 : p.rssBytes / maxRss, height: 4, color: tint),
          ]),
        ),
        const SizedBox(width: 4),
        p.protected
            ? SizedBox(width: 48, child: Icon(Icons.lock, size: 20, color: t.muted))
            : IconButton(icon: const Icon(Icons.close), tooltip: 'End ${p.name}', onPressed: onEnd),
      ]),
    );
  }
}
