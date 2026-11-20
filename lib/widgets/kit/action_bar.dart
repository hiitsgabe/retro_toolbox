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
  const ActionBar({super.key, this.primary, this.secondary, this.more = const [], this.hints = const [], this.summary, this.autofocus = false});

  /// Null: no primary (Start then does nothing on this screen).
  final KitAction? primary;

  /// A second, quieter button (Back in a wizard, Add app). Its [KitAction.button]
  /// shows as its key cap; select, X and Y are bound for the screen too.
  final KitAction? secondary;

  /// Further quiet buttons, before the secondary (a game's other actions):
  /// labelled in landscape, icons with their label as a tooltip in portrait.
  /// Their select, X and Y are bound for the screen too.
  final List<KitAction> more;
  final List<KitHint> hints;

  /// The primary takes focus when the bar appears (or, without one, the
  /// first enabled button): a page whose first move is the primary's.
  final bool autofocus;

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
    // Who takes focus: the primary, else the first enabled button in the row.
    final focusFirst = !autofocus
        ? null
        : this.primary?.enabled == true
            ? this.primary
            : [...more, if (this.secondary != null) this.secondary!].where((a) => a.enabled).firstOrNull;
    final primary = this.primary == null ? null : _Primary(action: this.primary!, pad: pad, big: portrait, autofocus: identical(focusFirst, this.primary));
    final secondary =
        this.secondary == null ? null : _Secondary(action: this.secondary!, pad: pad, big: portrait, autofocus: identical(focusFirst, this.secondary));
    final extra = [
      for (final (i, a) in more.indexed)
        portrait && a.icon != null
            ? _MoreIcon(key: ValueKey('kit-more-$i'), action: a, autofocus: identical(focusFirst, a))
            : _Secondary(key: ValueKey('kit-more-$i'), action: a, pad: pad, big: portrait, autofocus: identical(focusFirst, a)),
    ];
    final Widget content;
    if (portrait) {
      content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (summaryText != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: summaryText),
        Row(children: [
          for (final e in extra) ...[e, const SizedBox(width: 8)],
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
        for (final e in extra) ...[const SizedBox(width: 8), e],
        if (secondary != null) ...[SizedBox(width: extra.isEmpty ? 12 : 8), secondary],
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
        child: _KeepFocus(child: Padding(padding: portrait ? const EdgeInsets.fromLTRB(16, 10, 16, 12) : const EdgeInsets.fromLTRB(16, 6, 12, 6), child: content)),
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
  const _Primary({required this.action, required this.pad, required this.big, this.autofocus = false});

  final KitAction action;
  final bool pad;
  final bool big;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final k = t.k;
    return FilledButton(
      key: const ValueKey('kit-primary'),
      autofocus: autofocus,
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
  const _Secondary({super.key, required this.action, required this.pad, required this.big, this.autofocus = false});

  final KitAction action;
  final bool pad;
  final bool big;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    final button = action.button;
    return OutlinedButton(
      key: key ?? const ValueKey('kit-secondary'),
      autofocus: autofocus,
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

/// Keeps focus in the bar when the focused button goes away (a game's Select
/// once it is marked): focus would fall to the page's scope, and the d-pad
/// would start over from nothing.
class _KeepFocus extends StatefulWidget {
  const _KeepFocus({required this.child});

  final Widget child;

  @override
  State<_KeepFocus> createState() => _KeepFocusState();
}

class _KeepFocusState extends State<_KeepFocus> {
  final _node = FocusNode(debugLabel: 'ActionBar', canRequestFocus: false, skipTraversal: true);
  bool _had = false;

  // The manager, not the node: a focused child that is removed leaves the
  // tree before focus moves, and its old ancestors are not told.
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  void _onFocus() {
    if (_node.hasFocus) {
      _had = true;
      return;
    }
    if (!_had) return;
    _had = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Only when focus fell to a scope: moving elsewhere on purpose stays.
      if (!mounted || FocusManager.instance.primaryFocus is! FocusScopeNode) return;
      _node.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal).firstOrNull?.requestFocus();
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(focusNode: _node, child: widget.child);
}

/// A further action in portrait: its icon in an outlined square, its label
/// the tooltip.
class _MoreIcon extends StatelessWidget {
  const _MoreIcon({super.key, required this.action, this.autofocus = false});

  final KitAction action;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = KitType.of(context);
    return IconButton.outlined(
      autofocus: autofocus,
      tooltip: action.label,
      onPressed: action.onPressed,
      icon: Icon(action.icon, size: 22),
      style: IconButton.styleFrom(
        minimumSize: const Size(50, 50),
        foregroundColor: t.ink,
        side: BorderSide(color: t.ink.withValues(alpha: 0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.k.buttonRadius.clamp(4, 25).toDouble())),
      ),
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
    Action<T> run<T extends Intent>(VoidCallback? f) => CallbackAction<T>(onInvoke: (_) {
          f?.call();
          return null;
        });
    KitAction? on(PadButton b) => [if (bar.secondary != null) bar.secondary!, ...bar.more].where((a) => a.button == b).firstOrNull;
    final select = on(PadButton.select), x = on(PadButton.x), y = on(PadButton.y);
    return Actions(
      actions: {
        PrimaryActionIntent: run<PrimaryActionIntent>(bar.primary?.onPressed),
        if (select != null) OptionsIntent: run<OptionsIntent>(select.onPressed),
        if (x != null) MarkIntent: run<MarkIntent>(x.onPressed),
        if (y != null) ItemActionsIntent: run<ItemActionsIntent>(y.onPressed),
      },
      child: child,
    );
  }
}
