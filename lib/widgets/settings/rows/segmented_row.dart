import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/settings/rows/settings_row.dart';
import 'package:retro_toolbox/widgets/settings/rows/stepper_row.dart';

const _segmentText = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);

/// One of a few choices: left/right on the focused row picks the one before
/// or after (no wrap), a tap picks any. The choices sit right of the title,
/// or under it when they would leave the title too little room. A console's
/// [changed] choice carries the chip; X resets it ([onReset]).
class SettingsSegmentedRow<T> extends StatelessWidget {
  const SettingsSegmentedRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.indent = false,
    this.changed = false,
    this.onReset,
  });

  final String title;
  final String? subtitle;
  final List<(T, String)> options;
  final T selected;
  final ValueChanged<T>? onChanged;
  final bool indent;
  final bool changed;
  final VoidCallback? onReset;

  /// The choices' width on one line.
  double _choicesWidth(BuildContext context) {
    var w = 2.0;
    for (final o in options) {
      final tp = TextPainter(
        text: TextSpan(text: o.$2, style: DefaultTextStyle.of(context).style.merge(_segmentText)),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      w += tp.width + 32;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = StyleTokens.of(context);
    final round = math.min(k.buttonRadius, 22).toDouble();
    final index = options.indexWhere((o) => o.$1 == selected);
    final reset = changed ? onReset : null;

    Widget segment((T, String) o) {
      final picked = o.$1 == selected;
      return Material(
        color: picked ? k.accent : Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          onTap: onChanged == null || picked ? null : () => onChanged!(o.$1),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(o.$2, style: _segmentText.copyWith(color: picked ? k.onAccent : scheme.onSurfaceVariant)),
              ),
            ),
          ),
        ),
      );
    }

    Widget choices({required bool wrap}) => ExcludeFocus(
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: Border.all(color: k.panelLine), borderRadius: BorderRadius.circular(round)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(round),
              child: wrap
                  ? Wrap(children: [for (final o in options) segment(o)])
                  : IntrinsicHeight(child: Row(mainAxisSize: MainAxisSize.min, children: [for (final o in options) segment(o)])),
            ),
          ),
        );
    final text = SettingsRowText(title: title, subtitle: subtitle, changed: changed, enabled: onChanged != null);

    return SettingsRowFrame(
      indent: indent,
      onReset: reset,
      minHeight: changed ? 72 : 64,
      onKeyEvent: (_, e) {
        final by = sideStep(e);
        if (by == null || onChanged == null) return KeyEventResult.ignored;
        final next = (index < 0 ? 0 : index + by).clamp(0, options.length - 1);
        if (next != index) onChanged!(options[next].$1);
        return KeyEventResult.handled;
      },
      child: LayoutBuilder(builder: (context, box) {
        final wide = _choicesWidth(context);
        // Under the title when the title would get less than 200 px.
        if (box.maxWidth - wide - 16 < 200) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            text,
            const SizedBox(height: 10),
            choices(wrap: true),
          ]);
        }
        return Row(children: [
          Expanded(child: text),
          const SizedBox(width: 16),
          choices(wrap: false),
        ]);
      }),
    );
  }
}
