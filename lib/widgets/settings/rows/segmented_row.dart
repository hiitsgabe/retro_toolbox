import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/stepper_row.dart';

/// One of a few choices: left/right on the focused row picks the one before
/// or after (no wrap), a tap picks any. [stacked] puts the choices under the
/// title, for long or many labels.
class SettingsSegmentedRow<T> extends StatelessWidget {
  const SettingsSegmentedRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.indent = false,
    this.stacked = false,
    this.changed = false,
    this.onReset,
  });

  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T>? onChanged;
  final bool indent;
  final bool stacked;
  final bool changed;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = options.indexWhere((o) => o.$1 == selected);
    final reset = changed ? onReset : null;

    Widget segment((T, String) o) {
      final picked = o.$1 == selected;
      return ExcludeFocus(
        child: Material(
          color: picked ? scheme.secondaryContainer : Colors.transparent,
          child: InkWell(
            canRequestFocus: false,
            onTap: onChanged == null || picked ? null : () => onChanged!(o.$1),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    o.$2,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: picked ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final choices = DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(22)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: stacked
            ? Wrap(children: [for (final o in options) segment(o)])
            : Row(mainAxisSize: MainAxisSize.min, children: [for (final o in options) segment(o)]),
      ),
    );
    final text = SettingsRowText(title: title, subtitle: subtitle, changed: changed, enabled: onChanged != null);
    final resetPill = reset == null ? null : RowPill(label: 'Reset', filled: false, onPressed: reset);

    return SettingsRowFrame(
      indent: indent,
      onReset: reset,
      onKeyEvent: (_, e) {
        final by = sideStep(e);
        if (by == null || onChanged == null) return KeyEventResult.ignored;
        final next = (index < 0 ? 0 : index + by).clamp(0, options.length - 1);
        if (next != index) onChanged!(options[next].$1);
        return KeyEventResult.handled;
      },
      child: stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: text), if (resetPill != null) resetPill]),
              const SizedBox(height: 10),
              choices,
            ])
          : Row(children: [
              Expanded(child: text),
              if (resetPill != null) ...[const SizedBox(width: 12), resetPill],
              const SizedBox(width: 12),
              choices,
            ]),
    );
  }
}
