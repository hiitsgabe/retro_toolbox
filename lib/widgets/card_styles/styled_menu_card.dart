import 'package:flutter/material.dart';
import 'package:retro_toolbox/widgets/menu_grid/menu_grid.dart';

/// What a tap on a style's card does with focus, so a finger reaches what
/// the style shows for the focused card.
enum TapFocus {
  /// Runs the card; focus stays where it was (the classic tile).
  none,

  /// Focuses the card and runs it: the focus look follows the finger (Switch).
  focusAndRun,

  /// Touch has no hover: a tap on a card without focus only focuses it, a tap
  /// on the focused card runs it (3DS, whose top strip names the focused one).
  selectFirst,
}

/// Tracks whether a card has focus, and shows it only to d-pad and keyboard
/// users: [focusedLook] is false under touch, as the classic menu tile does,
/// unless the card took focus from a tap ([TapFocus]).
mixin FocusedLook<T extends StatefulWidget> on State<T> {
  bool _focused = false;
  bool _tapped = false;

  /// Focused, and focus is drawn (traditional highlight mode, or a tap put it here).
  bool get focusedLook => _focused && (_tapped || FocusManager.instance.highlightMode == FocusHighlightMode.traditional);

  /// Give it the card's focus changes.
  void setFocused(bool focused) => setState(() => _focused = focused);

  /// A tap under [mode]: true when the card should run. Focus moves to [node]
  /// unless [mode] is [TapFocus.none].
  bool tapFocus(TapFocus mode, FocusNode node) {
    if (mode == TapFocus.none) return true;
    // Kept after focus leaves, so the look is back when a page over it closes.
    _tapped = true;
    final run = mode == TapFocus.focusAndRun || node.hasPrimaryFocus;
    node.requestFocus();
    return run;
  }

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
  const StyledMenuCard({
    super.key,
    required this.tile,
    required this.face,
    this.autofocus = false,
    this.onFocusChange,
    this.customBorder,
    this.tapFocus = TapFocus.none,
  });

  final MenuTile tile;

  /// The style's look; [focused] only when focus should show (see [FocusedLook]).
  final Widget Function(BuildContext context, bool focused) face;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;

  /// The ink's shape; the classic tile's rounded square when null.
  final ShapeBorder? customBorder;
  final TapFocus tapFocus;

  @override
  State<StyledMenuCard> createState() => _StyledMenuCardState();
}

class _StyledMenuCardState extends State<StyledMenuCard> with FocusedLook {
  bool _pressed = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: widget.customBorder == null ? BorderRadius.circular(20) : null,
        customBorder: widget.customBorder,
        // The style's face draws focus: no grey wash over it.
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () {
          if (tapFocus(widget.tapFocus, _focus)) widget.tile.onTap();
        },
        focusNode: _focus,
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
