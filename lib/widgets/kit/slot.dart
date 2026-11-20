import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icon.dart';
import 'package:retro_toolbox/widgets/pixel_icon/pixel_icons.dart';

/// Between the parts of a shortened path.
const pathSeparator = ' › ';

/// The ellipsis that stands for the parts left out.
const pathEllipsis = '…';

/// Roots a path is shown from, most specific first.
final _roots = <(RegExp, String)>[
  (RegExp(r'^/storage/emulated/0/Download(?=/|$)'), 'Downloads'),
  (RegExp(r'^/sdcard/Download(?=/|$)'), 'Downloads'),
  (RegExp(r'^/storage/emulated/0(?=/|$)'), 'Internal'),
  (RegExp(r'^/sdcard(?=/|$)'), 'Internal'),
  (RegExp(r'^/storage/[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}(?=/|$)'), 'SD card'),
  (RegExp(r'^/mnt/(SDCARD|sdcard|mmc|sdcard2)(?=/|$)'), 'SD card'),
];

String? _home() {
  if (kIsWeb) return null;
  final h = Platform.environment['HOME'];
  return h == null || h.length < 2 ? null : h;
}

/// [path] as parts to show: from the nearest known root (Internal, SD card,
/// Downloads, the home folder), and from a ROMs folder inside it when the
/// path goes below one. "/storage/emulated/0/ROMs/psx" is ROMs, psx;
/// "/storage/emulated/0/ROMs" is Internal, ROMs.
List<String> pathParts(String path, {String? home}) {
  var p = path.replaceAll('\\', '/');
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  String? root;
  var rest = p;
  for (final (re, name) in _roots) {
    final m = re.firstMatch(p);
    if (m != null) {
      root = name;
      rest = p.substring(m.end);
      break;
    }
  }
  final h = home ?? _home();
  if (root == null && h != null && (p == h || p.startsWith('$h/'))) {
    root = 'Home';
    rest = p.substring(h.length);
  }
  var parts = rest.split('/').where((s) => s.isNotEmpty).toList();
  if (root == null) {
    if (parts.isEmpty) return [p];
    parts[0] = p.startsWith('/') ? '/${parts[0]}' : parts[0];
  } else {
    parts = [root, ...parts];
  }
  // The ROMs folder is the root for anything below it.
  final roms = parts.lastIndexWhere((s) => s.replaceFirst('/', '').toLowerCase() == 'roms');
  if (roms >= 0 && roms < parts.length - 1) parts = ['ROMs', ...parts.sublist(roms + 1)];
  return parts;
}

/// The longest form of [parts] that [fits]: whole; then with parts left out
/// after the root (the deepest kept); then the last part cut in the middle.
String fitPath(List<String> parts, bool Function(String) fits) {
  if (parts.isEmpty) return '';
  final whole = parts.join(pathSeparator);
  if (parts.length == 1 || fits(whole)) return parts.length == 1 ? _cutMiddle('', parts.single, fits) : whole;
  for (var from = 2; from < parts.length; from++) {
    final s = [parts.first, pathEllipsis, ...parts.sublist(from)].join(pathSeparator);
    if (fits(s)) return s;
  }
  final prefix = parts.length > 2 ? '${parts.first}$pathSeparator$pathEllipsis$pathSeparator' : '${parts.first}$pathSeparator';
  final withRoot = _cutMiddle(prefix, parts.last, fits);
  return fits(withRoot) ? withRoot : _cutMiddle('', parts.last, fits);
}

/// [prefix] then [s] with characters taken out of its middle until it fits.
String _cutMiddle(String prefix, String s, bool Function(String) fits) {
  if (fits('$prefix$s')) return '$prefix$s';
  var lo = 0, hi = s.length - 1;
  String at(int keep) {
    final head = (keep + 1) ~/ 2, tail = keep ~/ 2;
    return '$prefix${s.substring(0, head)}$pathEllipsis${s.substring(s.length - tail)}';
  }

  // The most characters kept that still fit.
  while (lo < hi) {
    final mid = (lo + hi + 1) ~/ 2;
    if (fits(at(mid))) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return at(lo);
}

/// A path shortened to fit one line: from its known root, parts left out in
/// the middle, never cut at the end (the file name stays readable).
class PathText extends StatelessWidget {
  const PathText(this.path, {super.key, this.style, this.home});

  final String path;
  final TextStyle? style;

  /// Tests: the home folder (null: \$HOME).
  final String? home;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? KitType.of(context).row;
    // Measured as Text paints it: on top of the default text style.
    final painted = DefaultTextStyle.of(context).style.merge(style);
    final parts = pathParts(path, home: home);
    return LayoutBuilder(builder: (context, box) {
      final scaler = MediaQuery.textScalerOf(context);
      final direction = Directionality.of(context);
      bool fits(String s) {
        if (!box.hasBoundedWidth) return true;
        final tp = TextPainter(text: TextSpan(text: s, style: painted), textDirection: direction, textScaler: scaler, maxLines: 1)..layout();
        final w = tp.width;
        tp.dispose();
        return w <= box.maxWidth;
      }

      return Text(fitPath(parts, fits), style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.clip, semanticsLabel: path);
    });
  }
}

/// An input of a tool: a file or folder (or any value) with one verb. Empty,
/// the whole row is the button and says what to choose; filled, it shows the
/// value and [verb]. [lockedReason]: shown, not changeable, and why ("Stop the
/// server to change").
class Slot extends StatelessWidget {
  const Slot({
    super.key,
    required this.label,
    this.path,
    this.value,
    this.emptyText = 'Choose',
    this.verb = 'Change',
    this.folder = false,
    this.icon,
    this.glyph,
    this.onPick,
    this.lockedReason,
    this.autofocus = false,
    this.focusNode,
  });

  final String label;

  /// A file or folder, shown shortened; the whole path in the tooltip.
  final String? path;

  /// Any other value ("412 games, 96 updates").
  final String? value;

  /// What an empty slot says: "Choose a disc image".
  final String emptyText;
  final String verb;
  final bool folder;
  final IconData? icon;
  final PixelGlyph? glyph;
  final VoidCallback? onPick;
  final String? lockedReason;
  final bool autofocus;
  final FocusNode? focusNode;

  bool get filled => path != null || value != null;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final locked = lockedReason != null;
    final onTap = locked ? null : onPick;
    final glyph = this.glyph ?? (folder ? PixelIcons.folder : PixelIcons.file);
    final icon = this.icon ?? (folder ? Icons.folder_outlined : Icons.insert_drive_file_outlined);
    final Widget shown;
    if (path != null) {
      shown = PathText(path!, style: t.row);
    } else if (value != null) {
      shown = Text(value!, style: t.row, maxLines: 1, overflow: TextOverflow.ellipsis);
    } else {
      shown = Text(emptyText, style: t.row.copyWith(color: onTap == null ? t.muted : k.accent), maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 8).toDouble())),
            child: k.pixelIcons ? PixelIcon(glyph, size: 18, color: k.accent) : Icon(icon, size: 18, color: k.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              shown,
            ]),
          ),
          if (locked) ...[
            const SizedBox(width: 8),
            Icon(Icons.lock_outline, size: 16, color: t.muted),
            const SizedBox(width: 4),
            Flexible(child: Text(lockedReason!, style: t.subtitle, maxLines: 2, textAlign: TextAlign.end)),
          ] else if (filled && onTap != null) ...[
            const SizedBox(width: 10),
            Text(verb, style: t.verb),
          ],
        ]),
      ),
    );
    if (path != null) row = Tooltip(message: path!, child: row);
    return InkWell(focusNode: focusNode, autofocus: autofocus, borderRadius: kitRowRadius(k), onTap: onTap, child: row);
  }
}
