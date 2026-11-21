import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// Space a dependent row is pushed in by, under the row it depends on.
const settingsIndent = 28.0;

/// Half the gap between two settings items: every row, header and info line
/// carries it above and below, so any two of them sit 6 apart.
const settingsHalfGap = 3.0;

/// The settings palette, from the style (the kit's panel): the tile, the
/// focused tile, the line between panes.
extension SettingsColors on StyleTokens {
  Color get settingsTile => panel;
  Color get settingsTileFocused => Color.alphaBlend(Colors.white.withValues(alpha: 0.08), solidPanel);
  Color get settingsLine => panelLine;
}

/// Whether focus is showing (a d-pad or keyboard moved it, not a touch).
bool get settingsFocusShows => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

/// A rounded tile that shows its own focus: a lighter fill and a 2 px outline
/// inside its edge, in place of the app's global outline. Drawn as the kit's
/// panel: the style's material, edge and corners. [onTap] makes it a
/// button; [onKeyEvent] (steppers, choices) keeps it focusable without one.
/// [onReset] binds X (MarkIntent) while it has focus.
class SettingsTile extends StatefulWidget {
  const SettingsTile({
    super.key,
    required this.child,
    this.onTap,
    this.onKeyEvent,
    this.onReset,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.color,
    this.focusedColor,
    this.radius,
    this.minHeight = 64,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final Widget child;
  final VoidCallback? onTap;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback? onReset;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Null: the settings tile colour.
  final Color? color;

  /// Null: the focused settings tile colour.
  final Color? focusedColor;
  /// Null: the style's panel corners, at most 14.
  final double? radius;
  final double minHeight;
  final EdgeInsets padding;

  @override
  State<SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<SettingsTile> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlight);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlight);
    super.dispose();
  }

  void _onHighlight(FocusHighlightMode _) {
    if (_focused) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final shows = _focused && settingsFocusShows;
    final radius = BorderRadius.circular(widget.radius ?? math.min(k.panelRadius, 14));
    // A plain tile has the panel's edge; one given its own colour (a rail
    // tile) has none.
    final edge = widget.color == null ? BorderSide(color: k.panelLine) : BorderSide.none;
    final box = ConstrainedBox(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      child: Padding(padding: widget.padding, child: widget.child),
    );
    final interactive = widget.onKeyEvent != null || widget.onTap == null
        ? Focus(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            canRequestFocus: widget.onKeyEvent != null,
            onKeyEvent: widget.onKeyEvent,
            child: box,
          )
        : InkWell(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            focusColor: Colors.transparent,
            borderRadius: radius,
            onTap: widget.onTap,
            child: box,
          );
    Widget tile = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) {
        setState(() => _focused = f);
        widget.onFocusChange?.call(f);
      },
      child: Material(
        color: shows ? (widget.focusedColor ?? k.settingsTileFocused) : (widget.color ?? k.settingsTile),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: shows ? BorderSide(color: k.accent, width: 2, strokeAlign: BorderSide.strokeAlignInside) : edge,
        ),
        clipBehavior: Clip.antiAlias,
        child: interactive,
      ),
    );
    // Always there, so a row that becomes changed (and gains Reset) keeps
    // its element, and with it the focus.
    final reset = widget.onReset;
    tile = Actions(
      actions: {
        if (reset != null)
          MarkIntent: CallbackAction<MarkIntent>(onInvoke: (_) {
            reset();
            return null;
          }),
      },
      child: tile,
    );
    return DpadOwnOutline(child: tile);
  }
}

/// The look every settings row shares: one focus stop at least 64 high, a
/// rounded tile with its own focus outline, [indent] in under the row it
/// depends on.
class SettingsRowFrame extends StatelessWidget {
  const SettingsRowFrame({
    super.key,
    required this.child,
    this.onTap,
    this.onKeyEvent,
    this.onReset,
    this.indent = false,
    this.focusNode,
    this.autofocus = false,
    this.minHeight = 64,
  });

  final Widget child;
  final VoidCallback? onTap;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback? onReset;
  final bool indent;
  final FocusNode? focusNode;
  final bool autofocus;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? settingsIndent : 0, top: settingsHalfGap, bottom: settingsHalfGap),
      child: SettingsTile(
        onTap: onTap,
        onKeyEvent: onKeyEvent,
        onReset: onReset,
        focusNode: focusNode,
        autofocus: autofocus,
        minHeight: minHeight,
        child: child,
      ),
    );
  }
}

/// A row's title and the line under it. [changed]: the console changes this
/// setting; a chip says so.
class SettingsRowText extends StatelessWidget {
  const SettingsRowText({super.key, required this.title, this.subtitle, this.changed = false, this.danger = false, this.enabled = true});

  final String title;
  final String? subtitle;
  final bool changed;
  final bool danger;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final titleText = Text(title, style: t.row.copyWith(fontSize: t.size(15), color: danger ? t.k.error : t.ink));
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (changed) Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [titleText, const ChangedChip()]) else titleText,
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          SizedBox(height: changed ? 4 : 3),
          Text(subtitle!, style: t.subtitle.copyWith(fontSize: t.size(13))),
        ],
      ],
    );
    return enabled ? text : Opacity(opacity: 0.5, child: text);
  }
}

/// Marks a console's own value for a setting.
class ChangedChip extends StatelessWidget {
  const ChangedChip({super.key});

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: t.k.accent, borderRadius: BorderRadius.circular(math.min(t.k.buttonRadius, 10))),
      child: Text('Changed', style: TextStyle(fontFamily: t.k.titleFont, fontSize: t.size(11), fontWeight: FontWeight.w700, color: t.k.onAccent)),
    );
  }
}

/// A small rounded button inside a row. Not a focus stop of its own: the row
/// is (a controller presses it with the row's own key, X for Reset).
class RowPill extends StatelessWidget {
  const RowPill({super.key, required this.label, this.onPressed, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: danger ? null : k.accent.withValues(alpha: 0.16),
        border: Border.all(color: danger ? k.error : k.accent.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(k.buttonRadius.clamp(4, 20).toDouble()),
      ),
      child: Text(label, style: t.verb.copyWith(fontSize: t.size(14), color: danger ? k.error : k.accent)),
    );
    if (onPressed == null) return pill;
    return ExcludeFocus(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onPressed, child: pill));
  }
}

/// Reset on a console's changed row: X on a controller, or a tap here.
class ResetPill extends StatelessWidget {
  const ResetPill({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return ExcludeFocus(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(t.k.buttonRadius.clamp(4, 16).toDouble())),
          child: Text('Reset', style: t.verb),
        ),
      ),
    );
  }
}

/// A group title above some rows.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.text, {super.key, this.top = 18});

  final String text;

  /// Space above it: 18 under rows, less at the top of a page.
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(4, top + settingsHalfGap, 4, 6 + settingsHalfGap),
      child: Text(text.toUpperCase(), style: t.label.copyWith(fontSize: t.size(12), color: t.k.accent)),
    );
  }
}

/// A line of explanation between rows; [error] in the error colour.
class SettingsInfo extends StatelessWidget {
  const SettingsInfo(this.text, {super.key, this.error = false, this.indent = false});

  final String text;
  final bool error;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(4 + (indent ? settingsIndent : 0), 4 + settingsHalfGap, 4, 8 + settingsHalfGap),
      child: Text(text, style: t.body.copyWith(height: 1.5, color: error ? t.k.error : t.muted)),
    );
  }
}

/// The 18 px chevron a value row ends with.
class RowChevron extends StatelessWidget {
  const RowChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(Icons.chevron_right, size: 22, color: KitType.of(context).muted);
}
