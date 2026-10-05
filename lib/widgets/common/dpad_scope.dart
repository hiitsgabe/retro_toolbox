import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:retro_toolbox/widgets/common/osk/on_screen_keyboard.dart';

/// Moves focus a page at a time (L1/R1 on handhelds map to PageUp/PageDown).
class PageFocusIntent extends Intent {
  const PageFocusIntent(this.forward);
  final bool forward;
}

EditableTextState? _focusedField() =>
    FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();

/// Up/down: leave a text field unless it is multi-line (maxLines != 1); then
/// disabled, so the key falls through to caret movement.
class _VerticalIntent extends Intent {
  const _VerticalIntent(this.direction);
  final TraversalDirection direction;
}

class _VerticalAction extends Action<_VerticalIntent> {
  @override
  bool isEnabled(_VerticalIntent intent) {
    final t = _focusedField();
    return t == null || t.widget.maxLines == 1;
  }

  @override
  void invoke(_VerticalIntent intent) {
    FocusManager.instance.primaryFocus?.focusInDirection(intent.direction);
  }
}

/// Left/right: leave a text field only when the caret is collapsed at that
/// edge (empty counts as both); otherwise disabled, so the key falls through
/// to normal caret movement.
class _SideIntent extends Intent {
  const _SideIntent(this.direction);
  final TraversalDirection direction;
}

class _SideAction extends Action<_SideIntent> {
  @override
  bool isEnabled(_SideIntent intent) {
    final c = _focusedField()?.widget.controller;
    if (c == null) return true;
    final sel = c.selection;
    if (!sel.isValid) return true;
    final edge = intent.direction == TraversalDirection.left ? 0 : c.text.length;
    return sel.isCollapsed && sel.baseOffset == edge;
  }

  @override
  void invoke(_SideIntent intent) {
    FocusManager.instance.primaryFocus?.focusInDirection(intent.direction);
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}

/// Enter on a single-line text field opens the on-screen keyboard (handheld
/// only; [_navigatorKey] is null when disabled). Otherwise disabled, so Enter
/// falls through to activate/submit.
class _OskIntent extends Intent {
  const _OskIntent();
}

class _OskAction extends Action<_OskIntent> {
  _OskAction(this._navigatorKey);
  final GlobalKey<NavigatorState>? _navigatorKey;

  @override
  bool isEnabled(_OskIntent intent) {
    final t = _focusedField();
    return _navigatorKey?.currentState?.overlay != null && t != null && t.widget.maxLines == 1 && !t.widget.readOnly;
  }

  @override
  void invoke(_OskIntent intent) => showOnScreenKeyboard(_navigatorKey!.currentState!.overlay!, _focusedField()!);
}

/// Global d-pad/gamepad key map plus a visible focus outline.
/// Handheld gamepads reach the app as keys: D-pad=arrows, A=Enter, B=Escape,
/// L1/R1=PageUp/PageDown.
class DpadScope extends StatefulWidget {
  const DpadScope({super.key, required this.child, required this.navigatorKey, this.onScreenKeyboard = false});

  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Enter on a text field opens the in-app keyboard (no platform IME).
  final bool onScreenKeyboard;

  @override
  State<DpadScope> createState() => _DpadScopeState();
}

class _DpadScopeState extends State<DpadScope> {
  static const _pageSteps = 6;

  static final _shortcuts = <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowUp): const _VerticalIntent(TraversalDirection.up),
    const SingleActivator(LogicalKeyboardKey.arrowDown): const _VerticalIntent(TraversalDirection.down),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): const _SideIntent(TraversalDirection.left),
    const SingleActivator(LogicalKeyboardKey.arrowRight): const _SideIntent(TraversalDirection.right),
    const SingleActivator(LogicalKeyboardKey.pageUp): const PageFocusIntent(false),
    const SingleActivator(LogicalKeyboardKey.pageDown): const PageFocusIntent(true),
    const SingleActivator(LogicalKeyboardKey.escape): const _BackIntent(),
    const SingleActivator(LogicalKeyboardKey.enter): const _OskIntent(),
  };

  final _repaint = _Repaint();
  Rect? _painted; // rect last drawn by the painter; the frame callback diffs against it

  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_repaint.ping);
    FocusManager.instance.addHighlightModeListener(_onHighlight);
    // Persistent callbacks can't be removed, hence the _disposed guard.
    // ponytail: runs only after frames that render anyway; repaints just when
    // the focused rect moved (scrolling), so an idle app schedules no frames.
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      if (_disposed) return;
      if (_painted != _focusRect()) {
        _repaint.ping();
        // Persistent-callback phase: marking dirty alone schedules no frame.
        SchedulerBinding.instance.scheduleFrame();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    FocusManager.instance.removeListener(_repaint.ping);
    FocusManager.instance.removeHighlightModeListener(_onHighlight);
    _repaint.dispose();
    super.dispose();
  }

  void _onHighlight(FocusHighlightMode _) => _repaint.ping();

  Rect? _focusRect() {
    if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) {
      return null;
    }
    final node = FocusManager.instance.primaryFocus;
    final ctx = node?.context;
    if (node == null || node is FocusScopeNode || ctx is! Element) return null;
    // Elements replaced during layout stay deactivated until the frame ends;
    // findRenderObject() asserts on them (release builds fall to `attached`).
    if (kDebugMode && !ctx.debugIsActive) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return node.rect;
  }

  // Not DismissIntent: a page route registers a disabled DismissIntent action
  // that would shadow ours. Dialogs/sheets keep handling Escape themselves.
  void _back() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx != null && ModalRoute.of(ctx) is PopupRoute) {
      Actions.maybeInvoke(ctx, const DismissIntent());
    } else {
      widget.navigatorKey.currentState?.maybePop();
    }
  }

  void _pageFocus(bool forward) {
    final dir = forward ? TraversalDirection.down : TraversalDirection.up;
    var moved = false;
    for (var i = 0; i < _pageSteps; i++) {
      final node = FocusManager.instance.primaryFocus;
      if (node == null || !node.focusInDirection(dir)) break;
      // Focus changes are otherwise applied in a microtask, after this loop.
      FocusManager.instance.applyFocusChangesIfNeeded();
      if (FocusManager.instance.primaryFocus == node) break;
      moved = true;
    }
    // Nothing to focus (text-only view): keep the stock page scroll.
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (!moved && ctx != null) {
      Actions.maybeInvoke(
        ctx,
        ScrollIntent(direction: forward ? AxisDirection.down : AxisDirection.up, type: ScrollIncrementType.page),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Shortcuts(
      shortcuts: _shortcuts,
      child: Actions(
        actions: {
          PageFocusIntent: CallbackAction<PageFocusIntent>(
            onInvoke: (i) => _pageFocus(i.forward),
          ),
          _VerticalIntent: _VerticalAction(),
          _SideIntent: _SideAction(),
          _BackIntent: CallbackAction<_BackIntent>(
            onInvoke: (_) => _back(),
          ),
          _OskIntent: _OskAction(widget.onScreenKeyboard ? widget.navigatorKey : null),
        },
        child: Stack(
          textDirection: TextDirection.ltr,
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    key: const ValueKey('dpad-focus-outline'),
                    painter: _OutlinePainter(this, color, _repaint),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _OutlinePainter extends CustomPainter {
  _OutlinePainter(this._state, this._color, Listenable repaint) : super(repaint: repaint);

  final _DpadScopeState _state;
  final Color _color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _state._painted = _state._focusRect();
    if (rect == null) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(2), const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = _color,
    );
  }

  @override
  bool shouldRepaint(_OutlinePainter old) => old._color != _color;
}
