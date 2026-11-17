import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';

/// Left/right on a focused choice row: -1 or +1, null for any other key.
int? sideStep(KeyEvent e) {
  if (e is! KeyDownEvent && e is! KeyRepeatEvent) return null;
  if (e.logicalKey == LogicalKeyboardKey.arrowLeft) return -1;
  if (e.logicalKey == LogicalKeyboardKey.arrowRight) return 1;
  return null;
}

/// A number from [min] to [max]: left/right on the focused row, or the two
/// round buttons, step it by one.
class SettingsStepperRow extends StatelessWidget {
  const SettingsStepperRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.indent = false,
  });

  final String title;
  final String? subtitle;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final bool indent;

  void _step(int by) {
    final next = (value + by).clamp(min, max);
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget round(IconData icon, String tooltip, bool enabled, int by) => ExcludeFocus(
          child: IconButton.outlined(
            tooltip: tooltip,
            onPressed: enabled ? () => _step(by) : null,
            icon: Icon(icon),
          ),
        );
    return SettingsRowFrame(
      indent: indent,
      onKeyEvent: (_, e) {
        final by = sideStep(e);
        if (by == null) return KeyEventResult.ignored;
        _step(by);
        return KeyEventResult.handled;
      },
      child: Row(children: [
        Expanded(child: SettingsRowText(title: title, subtitle: subtitle)),
        const SizedBox(width: 12),
        round(Icons.chevron_left, 'Less', value > min, -1),
        SizedBox(
          width: 44,
          child: Text('$value', textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
        round(Icons.chevron_right, 'More', value < max, 1),
      ]),
    );
  }
}
