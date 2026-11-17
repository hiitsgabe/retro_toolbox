import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// Space a dependent row is pushed in by, under the row it depends on.
const settingsIndent = 28.0;

/// Half the gap between two settings items: every row, header and info line
/// carries it above and below, so any two of them sit 6 apart.
const settingsHalfGap = 3.0;

/// The settings palette, from the theme: the tile, the focused tile, the line
/// between panes.
extension SettingsColors on ColorScheme {
  Color get settingsTile => surfaceContainerLow;
  Color get settingsTileFocused => surfaceContainerHigh;
  Color get settingsLine => surfaceContainerHigh;
}

/// Whether focus is showing (a d-pad or keyboard moved it, not a touch).
bool get settingsFocusShows => FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

/// A rounded tile that shows its own focus: a lighter fill and a 2 px outline
/// inside its edge, in place of the app's global outline. [onTap] makes it a
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
    this.radius = 14,
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
  final double radius;
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
    final scheme = Theme.of(context).colorScheme;
    final shows = _focused && settingsFocusShows;
    final radius = BorderRadius.circular(widget.radius);
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
        color: shows ? (widget.focusedColor ?? scheme.settingsTileFocused) : (widget.color ?? scheme.settingsTile),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: shows ? BorderSide(color: scheme.primary, width: 2, strokeAlign: BorderSide.strokeAlignInside) : BorderSide.none,
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
    final scheme = Theme.of(context).colorScheme;
    final titleText = Text(
      title,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: danger ? scheme.error : scheme.onSurface),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (changed) Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [titleText, const ChangedChip()]) else titleText,
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          SizedBox(height: changed ? 4 : 3),
          Text(subtitle!, style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant)),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
      child: Text('Changed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onPrimary)),
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
    final scheme = Theme.of(context).colorScheme;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: danger ? null : scheme.secondaryContainer,
        border: danger ? Border.all(color: scheme.error) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: danger ? scheme.error : scheme.onSecondaryContainer)),
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
    final scheme = Theme.of(context).colorScheme;
    return ExcludeFocus(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
          child: Text('Reset', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, top + settingsHalfGap, 4, 6 + settingsHalfGap),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.96, color: scheme.primary),
      ),
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(4 + (indent ? settingsIndent : 0), 4 + settingsHalfGap, 4, 8 + settingsHalfGap),
      child: Text(text, style: TextStyle(fontSize: 13, height: 1.5, color: error ? scheme.error : scheme.onSurfaceVariant)),
    );
  }
}

/// The 18 px chevron a value row ends with.
class RowChevron extends StatelessWidget {
  const RowChevron({super.key});

  @override
  Widget build(BuildContext context) => Icon(Icons.chevron_right, size: 22, color: Theme.of(context).colorScheme.outline);
}
