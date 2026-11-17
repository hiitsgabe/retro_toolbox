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

/// A 44 px round outlined button inside a row; not a focus stop.
class RoundRowButton extends StatelessWidget {
  const RoundRowButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeFocus(
      child: Tooltip(
        message: tooltip,
        child: Material(
          type: MaterialType.transparency,
          shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            canRequestFocus: false,
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 22, color: onPressed == null ? scheme.onSurface.withValues(alpha: 0.38) : scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
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
        const SizedBox(width: 16),
        RoundRowButton(icon: Icons.chevron_left, tooltip: 'Less', onPressed: value > min ? () => _step(-1) : null),
        const SizedBox(width: 4),
        SizedBox(
          width: 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: scheme.onSurface, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        const SizedBox(width: 4),
        RoundRowButton(icon: Icons.chevron_right, tooltip: 'More', onPressed: value < max ? () => _step(1) : null),
      ]),
    );
  }
}
