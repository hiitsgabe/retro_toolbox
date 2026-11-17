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
    this.monospace = false,
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
  final bool monospace;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reset = changed ? onReset : null;
    return SettingsRowFrame(
      indent: indent,
      onTap: onTap,
      onReset: reset,
      focusNode: focusNode,
      autofocus: autofocus,
      child: Row(children: [
        Expanded(flex: 3, child: SettingsRowText(title: title, subtitle: subtitle, changed: changed, enabled: onTap != null)),
        if (value != null) ...[
          const SizedBox(width: 12),
          Flexible(
            flex: 2,
            child: Text(
              value!,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontFamily: monospace ? 'monospace' : null),
            ),
          ),
        ],
        if (reset != null) ...[const SizedBox(width: 12), RowPill(label: 'Reset', filled: false, onPressed: reset)],
        const SizedBox(width: 4),
        Icon(Icons.chevron_right, color: theme.colorScheme.outline),
      ]),
    );
  }
}

/// A value row that opens a panel under itself (a form, a list) instead of
/// another page; A again closes it.
class SettingsExpandRow extends StatefulWidget {
  const SettingsExpandRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final Widget child;
  final bool initiallyExpanded;

  @override
  State<SettingsExpandRow> createState() => _SettingsExpandRowState();
}

class _SettingsExpandRowState extends State<SettingsExpandRow> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsRowFrame(
          onTap: () => setState(() => _open = !_open),
          child: Row(children: [
            Expanded(flex: 3, child: SettingsRowText(title: widget.title, subtitle: widget.subtitle)),
            if (widget.value != null) ...[
              const SizedBox(width: 12),
              Flexible(
                  flex: 2,
                  child: Text(widget.value!, textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium)),
            ],
            const SizedBox(width: 4),
            Icon(_open ? Icons.expand_less : Icons.expand_more, color: theme.colorScheme.outline),
          ]),
        ),
        if (_open) SettingsPanel(indent: true, child: widget.child),
      ],
    );
  }
}
