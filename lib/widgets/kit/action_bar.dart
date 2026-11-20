import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retro_toolbox/providers/input_mode_provider.dart';
import 'package:retro_toolbox/theme/device_class.dart';
import 'package:retro_toolbox/theme/style_tokens.dart';
import 'package:retro_toolbox/widgets/common/dpad_scope.dart';
import 'package:retro_toolbox/widgets/kit/kit_base.dart';

/// The bar fixed at the bottom of a kit screen: the primary action (Start),
/// an optional secondary, the button hints and a short summary. Hints and key
/// caps show only after gamepad input. In portrait the primary takes the
/// width, where the thumb is.
///
/// Give it to [KitScaffold.actionBar]: the scaffold binds Start to [primary]
/// for the whole screen.
class ActionBar extends ConsumerWidget {
  const ActionBar({super.key, this.primary, this.secondary, this.hints = const [], this.summary});

  /// Null: no primary (Start then does nothing on this screen).
  final KitAction? primary;

  /// A second, quieter button (Back in a wizard, Add app). Its [KitAction.button]
  /// shows as its key cap; select, X and Y are bound for the screen too.
  final KitAction? secondary;
  final List<KitHint> hints;

  /// One line about what the primary will do: "Crash Bandicoot.cue to .chd".
  final String? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = ref.watch(inputModeProvider) == InputMode.gamepad;
    final k = StyleTokens.of(context);
    final t = KitType.of(context);
    final portrait = DeviceClass.of(context) == DeviceClass.portrait;
    final summary = this.summary;
    final summaryText = summary == null || summary.isEmpty
        ? null
        : Text(summary, key: const ValueKey('kit-summary'), style: t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: portrait ? TextAlign.start : TextAlign.end);
    final primary = this.primary == null ? null : _Primary(action: this.primary!, pad: pad, big: portrait);
    final secondary = this.secondary == null ? null : _Secondary(action: this.secondary!, pad: pad, big: portrait);
    final Widget content;
    if (portrait) {
      content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (summaryText != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: summaryText),
        Row(children: [
          if (secondary != null) secondary,
          if (secondary != null && primary != null) const SizedBox(width: 10),
          if (primary != null) Expanded(child: primary),
        ]),
      ]);
    } else {
      // Hints that do not fit are cut at the edge rather than pushing the
      // buttons off the bar.
      final hintRow = pad && hints.isNotEmpty
          ? ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(children: [
                  for (final h in hints) ...[_Hint(hint: h), const SizedBox(width: 14)],
                ]),
              ),
            )
          : null;
      content = Row(children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => Row(children: [
              if (hintRow != null) ConstrainedBox(constraints: BoxConstraints(maxWidth: box.maxWidth * (summaryText == null ? 1 : 0.6)), child: hintRow),
              if (summaryText != null) Expanded(child: summaryText),
            ]),
          ),
        ),
        if (secondary != null) ...[const SizedBox(width: 12), secondary],
        if (primary != null) ...[const SizedBox(width: 10), primary],
      ]);
    }
    return Container(
      decoration: BoxDecoration(
        color: Color.alphaBlend(Colors.black.withValues(alpha: 0.3), k.surface.withValues(alpha: 0.55)),
        border: Border(top: BorderSide(color: k.panelLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(padding: portrait ? const EdgeInsets.fromLTRB(16, 10, 16, 12) : const EdgeInsets.fromLTRB(16, 6, 12, 6), child: content),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.hint});

  final KitHint hint;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      PadKey(hint.button),
      const SizedBox(width: 5),
      Text(hint.label, style: t.subtitle.copyWith(color: t.ink.withValues(alpha: 0.72))),
    ]);
  }
}

TextStyle _buttonText(KitType t, bool big) => TextStyle(fontFamily: t.k.titleFont, fontSize: t.size(big ? 16 : 14), fontWeight: FontWeight.w700, letterSpacing: t.k.titleCaps ? 0.6 : 0);

class _Primary extends StatelessWidget {
  const _Primary({required this.action, required this.pad, required this.big});

  final KitAction action;
  final bool pad;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    return FilledButton(
      key: const ValueKey('kit-primary'),
      onPressed: action.onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(0, big ? 50 : 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: _buttonText(t, big),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pad) ...[
          PadKey(PadButton.start, color: Colors.black.withValues(alpha: 0.22), textColor: action.enabled ? k.onAccent : null),
          const SizedBox(width: 8),
        ] else if (action.icon != null) ...[
          Icon(action.icon, size: 18),
          const SizedBox(width: 8),
        ],
        Flexible(child: Text(t.caps(action.label), maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

class _Secondary extends StatelessWidget {
  const _Secondary({required this.action, required this.pad, required this.big});

  final KitAction action;
  final bool pad;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final button = action.button;
    return OutlinedButton(
      key: const ValueKey('kit-secondary'),
      onPressed: action.onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, big ? 50 : 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: t.ink,
        side: BorderSide(color: t.ink.withValues(alpha: 0.3)),
        textStyle: _buttonText(t, big),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (pad && button != null) ...[PadKey(button), const SizedBox(width: 8)] else if (action.icon != null) ...[Icon(action.icon, size: 18), const SizedBox(width: 6)],
        Text(t.caps(action.label)),
      ]),
    );
  }
}

/// Binds the pad buttons of [bar] for everything under it: Start runs the
/// primary (or nothing, when it is disabled or absent: Start must not fall
/// back to pressing whatever has focus), and the secondary's select, X or Y.
/// A control's own Actions nearer the focus still win.
class KitBarActions extends StatelessWidget {
  const KitBarActions({super.key, required this.bar, required this.child});

  final ActionBar? bar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bar = this.bar;
    // Always an Actions, so a bar that comes and goes (a paste waiting) keeps
    // the screen's tree, and with it its state and focus.
    if (bar == null) return Actions(actions: const {}, child: child);
    final secondary = bar.secondary;
    Action<T> run<T extends Intent>(VoidCallback? f) => CallbackAction<T>(onInvoke: (_) {
          f?.call();
          return null;
        });
    return Actions(
      actions: {
        PrimaryActionIntent: run<PrimaryActionIntent>(bar.primary?.onPressed),
        if (secondary?.button == PadButton.select) OptionsIntent: run<OptionsIntent>(secondary!.onPressed),
        if (secondary?.button == PadButton.x) MarkIntent: run<MarkIntent>(secondary!.onPressed),
        if (secondary?.button == PadButton.y) ItemActionsIntent: run<ItemActionsIntent>(secondary!.onPressed),
      },
      child: child,
    );
  }
}
