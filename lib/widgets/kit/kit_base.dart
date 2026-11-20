import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:retro_toolbox/app.dart' show tokenTheme;
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';

/// The pad's buttons as the hints name them.
enum PadButton {
  a('A'),
  b('B'),
  x('X'),
  y('Y'),
  l('L'),
  r('R'),
  start('START'),
  select('SELECT');

  const PadButton(this.label);

  final String label;

  /// START and SELECT are oblong keys, the face buttons round.
  bool get oblong => this == start || this == select;
}

/// Something a screen offers: a label, what it does (null: shown disabled),
/// and the pad button it answers to, if any.
@immutable
class KitAction {
  const KitAction(this.label, this.onPressed, {this.icon, this.button});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final PadButton? button;

  bool get enabled => onPressed != null;
}

/// One entry of the action bar's hint row: "A Choose".
@immutable
class KitHint {
  const KitHint(this.button, this.label);

  final PadButton button;
  final String label;
}

/// What a badge or a status word means; the colour comes from the style.
enum KitTone { neutral, accent, success, warning, error, info }

Color kitToneColor(BuildContext context, KitTone tone) {
  final k = StyleTokens.of(context);
  return switch (tone) {
    KitTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    KitTone.accent => k.accent,
    KitTone.success => k.success,
    KitTone.warning => k.warning,
    KitTone.error => k.error,
    KitTone.info => k.area(AppArea.info),
  };
}

/// The kit's type scale. Sizes are the Odin 2 sizes; none goes under the
/// device class's text floor.
class KitType {
  KitType._(this.k, this.floor, this.ink, this.muted, this.portrait);

  factory KitType.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final device = DeviceClass.of(context);
    return KitType._(StyleTokens.of(context), device.textFloor, scheme.onSurface, scheme.onSurfaceVariant, device == DeviceClass.portrait);
  }

  final StyleTokens k;
  final double floor;
  final Color ink;
  final Color muted;
  final bool portrait;

  double size(double s) => math.max(s, floor);

  /// The screen's name in the header.
  TextStyle get title =>
      TextStyle(fontFamily: k.titleFont, fontSize: size(portrait ? 20 : 18), fontWeight: FontWeight.w700, height: 1.15, letterSpacing: k.titleCaps ? 0.6 : 0, color: ink);

  /// The one line under a title, row subtitles, secondary text.
  TextStyle get subtitle => TextStyle(fontFamily: StyleTokens.bodyFont, fontSize: size(12), height: 1.3, color: muted);

  /// A row's title, a slot's value.
  TextStyle get row => TextStyle(fontFamily: StyleTokens.bodyFont, fontSize: size(14), fontWeight: FontWeight.w600, height: 1.25, color: ink);

  /// Plain reading text (steps, details).
  TextStyle get body => TextStyle(fontFamily: StyleTokens.bodyFont, fontSize: size(13), height: 1.35, color: ink);

  /// Section labels and small caps captions.
  TextStyle get label => TextStyle(fontFamily: k.titleFont, fontSize: size(11), fontWeight: FontWeight.w700, letterSpacing: 1.2, color: muted);

  /// A verb at the end of a row ("Change").
  TextStyle get verb => TextStyle(fontFamily: k.titleFont, fontSize: size(13), fontWeight: FontWeight.w700, color: k.accent);

  /// Addresses and other values typed by hand on another device.
  TextStyle mono(double s) => TextStyle(fontFamily: 'monospace', fontSize: size(s), fontWeight: FontWeight.w500, color: ink);

  String caps(String s) => k.titleCaps ? s.toUpperCase() : s;
}

/// The corners of a focusable row inside a panel: the ink's shape, which the
/// global focus outline follows.
BorderRadius kitRowRadius(StyleTokens k) => BorderRadius.circular(math.min(k.panelRadius, 12));

/// The style's panel: its material, edge and corners, with a line between
/// [children]. Rows inside it ink and focus on the panel.
class KitPanel extends StatelessWidget {
  const KitPanel({super.key, required this.children, this.padding = EdgeInsets.zero, this.edge, this.divided = true});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  /// Null: the style's panel line.
  final Color? edge;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final rows = <Widget>[];
    for (final c in children) {
      if (rows.isNotEmpty && divided) rows.add(Divider(height: 1, thickness: 1, color: k.panelLine));
      rows.add(c);
    }
    return Material(
      color: k.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(k.panelRadius), side: BorderSide(color: edge ?? k.panelLine)),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: rows)),
    );
  }
}

/// A section label over a panel: "INPUT", "OPTIONS".
class KitLabel extends StatelessWidget {
  const KitLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 0),
        child: Text(text.toUpperCase(), style: KitType.of(context).label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

/// A pad button's key cap, as the hints and the primary show it.
class PadKey extends StatelessWidget {
  const PadKey(this.button, {super.key, this.color, this.textColor});

  final PadButton button;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final side = t.size(11) + 9;
    return Container(
      constraints: BoxConstraints(minWidth: side, minHeight: side),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(color: color ?? Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(button.oblong ? 4 : side / 2)),
      // Centred in the cap without growing to the space it is given.
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(button.label, style: TextStyle(fontFamily: StyleTokens.displayFont, fontSize: t.size(11), fontWeight: FontWeight.w700, height: 1, color: textColor ?? Colors.white)),
      ),
    );
  }
}

/// A short word in a tinted box: a row's state ("Keep", "Up to date").
class KitBadge extends StatelessWidget {
  const KitBadge(this.label, {super.key, this.tone = KitTone.neutral});

  final String label;
  final KitTone tone;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final c = kitToneColor(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(math.min(t.k.buttonRadius, 6))),
      child: Text(t.caps(label), style: TextStyle(fontFamily: t.k.titleFont, fontSize: t.size(12), fontWeight: FontWeight.w700, letterSpacing: 0.4, color: c)),
    );
  }
}

/// [child] in the theme of [area]: in a style whose accent follows the area
/// (Classic), the area's colour becomes the accent of every control under it.
class KitArea extends StatelessWidget {
  const KitArea({super.key, required this.area, required this.child});

  final AppArea? area;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final inner = k.inArea(area);
    if (identical(inner, k)) return child;
    final outer = Theme.of(context);
    // The text theme stays the outer one: it carries the device's text floor.
    final theme = tokenTheme(inner).copyWith(textTheme: outer.textTheme, primaryTextTheme: outer.primaryTextTheme);
    return Theme(data: theme, child: child);
  }
}

/// Space between the panels of a column.
const kitGap = 8.0;
