import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';

/// Something to do rather than a value: the row is the button, the pill
/// names the action. [danger] for what deletes; [busy] spins in its place.
class SettingsActionRow extends StatelessWidget {
  const SettingsActionRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.action,
    required this.onPressed,
    this.danger = false,
    this.busy = false,
    this.indent = false,
  });

  final String title;
  final String? subtitle;
  final String action;
  final VoidCallback? onPressed;
  final bool danger;
  final bool busy;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SettingsRowFrame(
      indent: indent,
      onTap: enabled ? onPressed : null,
      child: Row(children: [
        Expanded(child: SettingsRowText(title: title, subtitle: subtitle, danger: danger, enabled: enabled || busy)),
        const SizedBox(width: 12),
        if (busy)
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else
          Opacity(opacity: enabled ? 1 : 0.5, child: RowPill(label: action, danger: danger)),
      ]),
    );
  }
}
