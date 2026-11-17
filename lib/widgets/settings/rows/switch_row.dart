import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';

/// An on/off setting: A or a tap anywhere on the row flips it. [onChanged]
/// null: shown, not changeable. [onReset] with [changed]: a Reset pill, and X
/// resets.
class SettingsSwitchRow extends StatelessWidget {
  const SettingsSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.indent = false,
    this.changed = false,
    this.onReset,
    this.autofocus = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool indent;
  final bool changed;
  final VoidCallback? onReset;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final reset = changed ? onReset : null;
    return SettingsRowFrame(
      indent: indent,
      autofocus: autofocus,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      onReset: reset,
      child: Row(children: [
        Expanded(child: SettingsRowText(title: title, subtitle: subtitle, changed: changed, enabled: onChanged != null)),
        if (reset != null) ...[const SizedBox(width: 12), RowPill(label: 'Reset', filled: false, onPressed: reset)],
        const SizedBox(width: 12),
        ExcludeFocus(child: Switch(value: value, onChanged: onChanged)),
      ]),
    );
  }
}
