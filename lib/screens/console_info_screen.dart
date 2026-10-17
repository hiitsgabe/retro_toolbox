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

typedef Mount = ({String label, String mount, int total, int free});

/// `df -Pk` for each path; paths on a mount already listed are dropped (the
/// first label wins), and paths `df` can't read are skipped.
Future<List<Mount>> readMounts(List<({String label, String path})> paths) async {
  final out = <Mount>[];
  for (final p in paths) {
    try {
      final r = await Process.run('df', ['-Pk', p.path]);
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
  final r = await Process.run('iwgetid', ['-r']);
  final s = r.stdout.toString().trim();
  return r.exitCode == 0 && s.isNotEmpty ? s : null;
}

const _dash = '—';

/// Handheld dashboard: device, storage, memory, battery, network and system
/// facts, plus an Advanced process list where non-critical processes can be ended.
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
    var r = await _processes.end(e.pid);
    if (r == EndResult.stillRunning && mounted && await _confirm('${e.name} is still running', 'Force end stops it at once.', 'Force end')) {
      r = await _processes.end(e.pid, force: true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Console Info')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 520;
          // Two columns of equal-height cards when wide, stacked otherwise.
          Widget pair(Widget a, Widget b) => wide
              ? IntrinsicHeight(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 12), b]);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(s),
              const SizedBox(height: 12),
              pair(_memory(s.mem), _power(s)),
              const SizedBox(height: 12),
              pair(_storage(), _network(ip, s.hostname)),
              const SizedBox(height: 12),
              _system(context, s, wide ? (box.maxWidth - 28 - 12) / 2 : null),
              const SizedBox(height: 12),
              _advanced(),
            ],
          );
        }),
      ),
    );
  }

  Widget _header(SystemSnapshot s) {
    final t = Theme.of(context).textTheme;
    final sub = [s.firmware, s.osVersion].nonNulls.join(' · ');
    return _InfoCard(
      accent: const Color(0xFF6C4AB6),
      autofocus: true,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.videogame_asset, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.deviceName ?? _dash,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                Text(sub.isEmpty ? _dash : sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _memory(MemInfo m) {
    final t = Theme.of(context).textTheme;
    final used = m.usedBytes, total = m.totalBytes;
    final swapTotal = m.swapTotalBytes ?? 0;
    return _InfoCard(
      title: 'Memory',
      icon: Icons.memory,
      accent: const Color(0xFF167C80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _big(used == null ? _dash : formatBytes(used), total == null ? null : ' / ${formatBytes(total)}'),
          const SizedBox(height: 8),
          _Bar(used == null || total == null || total == 0 ? null : used / total),
          const SizedBox(height: 6),
          Text(
            [
              if (m.availableBytes != null) '${formatBytes(m.availableBytes!)} free',
              if (swapTotal > 0) 'swap ${formatBytes(swapTotal - (m.swapFreeBytes ?? 0))} / ${formatBytes(swapTotal)}',
            ].join(' · ').ifEmpty(_dash),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _power(SystemSnapshot s) {
    final pct = s.battery?.percent, charging = s.battery?.charging, temp = s.cpuTempC;
    final t = Theme.of(context).textTheme;
    Widget half(IconData icon, String value, String label, double? level, Color? color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: color ?? Colors.white, size: 22),
                const SizedBox(width: 4),
                Flexible(child: _big(value, null)),
              ]),
              const SizedBox(height: 8),
              _Bar(level, color: color),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: Colors.white70)),
            ],
          ),
        );
    return _InfoCard(
      title: 'Battery & temperature',
      icon: Icons.bolt,
      accent: const Color(0xFF2E9E4F),
      child: Row(
        children: [
          half(
            charging == true ? Icons.battery_charging_full : (pct != null && pct < 20 ? Icons.battery_alert : Icons.battery_full),
            pct == null ? _dash : '$pct%',
            charging == null ? _dash : (charging ? 'Charging' : 'On battery'),
            pct == null ? null : pct / 100,
            pct != null && pct < 20 && charging != true ? Colors.redAccent : null,
          ),
          const SizedBox(width: 16),
          half(
            Icons.thermostat,
            temp == null ? _dash : '${temp.toStringAsFixed(1)} °C',
            'CPU',
            temp == null ? null : (temp / 100).clamp(0, 1).toDouble(),
            temp == null ? null : (temp >= 75 ? Colors.redAccent : (temp >= 60 ? Colors.amberAccent : null)),
          ),
        ],
      ),
    );
  }

  Widget _storage() {
    final t = Theme.of(context).textTheme;
    return _InfoCard(
      title: 'Storage',
      icon: Icons.sd_storage,
      accent: const Color(0xFFB4632E),
      child: _mounts.isEmpty
          ? _big(_dash, null)
          : Column(
              children: [
                for (final (i, m) in _mounts.indexed) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: m.label, style: t.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                            TextSpan(text: '  ${m.mount}', style: t.labelSmall?.copyWith(color: Colors.white54)),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${formatBytes(m.free)} free of ${formatBytes(m.total)}', style: t.bodySmall?.copyWith(color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _Bar(m.total == 0 ? null : (m.total - m.free) / m.total, color: m.total > 0 && m.free / m.total < 0.1 ? Colors.amberAccent : null),
                ],
              ],
            ),
    );
  }

  Widget _network(String? ip, String? hostname) {
    final t = Theme.of(context).textTheme;
    return _InfoCard(
      title: 'Network',
      icon: Icons.wifi,
      accent: const Color(0xFF2E6DB4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ip ?? _dash, style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          if (ip != null) Text('Use this address in FTP, SMB and Retro Tools Server', style: t.bodySmall?.copyWith(color: Colors.white70)),
          const SizedBox(height: 8),
          _Field('Hostname', hostname),
          if (_ssid != null) _Field('Wi-Fi', _ssid),
        ],
      ),
    );
  }

  /// [col]: width of each of the card's two field columns; null for one column.
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
    ];
    return _InfoCard(
      title: 'System',
      icon: Icons.info_outline,
      accent: const Color(0xFF55606E),
      child: Wrap(
        spacing: 12,
        children: [for (final f in fields) SizedBox(width: col?.floorToDouble(), child: f)],
      ),
    );
  }

  Widget _advanced() {
    final procs = _procs;
    final maxRss = procs == null || procs.isEmpty ? 1 : procs.map((p) => p.rssBytes).reduce((a, b) => a > b ? a : b);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        shape: const Border(),
        leading: const Icon(Icons.tune),
        title: const Text('Advanced', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(procs == null || !_expanded ? 'Running processes' : '${procs.length} running processes'),
        onExpansionChanged: (v) {
          _expanded = v;
          if (v) _loadProcs();
        },
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          if (procs == null)
            const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())
          else if (procs.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No processes'))
          else
            for (final p in procs) _ProcessRow(p, maxRss: maxRss, onEnd: () => _end(p)),
        ],
      ),
    );
  }

  Widget _big(String value, String? suffix) {
    final t = Theme.of(context).textTheme;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: value, style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
        if (suffix != null) TextSpan(text: suffix, style: t.bodyMedium?.copyWith(color: Colors.white70)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Same darkened accent gradient as the menu tiles (see MenuTileFace).
List<Color> _gradient(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  return [hsl.withLightness(0.30).withSaturation((hsl.saturation * 0.85).clamp(0.0, 1.0)).toColor(), hsl.withLightness(0.15).toColor()];
}

/// A focusable card (so the d-pad can step through and scroll the page).
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.accent, required this.child, this.title, this.icon, this.autofocus = false});
  final Color accent;
  final Widget child;
  final String? title;
  final IconData? icon;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      autofocus: autofocus,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _gradient(accent))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Row(children: [
                    Icon(icon, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(title!.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white70, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                ],
                child,
              ],
            ),
          ),
        ),
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
        backgroundColor: Colors.white.withValues(alpha: 0.14),
        color: color ?? Colors.white.withValues(alpha: 0.9),
      );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: t.bodySmall?.copyWith(color: Colors.white60))),
          Expanded(child: Text(value ?? _dash, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: Colors.white))),
        ],
      ),
    );
  }
}

const _avatarColors = [Color(0xFF2E6DB4), Color(0xFF167C80), Color(0xFFE56717), Color(0xFF2E7D5B), Color(0xFF7A5CA8), Color(0xFFB4632E), Color(0xFF9C4DA0)];

class _ProcessRow extends StatelessWidget {
  const _ProcessRow(this.p, {required this.maxRss, required this.onEnd});
  final ProcessEntry p;
  final int maxRss;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = p.protected ? const Color(0xFF55606E) : _avatarColors[p.name.hashCode % _avatarColors.length];
    return ListTile(
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: accent,
        child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      title: Row(
        children: [
          Expanded(child: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
          Text(formatBytes(p.rssBytes), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.cmdline, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 4),
          _Bar(maxRss == 0 ? 0 : p.rssBytes / maxRss, height: 4, color: accent),
        ],
      ),
      trailing: p.protected
          ? SizedBox(width: 48, child: Icon(Icons.lock, size: 20, color: muted))
          : IconButton(icon: const Icon(Icons.close), tooltip: 'End ${p.name}', onPressed: onEnd),
    );
  }
}
