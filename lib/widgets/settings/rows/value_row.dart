import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';

/// A setting shown by its value; A or a tap opens what changes it.
class SettingsValueRow extends StatelessWidget {
  const SettingsValueRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    required this.onTap,
    this.indent = false,
    this.changed = false,
    this.onReset,
    this.focusNode,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool indent;
  final bool changed;
  final VoidCallback? onReset;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reset = changed ? onReset : null;
    return SettingsRowFrame(
      indent: indent,
      onTap: onTap,
      onReset: reset,
      focusNode: focusNode,
      autofocus: autofocus,
      minHeight: changed ? 72 : 64,
      child: Row(children: [
        Expanded(child: SettingsRowText(title: title, subtitle: subtitle, changed: changed)),
        if (value != null) ...[
          const SizedBox(width: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: scheme.onSurface)),
          ),
        ],
        if (reset != null) ...[const SizedBox(width: 16), ResetPill(onPressed: reset)],
        // The console page's changed rows end on Reset instead.
        if (onTap != null && reset == null) ...[const SizedBox(width: 6), const RowChevron()],
      ]),
    );
  }
}
