import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';

/// Space a dependent row is pushed in by, under the row it depends on.
const settingsIndent = 28.0;

/// The look every settings row shares: one focus stop at least 64 high, a
/// rounded tile, the d-pad outline drawn by DpadScope around it. [onTap] makes
/// it a button; [onKeyEvent] (steppers, choices) keeps it focusable without
/// one. [onReset] binds X (MarkIntent) while it has focus.
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
  });

  final Widget child;
  final VoidCallback? onTap;
  final FocusOnKeyEventCallback? onKeyEvent;
  final VoidCallback? onReset;
  final bool indent;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    final box = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: child),
    );
    Widget row = Material(
      color: scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onKeyEvent != null || onTap == null
          ? Focus(focusNode: focusNode, autofocus: autofocus, canRequestFocus: onKeyEvent != null, onKeyEvent: onKeyEvent, child: box)
          : InkWell(focusNode: focusNode, autofocus: autofocus, focusColor: Colors.transparent, onTap: onTap, child: box),
    );
    if (onReset != null) {
      row = Actions(
        actions: {
          MarkIntent: CallbackAction<MarkIntent>(onInvoke: (_) {
            onReset!();
            return null;
          }),
        },
        child: row,
      );
    }
    return Padding(
      padding: EdgeInsets.only(left: indent ? settingsIndent : 0, top: 3, bottom: 3),
      child: row,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleText = Text(
      title,
      style: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: danger ? scheme.error : scheme.onSurface,
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (changed) Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [titleText, const ChangedChip()]) else titleText,
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
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
  const RowPill({super.key, required this.label, this.onPressed, this.danger = false, this.filled = true});

  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = danger ? scheme.error : (filled ? scheme.onSecondaryContainer : scheme.primary);
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: danger ? null : (filled ? scheme.secondaryContainer : scheme.surfaceContainerHighest),
        border: danger ? Border.all(color: scheme.error) : null,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
    );
    if (onPressed == null) return pill;
    return ExcludeFocus(
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onPressed, child: pill),
    );
  }
}

/// A group title above some rows.
class SettingsHeader extends StatelessWidget {
  const SettingsHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: scheme.primary),
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
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(4 + (indent ? settingsIndent : 0), 4, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.5, color: error ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// A row-shaped box for a widget with its own controls (a form, a list of
/// choices): it keeps their focus stops and only takes the row's look.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key, required this.child, this.indent = false});

  final Widget child;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? settingsIndent : 0, top: 3, bottom: 3),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}
