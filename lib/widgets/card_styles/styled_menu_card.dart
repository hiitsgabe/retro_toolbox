import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// Tracks whether a card has focus, and shows it only to d-pad and keyboard
/// users: [focusedLook] is false under touch, as the classic menu tile does.
mixin FocusedLook<T extends StatefulWidget> on State<T> {
  bool _focused = false;

  /// Focused, and focus is drawn (traditional highlight mode).
  bool get focusedLook => _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  /// Give it the card's focus changes.
  void setFocused(bool focused) => setState(() => _focused = focused);

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_onHighlightMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onHighlightMode);
    super.dispose();
  }

  void _onHighlightMode(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }
}

/// The behaviour of a classic menu tile (one focus stop, tap or A runs the
/// tile, a press shrinks it) around a style's [face].
class StyledMenuCard extends StatefulWidget {
  const StyledMenuCard({super.key, required this.tile, required this.face, this.autofocus = false, this.onFocusChange, this.customBorder});

  final MenuTile tile;

  /// The style's look; [focused] only when focus should show (see [FocusedLook]).
  final Widget Function(BuildContext context, bool focused) face;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  /// The ink's shape; the classic tile's rounded square when null.
  final ShapeBorder? customBorder;

  @override
  State<StyledMenuCard> createState() => _StyledMenuCardState();
}

class _StyledMenuCardState extends State<StyledMenuCard> with FocusedLook {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: widget.customBorder == null ? BorderRadius.circular(20) : null,
        customBorder: widget.customBorder,
        onTap: widget.tile.onTap,
        autofocus: widget.autofocus,
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onFocusChange: (v) {
          setFocused(v);
          widget.onFocusChange?.call(v);
        },
        // Styles draw their own focus look, so only a press scales.
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1,
          duration: const Duration(milliseconds: 90),
          child: widget.face(context, focusedLook),
        ),
      ),
    );
  }
}
