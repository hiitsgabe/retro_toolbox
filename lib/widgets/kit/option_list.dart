import 'package:flutter/material.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// A tool's options: toggle, choice, action and expander rows in one panel,
/// a line between them. Each row is one focus stop; A or a tap acts on it.
class OptionList extends StatelessWidget {
  const OptionList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => KitPanel(children: children);
}

/// The frame of a kit row: at least 46 high, ink and focus on the whole row.
class KitRow extends StatelessWidget {
  const KitRow({super.key, required this.child, this.onTap, this.autofocus = false, this.focusNode, this.minHeight = 46, this.selected});

  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final double minHeight;

  /// For assistive tech: a choice or toggle row's state.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    return Semantics(
      selected: selected,
      child: InkWell(
        focusNode: focusNode,
        autofocus: autofocus,
        borderRadius: kitRowRadius(k),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), child: child),
        ),
      ),
    );
  }
}

/// A row's title and the line under it.
class KitRowText extends StatelessWidget {
  const KitRowText({super.key, required this.title, this.subtitle, this.enabled = true});

  final String title;
  final String? subtitle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final subtitle = this.subtitle;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: t.row),
        if (subtitle != null && subtitle.isNotEmpty) Text(subtitle, style: t.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// The kit's on/off switch, drawn small (it is a picture: the row is the
/// control).
class KitSwitch extends StatelessWidget {
  const KitSwitch({super.key, required this.value, this.enabled = true});

  final bool value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: value ? k.accent : Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 120),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 16, height: 16, decoration: BoxDecoration(shape: BoxShape.circle, color: value ? k.onAccent : scheme.onSurface.withValues(alpha: 0.85))),
        ),
      ),
    );
  }
}

/// The kit's radio dot (a picture, like [KitSwitch]).
class KitRadio extends StatelessWidget {
  const KitRadio({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final k = StyleTokens.of(context);
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? k.accent : Colors.white.withValues(alpha: 0.5), width: 2)),
      child: selected ? Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: k.accent)) : null,
    );
  }
}

/// An on/off option. [onChanged] null: shown, not changeable.
class OptionToggle extends StatelessWidget {
  const OptionToggle({super.key, required this.title, this.subtitle, required this.value, required this.onChanged, this.autofocus = false});

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return KitRow(
      autofocus: autofocus,
      selected: value,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: Row(children: [
        Expanded(child: KitRowText(title: title, subtitle: subtitle, enabled: enabled)),
        const SizedBox(width: 12),
        KitSwitch(value: value, enabled: enabled),
      ]),
    );
  }
}

/// One choice of a group: the radio is on when [value] is [groupValue].
class OptionChoice<T> extends StatelessWidget {
  const OptionChoice({super.key, required this.title, this.subtitle, required this.value, required this.groupValue, required this.onSelected, this.autofocus = false});

  final String title;
  final String? subtitle;
  final T value;
  final T? groupValue;
  final ValueChanged<T>? onSelected;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final on = value == groupValue;
    final enabled = onSelected != null;
    return KitRow(
      autofocus: autofocus,
      selected: on,
      onTap: enabled ? () => onSelected!(value) : null,
      child: Row(children: [
        KitRadio(selected: on),
        const SizedBox(width: 12),
        Expanded(child: KitRowText(title: title, subtitle: subtitle, enabled: enabled)),
      ]),
    );
  }
}

/// A row that opens something or shows a value: "Port 9092 >".
class OptionAction extends StatelessWidget {
  const OptionAction({super.key, required this.title, this.subtitle, this.value, required this.onTap, this.chevron = true, this.autofocus = false});

  final String title;
  final String? subtitle;
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return KitRow(
      autofocus: autofocus,
      onTap: onTap,
      child: Row(children: [
        Expanded(child: KitRowText(title: title, subtitle: subtitle, enabled: onTap != null)),
        if (value != null) ...[const SizedBox(width: 12), Text(value!, style: t.subtitle.copyWith(fontSize: t.size(13)))],
        if (chevron) ...[const SizedBox(width: 6), Icon(Icons.chevron_right, size: 20, color: t.muted)],
      ]),
    );
  }
}

/// "Advanced": a row that opens the rows under it in place. Closed by
/// default; [subtitle] says what is inside.
class OptionExpander extends StatefulWidget {
  const OptionExpander({super.key, this.title = 'Advanced', this.subtitle, required this.children, this.initiallyExpanded = false, this.onChanged});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;

  /// Told when it opens (true) or closes: what is inside can load then.
  final ValueChanged<bool>? onChanged;

  @override
  State<OptionExpander> createState() => _OptionExpanderState();
}

class _OptionExpanderState extends State<OptionExpander> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    final rows = <Widget>[];
    for (final c in widget.children) {
      rows.add(Divider(height: 1, thickness: 1, color: k.panelLine));
      rows.add(c);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        expanded: _open,
        child: KitRow(
          onTap: () {
            setState(() => _open = !_open);
            widget.onChanged?.call(_open);
          },
          child: Row(children: [
            Expanded(child: KitRowText(title: widget.title, subtitle: widget.subtitle)),
            AnimatedRotation(turns: _open ? 0.5 : 0, duration: const Duration(milliseconds: 150), child: Icon(Icons.expand_more, size: 22, color: t.muted)),
          ]),
        ),
      ),
      if (_open) ColoredBox(color: Colors.black.withValues(alpha: 0.12), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows)),
    ]);
  }
}
